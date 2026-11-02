// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text;
using System.Text.Json.Nodes;
using Retrocore.Debug;

namespace Retrocore.Tests;

/// <summary>
///  Verifies the Debug Adapter Protocol's wire: framing, answers, errors and events.
/// </summary>
[TestClass]
public sealed class DapTransportTests
{
    /// <summary>
    ///  Each request gets a response with its sequence number, command and the handler's body, numbered in order.
    /// </summary>
    [TestMethod]
    public void AnswersEachRequestInOrder()
    {
        List<JsonObject> messages = Exchange(
            transport => transport.On("echo", args => new JsonObject { ["value"] = args["value"]?.DeepClone() }),
            Request(7, "echo", new JsonObject { ["value"] = 1 }),
            Request(8, "echo", new JsonObject { ["value"] = 2 }));

        messages.Should().HaveCount(2);
        messages.Select(message => message.Int("seq")).Should().Equal(1, 2);
        messages.Select(message => message.Int("request_seq")).Should().Equal(7, 8);
        messages.Select(message => message.String("type")).Should().AllBe("response");
        messages.Select(message => message.Bool("success")).Should().AllBeEquivalentTo(expectation: true);
        messages.Select(message => message.String("command")).Should().AllBe("echo");
        messages.Select(message => Body(message).Int("value")).Should().Equal(1, 2);
    }

    /// <summary>
    ///  Content-Length counts bytes, so text with multi-byte characters frames correctly both ways.
    /// </summary>
    [TestMethod]
    public void LengthsCountUtf8Bytes()
    {
        const string Text = "é ✓ 漢字";
        MemoryStream output = new();
        DapTransport transport = new(Input(Request(1, "echo", new JsonObject { ["text"] = Text })), output);
        transport.On("echo", args => new JsonObject { ["text"] = args["text"]?.DeepClone() });
        transport.Run();

        List<JsonObject> messages = Frames(output.ToArray());
        messages.Should().ContainSingle();
        Body(messages[0]).String("text").Should().Be(Text);
    }

    /// <summary>
    ///  Messages split across reads, a few bytes at a time, still frame correctly.
    /// </summary>
    [TestMethod]
    public void ReadsMessagesSplitAcrossReads()
    {
        MemoryStream output = new();
        byte[] input = [.. Request(1, "a", []), .. Request(2, "b", [])];
        DapTransport transport = new(new TrickleStream(input), output);
        transport.On("a", _ => new JsonObject { ["name"] = "a" });
        transport.On("b", _ => new JsonObject { ["name"] = "b" });
        transport.Run();

        Frames(output.ToArray()).Select(message => Body(message).String("name")).Should().Equal("a", "b");
    }

    /// <summary>
    ///  A request without a handler, or whose handler throws, fails with a message VS Code can show.
    /// </summary>
    [TestMethod]
    public void FailuresAnswerWithTheirMessage()
    {
        List<JsonObject> messages = Exchange(
            transport => transport.On("fails", (JsonObject _) => throw new ArgumentException("scanline must be 0-261.")),
            Request(1, "unknown", []),
            Request(2, "fails", []));

        messages.Should().OnlyContain(message => message.Bool("success") == false);
        messages[0].String("message").Should().Contain("unknown");
        messages[1].String("message").Should().Be("scanline must be 0-261.");
    }

    /// <summary>
    ///  A command can have only one handler, so a second registration is a mistake that shows.
    /// </summary>
    [TestMethod]
    public void RefusesASecondHandler()
    {
        DapTransport transport = new(new MemoryStream(), new MemoryStream());
        transport.On("launch", (JsonObject _) => new JsonObject());
        Action again = () => transport.On("launch", (JsonObject _) => new JsonObject());
        again.Should().Throw<InvalidOperationException>();
    }

    /// <summary>
    ///  A handler that stops the transport, as disconnect does, gets its response, and nothing after is read.
    /// </summary>
    [TestMethod]
    public void StopsAfterTheStoppingRequest()
    {
        List<JsonObject> messages = Exchange(
            transport =>
            {
                transport.On("disconnect", (JsonObject _) => Stopped(transport));
                transport.On("after", (JsonObject _) => new JsonObject());
            },
            Request(1, "disconnect", []),
            Request(2, "after", []));

        messages.Should().ContainSingle().Which.String("command").Should().Be("disconnect");
    }

    /// <summary>
    ///  A message that is not JSON is skipped, and the ones after it are answered.
    /// </summary>
    [TestMethod]
    public void SkipsAMessageThatIsNotJson()
    {
        byte[] broken = Encoding.ASCII.GetBytes("Content-Length: 5\r\n\r\n{oops");
        List<JsonObject> messages = Exchange(
            transport => transport.On("ok", (JsonObject _) => new JsonObject()),
            broken,
            Request(2, "ok", []));

        messages.Should().ContainSingle().Which.Int("request_seq").Should().Be(2);
    }

    /// <summary>
    ///  Events sent from another thread while requests are answered stay whole and numbered in order.
    /// </summary>
    [TestMethod]
    public void EventsFromAnotherThreadInterleaveCleanly()
    {
        const int Count = 200;
        MemoryStream output = new();
        byte[] input = [.. Enumerable.Range(1, Count).SelectMany(seq => Request(seq, "work", []))];
        DapTransport transport = new(new MemoryStream(input), output);
        using ManualResetEventSlim started = new();
        transport.On("work", _ =>
        {
            started.Set();
            return new JsonObject { ["pad"] = new string('x', 64) };
        });

        Thread events = new(() =>
        {
            started.Wait();
            for (int index = 0; index < Count; index++)
            {
                transport.SendEvent("output", new JsonObject { ["index"] = index });
            }
        });

        events.Start();
        transport.Run();
        events.Join();

        List<JsonObject> messages = Frames(output.ToArray());
        messages.Should().HaveCount(Count * 2);
        messages.Select(message => message.Int("seq") ?? 0).Should().Equal(Enumerable.Range(1, Count * 2));
        messages.Where(message => message.String("type") == "event")
            .Select(message => Body(message).Int("index") ?? -1)
            .Should().Equal(Enumerable.Range(0, Count));
    }

    private static List<JsonObject> Exchange(Action<DapTransport> register, params byte[][] requests)
    {
        MemoryStream output = new();
        DapTransport transport = new(Input(requests), output);
        register(transport);
        transport.Run();
        return Frames(output.ToArray());
    }

    private static MemoryStream Input(params byte[][] requests) => new([.. requests.SelectMany(request => request)]);

    private static byte[] Request(int seq, string command, JsonObject arguments)
    {
        JsonObject request = new()
        {
            ["seq"] = seq,
            ["type"] = "request",
            ["command"] = command,
            ["arguments"] = arguments
        };

        byte[] json = Encoding.UTF8.GetBytes(request.ToJsonString());
        return [.. Encoding.ASCII.GetBytes($"Content-Length: {json.Length}\r\n\r\n"), .. json];
    }

    private static JsonObject Stopped(DapTransport transport)
    {
        transport.Stop();
        return [];
    }

    private static JsonObject Body(JsonObject message) =>
        message["body"] as JsonObject ?? throw new AssertFailedException($"The {message.String("command")} message has no body.");

    // Splits output into its messages, checking each frame's length matches its bytes exactly.
    private static List<JsonObject> Frames(byte[] output)
    {
        List<JsonObject> messages = [];
        int position = 0;
        while (position < output.Length)
        {
            int headerEnd = output.AsSpan(position).IndexOf("\r\n\r\n"u8);
            headerEnd.Should().BeGreaterThan(0);
            string header = Encoding.ASCII.GetString(output, position, headerEnd);
            header.Should().StartWith("Content-Length: ");
            int length = int.Parse(header["Content-Length: ".Length..], System.Globalization.CultureInfo.InvariantCulture);
            position += headerEnd + 4;
            JsonObject message = JsonNode.Parse(output.AsSpan(position, length)) as JsonObject
                ?? throw new AssertFailedException("A message is not an object.");

            messages.Add(message);
            position += length;
        }

        return messages;
    }
}
