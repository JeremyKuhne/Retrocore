// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Buffers;
using System.Collections.Concurrent;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Retrocore.Debug;

/// <summary>
///  The Debug Adapter Protocol over <see cref="MessageFraming"/>: requests are answered one at a time, in the order
///  they arrive; events may be sent from any thread between them.
/// </summary>
/// <remarks>
///  <para>
///   A handler takes a request's <c>arguments</c> and returns its response's <c>body</c>. A handler that throws
///   answers with <c>success: false</c> and the exception's message, which VS Code shows; so does a request with no
///   handler. The debug host never sends requests of its own to VS Code, so there are no responses to wait for.
///  </para>
/// </remarks>
/// <param name="input">Where requests arrive, such as standard input.</param>
/// <param name="output">Where responses and events go, such as standard output.</param>
/// <param name="read">
///  An optional read for input that does not support cancellation through
///  <see cref="Stream.ReadAsync(Memory{byte}, CancellationToken)"/>.
/// </param>
internal sealed class DapTransport(Stream input, Stream output, Func<Memory<byte>, CancellationToken, int>? read = null)
{
    private const int OutputDrainMilliseconds = 2_000;

    private readonly MessageFraming _wire = new(input, output, read ?? ((bytes, token) => input.ReadAsync(bytes, token).AsTask().GetAwaiter().GetResult()));
    private readonly Dictionary<string, Func<JsonObject, (JsonNode? Body, Action? FollowUp)>> _handlers = [with(StringComparer.Ordinal)];
    private readonly object _outboundGate = new();
    private Queue<(Action Write, Action? Release, int Weight)> _outbound = new();

    // Numbered as each message is written, under the wire's lock, so the numbers go out in order.
    private int _sequence;
    private int _outboundWeight;
    private volatile bool _buffering;
    private volatile bool _outputFailed;
    private bool _finished;
    private volatile bool _stopped;
    private readonly CancellationTokenSource _stopReading = new();
    private readonly Dictionary<int, CancellationTokenSource> _pendingLaunches = [];
    private CancellationToken _launchCancellation;

    /// <summary>
    ///  Whether the emulator should yield instead of producing more events. Requests can still use the machine.
    /// </summary>
    internal bool Backpressured => Volatile.Read(ref _outboundWeight) >= 64;

    /// <summary>
    ///  Gets whether the wire can no longer deliver output.
    /// </summary>
    internal bool OutputFailed => _outputFailed;

    /// <summary>
    ///  Registers the handler for a request.
    /// </summary>
    /// <param name="command">The request's command, such as <c>launch</c>.</param>
    /// <param name="handler">Takes the request's arguments and returns the response's body.</param>
    /// <exception cref="InvalidOperationException">The command already has a handler.</exception>
    internal void On(string command, Func<JsonObject, JsonNode?> handler) =>
        OnWithFollowUp(command, args => (handler(args), null));

    /// <summary>
    ///  Registers a request handler that can schedule work after its successful response is queued, before the next request.
    /// </summary>
    /// <param name="command">The request's command.</param>
    /// <param name="handler">Takes the arguments and returns a response body and optional follow-up.</param>
    internal void OnWithFollowUp(string command, Func<JsonObject, (JsonNode? Body, Action? FollowUp)> handler)
    {
        if (!_handlers.TryAdd(command, handler))
        {
            throw new InvalidOperationException($"The {command} request already has a handler.");
        }
    }

    /// <summary>
    ///  Sends an event, from any thread.
    /// </summary>
    /// <param name="name">The event, such as <c>stopped</c>.</param>
    /// <param name="body">Its body.</param>
    internal void SendEvent(string name, JsonNode? body) =>
        Write(new JsonObject { ["type"] = "event", ["event"] = name, ["body"] = body });

    /// <summary>
    ///  Sends a frame without borrowing pixel memory from the caller past this call.
    /// </summary>
    /// <param name="state">The owned display state, without pixels.</param>
    /// <param name="pixels">The RGBA bytes, empty for an unchanged frame.</param>
    internal void SendFrame(JsonObject state, ReadOnlyMemory<byte> pixels)
    {
        if (!_buffering || pixels.IsEmpty)
        {
            SendEvent("retro/frame", writer => DisplayFrameWriter.Write(writer, state, pixels.Span));
            return;
        }

        byte[] rented = ArrayPool<byte>.Shared.Rent(pixels.Length);
        Memory<byte> owned = rented.AsMemory(0, pixels.Length);
        pixels.CopyTo(owned);
        SendEvent("retro/frame", writer => DisplayFrameWriter.Write(writer, state, owned.Span),
            release: () => ArrayPool<byte>.Shared.Return(rented), weight: 1 + (owned.Length / 8192));
    }

    /// <summary>
    ///  Sends an event whose body is written straight to the wire, from any thread, so a large body, such as a frame's
    ///  pixels, needs no node or string the size of it.
    /// </summary>
    /// <param name="name">The event, such as <c>retro/frame</c>.</param>
    /// <param name="writeBody">Writes the body: one JSON value.</param>
    /// <param name="release">Releases the owned body after the write or if the pipe has failed.</param>
    /// <param name="weight">Relative pressure on the output queue.</param>
    internal void SendEvent(string name, Action<Utf8JsonWriter> writeBody, Action? release = null, int weight = 1) =>
        Enqueue(() => _wire.Write(writer =>
        {
            writer.WriteStartObject();
            writer.WriteNumber("seq", ++_sequence);
            writer.WriteString("type", "event");
            writer.WriteString("event", name);
            writer.WritePropertyName("body");
            writeBody(writer);
            writer.WriteEndObject();
        }), release, weight);

    /// <summary>
    ///  Stops reading once the request being answered has its response.
    /// </summary>
    internal void Stop()
    {
        _stopped = true;
        _stopReading.Cancel();
    }

    /// <summary>
    ///  Stops a launch when the reader sees its cancellation request.
    /// </summary>
    internal void ThrowIfLaunchCancelled() => _launchCancellation.ThrowIfCancellationRequested();

    /// <summary>
    ///  Answers requests until <see cref="Stop"/> or the end of the input.
    /// </summary>
    internal void Run() => Run(end: null);

    /// <summary>
    ///  Answers requests, then finishes the session and allows a bounded time to drain its ordered output.
    /// </summary>
    /// <param name="end">Retires any event producers before the writer shuts down.</param>
    /// <param name="outputDrainMilliseconds">How long shutdown allows the peer to drain the output.</param>
    internal void Run(Action? end, int outputDrainMilliseconds = OutputDrainMilliseconds)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(outputDrainMilliseconds);
        _buffering = true;
        Thread writer = new(WriteLoop) { IsBackground = true, Name = "Retrocore DAP output" };
        writer.Start();
        try
        {
            ReadLoop();
        }
        finally
        {
            try
            {
                end?.Invoke();
            }
            finally
            {
                lock (_outboundGate)
                {
                    _finished = true;
                    Monitor.Pulse(_outboundGate);
                }

                if (!writer.Join(outputDrainMilliseconds)) { AbandonOutput(); }
            }
        }
    }

    private void AbandonOutput()
    {
        // A synchronous pipe write need not be interruptible. The background writer still owns its in-flight
        // message, but cannot take any of the queued messages after this point or hold the host open.
        Queue<(Action Write, Action? Release, int Weight)> pending;
        lock (_outboundGate)
        {
            _outputFailed = true;
            pending = _outbound;
            _outbound = new();
        }

        Console.Error.WriteLine("DAP output did not drain before shutdown; undelivered messages were discarded.");
        foreach (var item in pending)
        {
            item.Release?.Invoke();
            Interlocked.Add(ref _outboundWeight, -item.Weight);
        }
    }

    private void ReadLoop()
    {
        // A paced image boot can wait for minutes. Read cancellation ahead without dispatching handlers out of order.
        BlockingCollection<(JsonObject Message, TaskCompletionSource? Disconnect)> requests = [with(boundedCapacity: 256)];
        Task reader = Task.Factory.StartNew(
            () => ReadRequests(requests), CancellationToken.None, TaskCreationOptions.LongRunning, TaskScheduler.Default);

        foreach ((JsonObject message, TaskCompletionSource? disconnect) in requests.GetConsumingEnumerable())
        {
            if (_stopped) { break; }
            int? launch = ReadAhead<string>(message, "command") == "launch"
                ? ReadAheadInt(message, "seq")
                : null;

            if (launch is int current)
            {
                lock (_pendingLaunches)
                {
                    if (_pendingLaunches.TryGetValue(current, out CancellationTokenSource? pending))
                    {
                        _launchCancellation = pending.Token;
                    }
                }
            }

            try
            {
                Answer(message);
            }
            finally
            {
                disconnect?.SetResult();
                if (launch is int completed)
                {
                    _launchCancellation = default;
                    lock (_pendingLaunches)
                    {
                        if (_pendingLaunches.Remove(completed, out CancellationTokenSource? pending))
                        {
                            pending.Dispose();
                        }
                    }
                }
            }

            if (_stopped) { break; }
        }

        reader.GetAwaiter().GetResult();
    }

    private void ReadRequests(BlockingCollection<(JsonObject Message, TaskCompletionSource? Disconnect)> requests)
    {
        try { ReadRequestsUntilStopped(requests); }
        catch (OperationCanceledException) when (_stopped) { }
        finally { requests.CompleteAdding(); }
    }

    private void ReadRequestsUntilStopped(BlockingCollection<(JsonObject Message, TaskCompletionSource? Disconnect)> requests)
    {
        while (!_stopped)
        {
            JsonObject? message;
            try
            {
                message = _wire.Read(_stopReading.Token);
            }
            catch (JsonException exception)
            {
                // Without a sequence number there is no request to answer; skip the message and read on.
                Console.Error.WriteLine($"Ignored a DAP message that is not JSON: {exception.Message}");
                continue;
            }

            if (message is null || _stopped) { return; }
            if (ReadAhead<string>(message, "type") != "request") { continue; }
            string? command = ReadAhead<string>(message, "command");
            lock (_pendingLaunches)
            {
                if (command == "launch"
                    && ReadAheadInt(message, "seq") is int sequence
                    && !_pendingLaunches.ContainsKey(sequence))
                {
                    _pendingLaunches.Add(sequence, new());
                }
                else if (command == "cancel"
                    && message["arguments"] is JsonObject arguments
                    && ReadAheadInt(arguments, "requestId") is int requestId
                    && _pendingLaunches.TryGetValue(requestId, out CancellationTokenSource? pending))
                {
                    pending.Cancel();
                }
                else if (command == "disconnect")
                {
                    CancelPendingLaunches();
                }
            }

            // A successful disconnect stops the transport. Don't enter another blocking read before it is handled.
            TaskCompletionSource? disconnect = command == "disconnect" ? new(TaskCreationOptions.RunContinuationsAsynchronously) : null;
            requests.Add((message, disconnect), _stopReading.Token);
            disconnect?.Task.WaitAsync(_stopReading.Token).GetAwaiter().GetResult();
        }
    }

    private static T? ReadAhead<T>(JsonObject message, string field) =>
        message[field] is JsonValue json && json.TryGetValue(out T? value) ? value : default;

    private static int? ReadAheadInt(JsonObject message, string field) =>
        message[field] is JsonValue json && json.TryGetValue(out int value) ? value : null;

    private void CancelPendingLaunches()
    {
        foreach (CancellationTokenSource launch in _pendingLaunches.Values) { launch.Cancel(); }
    }

    private void Enqueue(Action write, Action? release = null, int weight = 1)
    {
        if (!_buffering)
        {
            try { write(); }
            finally { release?.Invoke(); }
            return;
        }

        lock (_outboundGate)
        {
            if (!_finished && !_outputFailed)
            {
                _outbound.Enqueue((write, release, weight));
                Interlocked.Add(ref _outboundWeight, weight);
                Monitor.Pulse(_outboundGate);
                return;
            }
        }

        release?.Invoke();
    }

    private void WriteLoop()
    {
        while (true)
        {
            (Action write, Action? release, int weight) item;
            lock (_outboundGate)
            {
                while (_outbound.Count == 0 && !_finished) { Monitor.Wait(_outboundGate); }
                if (!_outbound.TryDequeue(out item)) { return; }
            }

            try
            {
                if (!_outputFailed) { item.write(); }
            }
            catch (Exception exception) when (exception is IOException or ObjectDisposedException or InvalidOperationException or JsonException)
            {
                _outputFailed = true;
                Stop();
                lock (_pendingLaunches) { CancelPendingLaunches(); }
                Console.Error.WriteLine($"DAP output failed: {exception.Message}");
            }
            finally
            {
                item.release?.Invoke();
                Interlocked.Add(ref _outboundWeight, -item.weight);
            }
        }
    }

    private void Answer(JsonObject request)
    {
        string command = "";
        JsonObject response = new() { ["type"] = "response" };
        Action? followUp = null;
        try
        {
            command = request.String("command") ?? "";
            response["request_seq"] = request.Int("seq") ?? 0;
            response["command"] = command;
            if (!_handlers.TryGetValue(command, out var handler))
            {
                throw new NotSupportedException($"The debug host does not handle the {command} request.");
            }

            (JsonNode? body, Action? afterResponse) = handler(request.Object("arguments") ?? []);
            response["body"] = body;
            response["success"] = true;
            followUp = afterResponse;
        }
#pragma warning disable CA1031 // Any failure in a handler is the request's failure, reported to VS Code.
        catch (Exception exception)
#pragma warning restore CA1031
        {
            response["request_seq"] ??= 0;
            response["command"] ??= command;
            response["success"] = false;
            response["message"] = exception.Message;
        }

        Write(response);
        followUp?.Invoke();
    }

    private void Write(JsonObject message) => Enqueue(() => _wire.Write(writer =>
    {
        message["seq"] = ++_sequence;
        message.WriteTo(writer);
    }));
}
