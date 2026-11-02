// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text;
using System.Text.Json.Nodes;
using Retrocore.Debug;
using Retrocore.Debug.Language;

namespace Retrocore.Tests;

/// <summary>
///  Verifies the language server's JSON-RPC: answers by id, errors, notifications in order, and the lifecycle.
/// </summary>
[TestClass]
public sealed class JsonRpcServerTests
{
    /// <summary>
    ///  Each request gets its id back with the handler's result, a null result included.
    /// </summary>
    /// <returns>A task.</returns>
    [TestMethod]
    public async Task AnswersRequestsByTheirIds()
    {
        List<JsonObject> messages = await Serve(
            server =>
            {
                server.OnRequest("echo", parameters => new JsonObject { ["value"] = parameters.Int("value") });
                server.OnRequest("shutdown", (JsonObject? _) => (JsonNode?)null);
            },
            Request(1, "echo", new JsonObject { ["value"] = 5 }),
            Request("two", "shutdown", parameters: null),
            Notification("exit", parameters: null));

        JsonObject echo = messages.Single(message => message["id"]?.ToJsonString() == "1");
        echo.Object("result").Int("value").Should().Be(5);
        echo.String("jsonrpc").Should().Be("2.0");
        JsonObject shutdown = messages.Single(message => message["id"]?.ToJsonString() == "\"two\"");
        shutdown.ContainsKey("result").Should().BeTrue("a null result is still a result");
        shutdown["result"].Should().BeNull();
    }

    /// <summary>
    ///  An unknown request answers method not found; a handler that throws answers internal error with its message;
    ///  an unknown notification, such as a cancellation, is ignored.
    /// </summary>
    /// <returns>A task.</returns>
    [TestMethod]
    public async Task ReportsErrors()
    {
        List<JsonObject> messages = await Serve(
            server => server.OnRequest("fails", (Func<JsonObject?, JsonNode?>)(_ => throw new InvalidOperationException("no analysis"))),
            Request(1, "missing", parameters: null),
            Request(2, "fails", parameters: null),
            Notification("$/cancelRequest", new JsonObject { ["id"] = 1 }));

        messages.Should().HaveCount(2);
        messages.Single(message => message.Int("id") == 1).Object("error").Int("code").Should().Be(-32601);
        JsonObject failed = messages.Single(message => message.Int("id") == 2);
        failed.Object("error").Int("code").Should().Be(-32603);
        failed.Object("error").String("message").Should().Be("no analysis");
        failed.ContainsKey("result").Should().BeFalse();
    }

    /// <summary>
    ///  Notifications run in the order they arrive, and diagnostics go out as LSP's notification.
    /// </summary>
    /// <returns>A task.</returns>
    [TestMethod]
    public async Task HandlesNotificationsInOrderAndPublishes()
    {
        List<string> seen = [];
        Diagnostic odd = new()
        {
            Range = new LspRange(1, 2, 1, 5),
            Severity = DiagnosticSeverity.Warning,
            Message = "odd"
        };

        List<JsonObject> messages = await Serve(
            server =>
            {
                server.OnNotification("note", parameters => seen.Add(parameters.String("text") ?? ""));
                server.OnNotification("publish", _ => server.PublishDiagnostics(new DocumentUri("file:///c%3A/a.asm"), [odd]));
            },
            Notification("note", new JsonObject { ["text"] = "a" }),
            Notification("note", new JsonObject { ["text"] = "b" }),
            Notification("publish", parameters: null),
            Notification("note", new JsonObject { ["text"] = "c" }));

        seen.Should().Equal("a", "b", "c");
        JsonObject published = messages.Should().ContainSingle().Subject;
        published.String("method").Should().Be("textDocument/publishDiagnostics");
        published.Object("params").String("uri").Should().Be("file:///c%3A/a.asm");
        JsonObject diagnostic = published.Object("params").Array("diagnostics")?[0] as JsonObject ?? [];
        diagnostic.Int("severity").Should().Be(2);
        diagnostic.Object("range").Object("end").Int("character").Should().Be(5);
    }

    /// <summary>
    ///  Exit ends the server; nothing after it is read.
    /// </summary>
    /// <returns>A task.</returns>
    [TestMethod]
    public async Task StopsAtExit()
    {
        List<JsonObject> messages = await Serve(
            server => server.OnRequest("echo", (JsonObject? _) => new JsonObject()),
            Notification("exit", parameters: null),
            Request(1, "echo", parameters: null));

        messages.Should().BeEmpty();
    }

    private static async Task<List<JsonObject>> Serve(Action<JsonRpcServer> register, params byte[][] messages)
    {
        MemoryStream output = new();
        JsonRpcServer server = new(new MemoryStream([.. messages.SelectMany(message => message)]), output);
        register(server);
        await server.Run();
        List<JsonObject> written = [];
        MessageFraming framing = new(new MemoryStream(output.ToArray()), Stream.Null);
        while (framing.Read() is { } message) { written.Add(message); }
        return written;
    }

    private static byte[] Request(JsonNode id, string method, JsonObject? parameters) =>
        Frame(new JsonObject { ["jsonrpc"] = "2.0", ["id"] = id, ["method"] = method, ["params"] = parameters });

    private static byte[] Notification(string method, JsonObject? parameters) =>
        Frame(new JsonObject { ["jsonrpc"] = "2.0", ["method"] = method, ["params"] = parameters });

    private static byte[] Frame(JsonObject message)
    {
        byte[] json = Encoding.UTF8.GetBytes(message.ToJsonString());
        return [.. Encoding.ASCII.GetBytes($"Content-Length: {json.Length}\r\n\r\n"), .. json];
    }
}
