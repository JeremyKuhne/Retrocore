// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json;
using System.Text.Json.Nodes;

namespace Retrocore.Debug.Language;

/// <summary>
///  The Language Server Protocol's JSON-RPC 2.0 over <see cref="MessageFraming"/>: the server side of requests and
///  notifications, and the lifecycle from <c>initialize</c> to <c>exit</c>.
/// </summary>
/// <remarks>
///  <para>
///   Notifications, such as a document opening or changing, are handled in the order they arrive, before anything
///   read after them. Requests run concurrently, as a document's outline may wait for its analysis while hovers go
///   on; each answers when it finishes. A request whose handler throws answers with JSON-RPC's internal error and the
///   exception's message; an unknown request answers method not found, and an unknown notification, such as
///   <c>$/cancelRequest</c>, is ignored.
///  </para>
/// </remarks>
/// <param name="input">Where messages arrive, such as standard input.</param>
/// <param name="output">Where messages go, such as standard output.</param>
internal sealed class JsonRpcServer(Stream input, Stream output) : ILanguageClient
{
    private const int MethodNotFound = -32601;
    private const int InternalError = -32603;
    private readonly MessageFraming _wire = new(input, output);
    private readonly Dictionary<string, Func<JsonObject?, Task<JsonNode?>>> _requests = new(StringComparer.Ordinal);
    private readonly Dictionary<string, Action<JsonObject?>> _notifications = new(StringComparer.Ordinal);
    private readonly List<Task> _running = [];

    /// <summary>
    ///  Registers the handler for a request.
    /// </summary>
    /// <param name="method">The method, such as <c>textDocument/hover</c>.</param>
    /// <param name="handler">Takes the request's params and returns its result, which may be null.</param>
    internal void OnRequest(string method, Func<JsonObject?, Task<JsonNode?>> handler) => _requests.Add(method, handler);

    /// <summary>
    ///  Registers the handler for a request that answers at once.
    /// </summary>
    /// <param name="method">The method.</param>
    /// <param name="handler">Takes the request's params and returns its result.</param>
    internal void OnRequest(string method, Func<JsonObject?, JsonNode?> handler) =>
        _requests.Add(method, parameters => Task.FromResult(handler(parameters)));

    /// <summary>
    ///  Registers the handler for a notification.
    /// </summary>
    /// <param name="method">The method, such as <c>textDocument/didOpen</c>.</param>
    /// <param name="handler">Takes the notification's params.</param>
    internal void OnNotification(string method, Action<JsonObject?> handler) => _notifications.Add(method, handler);

    /// <summary>
    ///  Sends a notification, from any thread.
    /// </summary>
    /// <param name="method">The method.</param>
    /// <param name="parameters">Its params.</param>
    internal void Notify(string method, JsonNode? parameters) =>
        _wire.Write(new JsonObject { ["jsonrpc"] = "2.0", ["method"] = method, ["params"] = parameters });

    /// <inheritdoc/>
    public void PublishDiagnostics(DocumentUri uri, IEnumerable<Diagnostic> diagnostics) => Notify(
        "textDocument/publishDiagnostics",
        new JsonObject
        {
            ["uri"] = uri.Text,
            ["diagnostics"] = diagnostics.Select(diagnostic => (JsonNode?)diagnostic.ToJson()).ToJsonArray()
        });

    /// <summary>
    ///  Serves until the client sends <c>exit</c> or the input ends, then lets the requests still running finish.
    /// </summary>
    /// <returns>The task.</returns>
    internal async Task Run()
    {
        while (true)
        {
            JsonObject? message;
            try
            {
                message = _wire.Read();
            }
            catch (JsonException exception)
            {
                Console.Error.WriteLine($"Ignored an LSP message that is not JSON: {exception.Message}");
                continue;
            }

            if (message is null || message.String("method") == "exit") { break; }
            if (message.String("method") is not { } method) { continue; }
            JsonObject? parameters = message["params"] as JsonObject;
            if (message["id"] is { } id)
            {
                lock (_running)
                {
                    _running.RemoveAll(task => task.IsCompleted);
                    _running.Add(Answer(id.DeepClone(), method, parameters));
                }
            }
            else if (_notifications.TryGetValue(method, out Action<JsonObject?>? handler))
            {
                Handle(method, handler, parameters);
            }
        }

        Task[] running;
        lock (_running) { running = [.. _running]; }
        await Task.WhenAll(running).ConfigureAwait(continueOnCapturedContext: false);
    }

    private static void Handle(string method, Action<JsonObject?> handler, JsonObject? parameters)
    {
        try
        {
            handler(parameters);
        }
#pragma warning disable CA1031 // A notification has no answer to fail; the server goes on.
        catch (Exception exception)
#pragma warning restore CA1031
        {
            Console.Error.WriteLine($"The {method} notification failed: {exception}");
        }
    }

    private async Task Answer(JsonNode id, string method, JsonObject? parameters)
    {
        JsonObject response = new() { ["jsonrpc"] = "2.0", ["id"] = id };
        if (!_requests.TryGetValue(method, out Func<JsonObject?, Task<JsonNode?>>? handler))
        {
            response["error"] = new JsonObject
            {
                ["code"] = MethodNotFound,
                ["message"] = $"There is no {method} method."
            };

            _wire.Write(response);
            return;
        }

        try
        {
            // Off the reading thread, so a request that waits does not hold up the messages after it.
            response["result"] = await Task.Run(() => handler(parameters)).ConfigureAwait(continueOnCapturedContext: false);
        }
#pragma warning disable CA1031 // Any failure in a handler is the request's failure, reported to the client.
        catch (Exception exception)
#pragma warning restore CA1031
        {
            response.Remove("result");
            response["error"] = new JsonObject { ["code"] = InternalError, ["message"] = exception.Message };
        }

        _wire.Write(response);
    }
}
