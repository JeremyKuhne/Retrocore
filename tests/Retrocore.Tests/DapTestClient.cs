// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug;
using System.Collections.Concurrent;
using System.IO.Pipes;
using System.Text;
using System.Text.Json.Nodes;
using Touki;

namespace Retrocore.Tests;

/// <summary>
///  A debug client for tests that must see responses before sending the next request: it talks to a
///  <see cref="DebugSession"/> over pipes, with the session's transport on its own thread. Requests wait for their
///  responses; events queue until a test waits for them.
/// </summary>
internal sealed class DapTestClient : DisposableBase
{
    private static readonly TimeSpan s_timeout = TimeSpan.FromSeconds(30);

    private readonly AnonymousPipeServerStream _toHost = new(PipeDirection.Out);
    private readonly AnonymousPipeClientStream _hostInput;
    private readonly AnonymousPipeServerStream _fromHost = new(PipeDirection.In);
    private readonly AnonymousPipeClientStream _hostOutput;
    private readonly DebugSession _session = new();
    private readonly Thread _host;
    private readonly Thread _reader;
    private readonly BlockingCollection<JsonObject> _responses = [];
    private readonly BlockingCollection<JsonObject> _events = [];
    private int _sequence;

    /// <summary>
    ///  Starts a session and the thread that reads its messages.
    /// </summary>
    internal DapTestClient()
    {
        _hostInput = new(PipeDirection.In, _toHost.ClientSafePipeHandle);
        _hostOutput = new(PipeDirection.Out, _fromHost.ClientSafePipeHandle);
        DapTransport transport = new(_hostInput, _hostOutput);
        _session.Register(transport, transport.Stop);
        _host = new(() => transport.Run(_session.End)) { IsBackground = true };

        _reader = new(Read) { IsBackground = true };
        _host.Start();
        _reader.Start();
    }

    /// <summary>
    ///  Sends a request and waits for its response, which must succeed.
    /// </summary>
    /// <param name="command">The request's command, such as <c>launch</c>.</param>
    /// <param name="arguments">Its arguments.</param>
    /// <returns>The response's body, or an empty object when it has none.</returns>
    internal JsonObject Request(string command, JsonObject arguments) => Request(command, arguments, out _);

    /// <inheritdoc cref="Request(string, JsonObject)"/>
    /// <param name="sequence">The response's position on the wire.</param>
    internal JsonObject Request(string command, JsonObject arguments, out int? sequence)
    {
        JsonObject response = Send(command, arguments);
        response.Bool("success").Should().BeTrue($"{command} failed: {response.String("message")}");
        sequence = response.Int("seq");
        return response["body"] as JsonObject ?? [];
    }

    /// <summary>
    ///  Sends a request that must fail, and waits for its response.
    /// </summary>
    /// <param name="command">The request's command, such as <c>launch</c>.</param>
    /// <param name="arguments">Its arguments.</param>
    /// <returns>The response's message.</returns>
    internal string Fails(string command, JsonObject arguments)
    {
        JsonObject response = Send(command, arguments);
        response.Bool("success").Should().BeFalse($"{command} should fail");
        return response.String("message") ?? "";
    }

    private JsonObject Send(string command, JsonObject arguments)
    {
        int seq = ++_sequence;
        byte[] json = Encoding.UTF8.GetBytes(new JsonObject
        {
            ["seq"] = seq,
            ["type"] = "request",
            ["command"] = command,
            ["arguments"] = arguments
        }.ToJsonString());

        _toHost.Write([.. Encoding.ASCII.GetBytes($"Content-Length: {json.Length}\r\n\r\n"), .. json]);
        _toHost.Flush();
        if (!_responses.TryTake(out JsonObject? response, s_timeout))
        {
            throw new AssertFailedException($"{command} has no response.");
        }

        response.Int("request_seq").Should().Be(seq);
        return response;
    }

    /// <summary>
    ///  Waits for the next event with a name, passing over other events.
    /// </summary>
    /// <param name="name">The event, such as <c>stopped</c>.</param>
    /// <returns>The event's body.</returns>
    internal JsonObject Event(string name) => Event(name, out _);

    /// <inheritdoc cref="Event(string)"/>
    /// <param name="sequence">The event's position on the wire.</param>
    internal JsonObject Event(string name, out int? sequence)
    {
        DateTime end = DateTime.UtcNow + s_timeout;
        while (_events.TryTake(out JsonObject? message, Remaining(end)))
        {
            if (message.String("event") == name)
            {
                sequence = message.Int("seq");
                return message["body"] as JsonObject ?? [];
            }
        }

        throw new AssertFailedException($"No {name} event came.");
    }

    /// <summary>
    ///  Checks that no stopped event comes for a while, passing over other events.
    /// </summary>
    /// <param name="wait">How long to watch.</param>
    /// <param name="because">Why no stop should come, for the failure.</param>
    internal void NoStop(TimeSpan wait, string because)
    {
        DateTime end = DateTime.UtcNow + wait;
        while (_events.TryTake(out JsonObject? message, Remaining(end)))
        {
            message.String("event").Should().NotBe("stopped", because);
        }
    }

    /// <summary>
    ///  Checks that no event with a name comes for a while, passing over other events.
    /// </summary>
    /// <param name="name">The event that must not come.</param>
    /// <param name="wait">How long to watch.</param>
    internal void NoEvent(string name, TimeSpan wait)
    {
        DateTime end = DateTime.UtcNow + wait;
        while (_events.TryTake(out JsonObject? message, Remaining(end)))
        {
            message.String("event").Should().NotBe(name);
        }
    }

    private static TimeSpan Remaining(DateTime end)
    {
        TimeSpan left = end - DateTime.UtcNow;
        return left > TimeSpan.Zero ? left : TimeSpan.Zero;
    }

    private void Read()
    {
        try
        {
            while (ReadMessage() is { } message)
            {
                (message.String("type") == "response" ? _responses : _events).Add(message);
            }
        }
        catch (Exception exception) when (exception is IOException or ObjectDisposedException)
        {
            // The host has gone, or the client is closing.
        }
    }

    // One message: its Content-Length header, then its JSON body; null at the end of the output.
    private JsonObject? ReadMessage()
    {
        List<byte> header = [];
        while (header.Count < 4 || !header[^4..].SequenceEqual("\r\n\r\n"u8.ToArray()))
        {
            int next = _fromHost.ReadByte();
            if (next < 0) { return null; }
            header.Add((byte)next);
        }

        const string Prefix = "Content-Length: ";
        string[] lines = Encoding.ASCII.GetString([.. header]).Split("\r\n");
        string length = lines.Single(line => line.StartsWith(Prefix, StringComparison.Ordinal))[Prefix.Length..];
        byte[] body = new byte[int.Parse(length, System.Globalization.CultureInfo.InvariantCulture)];
        _fromHost.ReadExactly(body);
        return JsonNode.Parse(body) as JsonObject;
    }

    /// <summary>
    ///  Closes the session's input, which ends its transport, then ends the session, which stops a running machine,
    ///  before closing its output, so nothing writes an event to a closed pipe.
    /// </summary>
    /// <param name="disposing">Whether it is disposing rather than finalizing.</param>
    protected override void Dispose(bool disposing)
    {
        if (!disposing) { return; }
        _toHost.Dispose();
        _host.Join(s_timeout);
        try
        {
            _session.End();
        }
        finally
        {
            _hostOutput.Dispose();
            _reader.Join(s_timeout);
        }

        _hostInput.Dispose();
        _fromHost.Dispose();
        _responses.Dispose();
        _events.Dispose();
    }
}
