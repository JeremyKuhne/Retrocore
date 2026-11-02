// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

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
internal sealed class DapTransport(Stream input, Stream output)
{
    private readonly MessageFraming _wire = new(input, output);
    private readonly Dictionary<string, Func<JsonObject, JsonNode?>> _handlers = new(StringComparer.Ordinal);

    // Numbered as each message is written, under the wire's lock, so the numbers go out in order.
    private int _sequence;
    private volatile bool _stopped;

    /// <summary>
    ///  Registers the handler for a request.
    /// </summary>
    /// <param name="command">The request's command, such as <c>launch</c>.</param>
    /// <param name="handler">Takes the request's arguments and returns the response's body.</param>
    /// <exception cref="InvalidOperationException">The command already has a handler.</exception>
    internal void On(string command, Func<JsonObject, JsonNode?> handler)
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
    ///  Sends an event whose body is written straight to the wire, from any thread, so a large body, such as a frame's
    ///  pixels, needs no node or string the size of it.
    /// </summary>
    /// <param name="name">The event, such as <c>retro/frame</c>.</param>
    /// <param name="writeBody">Writes the body: one JSON value.</param>
    internal void SendEvent(string name, Action<Utf8JsonWriter> writeBody) => _wire.Write(writer =>
    {
        writer.WriteStartObject();
        writer.WriteNumber("seq", ++_sequence);
        writer.WriteString("type", "event");
        writer.WriteString("event", name);
        writer.WritePropertyName("body");
        writeBody(writer);
        writer.WriteEndObject();
    });

    /// <summary>
    ///  Stops reading once the request being answered has its response.
    /// </summary>
    internal void Stop() => _stopped = true;

    /// <summary>
    ///  Answers requests until <see cref="Stop"/> or the end of the input.
    /// </summary>
    internal void Run()
    {
        while (!_stopped)
        {
            JsonObject? message;
            try
            {
                message = _wire.Read();
            }
            catch (JsonException exception)
            {
                // Without a sequence number there is no request to answer; skip the message and read on.
                Console.Error.WriteLine($"Ignored a DAP message that is not JSON: {exception.Message}");
                continue;
            }

            if (message is null) { return; }
            if (message.String("type") == "request") { Answer(message); }
        }
    }

    private void Answer(JsonObject request)
    {
        string command = "";
        JsonObject response = new() { ["type"] = "response" };
        try
        {
            command = request.String("command") ?? "";
            response["request_seq"] = request.Int("seq") ?? 0;
            response["command"] = command;
            if (!_handlers.TryGetValue(command, out Func<JsonObject, JsonNode?>? handler))
            {
                throw new NotSupportedException($"The debug host does not handle the {command} request.");
            }

            response["body"] = handler(request.Object("arguments") ?? []);
            response["success"] = true;
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
    }

    private void Write(JsonObject message) => _wire.Write(writer =>
    {
        message["seq"] = ++_sequence;
        message.WriteTo(writer);
    });
}
