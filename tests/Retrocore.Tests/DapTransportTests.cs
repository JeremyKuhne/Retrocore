// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug;
using System.Text;
using System.Text.Json.Nodes;
using System.Diagnostics;

namespace Retrocore.Tests;

/// <summary>
///  Verifies the Debug Adapter Protocol's wire: framing, answers, errors and events.
/// </summary>
[TestClass]
public sealed class DapTransportTests
{
    private static readonly TimeSpan s_threadTimeout = TimeSpan.FromSeconds(30);

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
    ///  Disconnect does not leave a reader waiting for more input from a peer that has not closed its pipe.
    /// </summary>
    [TestMethod]
    public void DisconnectStopsReadingBeforeThePeerCloses()
    {
        using ManualResetEventSlim readingPastMessage = new();
        using ManualResetEventSlim close = new();
        using DisconnectReadStream input = new(Request(1, "disconnect", []), readingPastMessage, close);
        using MemoryStream output = new();
        DapTransport transport = new(input, output);
        bool readAhead = false;
        transport.On("disconnect", _ =>
        {
            readAhead = readingPastMessage.Wait(TimeSpan.FromMilliseconds(250));
            return Stopped(transport);
        });

        try
        {
            transport.Run();
            readAhead.Should().BeFalse();
            Frames(output.ToArray()).Should().ContainSingle().Which.Bool("success").Should().BeTrue();
        }
        finally
        {
            close.Set();
        }
    }

    /// <summary>
    ///  A failed disconnect leaves the reader available to service a retry.
    /// </summary>
    [TestMethod]
    public void FailedDisconnectDoesNotStopReading()
    {
        bool first = true;
        List<JsonObject> messages = Exchange(transport =>
        {
            transport.On("disconnect", _ =>
            {
                if (!first) { return Stopped(transport); }
                first = false;
                throw new IOException("Retry disconnect");
            });
        }, Request(1, "disconnect", []), Request(2, "disconnect", []));

        messages.Select(message => message.Bool("success")).Should().Equal(false, true);
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
        transport.Run(events.Join);

        List<JsonObject> messages = Frames(output.ToArray());
        messages.Should().HaveCount(Count * 2);
        messages.Select(message => message.Int("seq") ?? 0).Should().Equal(Enumerable.Range(1, Count * 2));
        messages.Where(message => message.String("type") == "event")
            .Select(message => Body(message).Int("index") ?? -1)
            .Should().Equal(Enumerable.Range(0, Count));
    }

    /// <summary>
    ///  A slow pipe does not block control requests, reorder replies, or read pixels from a reused frame buffer.
    /// </summary>
    /// <returns>The test task.</returns>
    [TestMethod]
    public async Task ControlRequestsCanRunWhileOutputIsBackpressured()
    {
        using ManualResetEventSlim writing = new();
        using ManualResetEventSlim release = new();
        using ManualResetEventSlim controlled = new();
        using GatedWriteStream output = new(writing, release);
        using MemoryStream input = Input(Request(1, "initialize", []), Request(2, "produce", []), Request(3, "pause", []));
        DapTransport transport = new(input, output);
        transport.On("initialize", _ => new JsonObject());
        transport.On("produce", _ =>
        {
            writing.Wait(s_threadTimeout).Should().BeTrue();
            byte[] pixels = new byte[63 * 8192];
            pixels[0] = 1;
            transport.SendFrame(Frame(), pixels);
            pixels[0] = 2;
            transport.SendFrame(Frame(), pixels);
            pixels[0] = 3;
            return new JsonObject();
        });

        transport.On("pause", _ =>
        {
            controlled.Set();
            return new JsonObject();
        });

        Task host = StartHost(() => transport.Run(WaitForRelease));
        try
        {
            controlled.Wait(s_threadTimeout).Should().BeTrue("the writer is still blocked");
            transport.Backpressured.Should().BeTrue();
        }
        finally
        {
            release.Set();
            await host.WaitAsync(s_threadTimeout).ConfigureAwait(continueOnCapturedContext: false);
        }

        List<JsonObject> messages = Frames(output.ToArray());
        messages.Select(message => message.Int("seq")).Should().Equal(1, 2, 3, 4, 5);
        messages.Select(message => message.String("command") ?? message.String("event"))
            .Should().Equal("initialize", "retro/frame", "retro/frame", "produce", "pause");

        Pixels(messages[1])[0].Should().Be(1);
        Pixels(messages[2])[0].Should().Be(2);
        transport.Backpressured.Should().BeFalse();

        void WaitForRelease() => release.Wait(s_threadTimeout).Should().BeTrue("shutdown waits until the test releases output");
        static JsonObject Frame() => new() { ["video"] = new JsonObject() };
        static byte[] Pixels(JsonObject message) =>
            Convert.FromBase64String(Body(message).Object("video")?.String("pixels")
                ?? throw new AssertFailedException("No frame pixels."));
    }

    /// <summary>
    ///  Disconnect returns even if the peer keeps the output open without reading; only the blocked write retains
    ///  ownership of its payload.
    /// </summary>
    /// <returns>The test task.</returns>
    [TestMethod]
    public async Task DisconnectAbandonsStalledOutput()
    {
        using ManualResetEventSlim writing = new();
        using ManualResetEventSlim release = new();
        using GatedWriteStream output = new(writing, release);
        using MemoryStream input = Input(Request(1, "disconnect", []));
        TaskCompletionSource inFlightReleased = new(TaskCreationOptions.RunContinuationsAsynchronously);
        TaskCompletionSource queuedReleased = new(TaskCreationOptions.RunContinuationsAsynchronously);
        DapTransport transport = new(input, output);
        transport.On("disconnect", _ =>
        {
            transport.SendEvent("output", writer => writer.WriteNullValue(), release: inFlightReleased.SetResult);
            writing.Wait(s_threadTimeout).Should().BeTrue();
            transport.SendEvent("output", writer => writer.WriteNullValue(), release: queuedReleased.SetResult);
            return Stopped(transport);
        });

        bool ended = false;
        Task host = StartHost(() => transport.Run(() => ended = true, outputDrainMilliseconds: 0));
        try
        {
            await host.WaitAsync(s_threadTimeout).ConfigureAwait(continueOnCapturedContext: false);
            ended.Should().BeTrue();
            transport.OutputFailed.Should().BeTrue();
            queuedReleased.Task.IsCompletedSuccessfully.Should().BeTrue();
            inFlightReleased.Task.IsCompleted.Should().BeFalse("the peer still blocks the first write");
        }
        finally
        {
            release.Set();
            await host.WaitAsync(s_threadTimeout).ConfigureAwait(continueOnCapturedContext: false);
            await inFlightReleased.Task.WaitAsync(s_threadTimeout).ConfigureAwait(continueOnCapturedContext: false);
        }
    }

    /// <summary>
    ///  A broken output cancels a reader waiting for input even when the peer keeps its pipe open.
    /// </summary>
    /// <returns>The test task.</returns>
    [TestMethod]
    public async Task OutputFailureStopsBlockedReader()
    {
        using ManualResetEventSlim reading = new();
        using ManualResetEventSlim close = new();
        using DisconnectReadStream input = new(Request(1, "initialize", []), reading, close);
        MemoryStream output = new();
        output.Dispose();
        DapTransport transport = new(input, output, (bytes, token) => input.Read(bytes.Span, token));
        transport.On("initialize", _ =>
        {
            reading.Wait(s_threadTimeout).Should().BeTrue();
            return new JsonObject();
        });

        Task host = StartHost(transport.Run);
        try
        {
            await host.WaitAsync(s_threadTimeout).ConfigureAwait(continueOnCapturedContext: false);
            transport.OutputFailed.Should().BeTrue();
        }
        finally
        {
            close.Set();
            await host.WaitAsync(s_threadTimeout).ConfigureAwait(continueOnCapturedContext: false);
        }
    }

    /// <summary>
    ///  The actual debugger host detects a closed output pipe and exits without waiting for input EOF.
    /// </summary>
    /// <returns>The test task.</returns>
    [TestMethod]
    public async Task RedirectedHostExitsWhenPeerClosesOnlyOutput()
    {
        ProcessStartInfo start = new("dotnet")
        {
            ArgumentList = { typeof(DebugSession).Assembly.Location },
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true
        };

        using Process host = Process.Start(start) ?? throw new AssertFailedException("Could not start the DAP host.");
        host.StandardOutput.Dispose();
        Task<string> errors = host.StandardError.ReadToEndAsync();
        try
        {
            Stream input = host.StandardInput.BaseStream;
            await input.WriteAsync(Request(1, "initialize", [])).ConfigureAwait(continueOnCapturedContext: false);
            await input.FlushAsync().ConfigureAwait(continueOnCapturedContext: false);
            await host.WaitForExitAsync().WaitAsync(s_threadTimeout).ConfigureAwait(continueOnCapturedContext: false);
            host.ExitCode.Should().Be(1);
            (await errors.ConfigureAwait(continueOnCapturedContext: false)).Should().Contain("DAP output failed:");
        }
        finally
        {
            if (!host.HasExited)
            {
                host.Kill();
                await host.WaitForExitAsync().WaitAsync(s_threadTimeout).ConfigureAwait(continueOnCapturedContext: false);
            }
        }
    }

    /// <summary>
    ///  A queued cancellation interrupts a launch without reordering the two responses.
    /// </summary>
    /// <param name="id">A whole request ID in JSON.</param>
    [TestMethod]
    [DataRow("1")]
    [DataRow("1.0")]
    [DataRow("1e0")]
    public void CancelInterruptsLaunch(string id)
    {
        List<JsonObject> messages = Exchange(transport =>
        {
            transport.On("launch", _ =>
            {
                long started = Stopwatch.GetTimestamp();
                while (Stopwatch.GetElapsedTime(started) < s_threadTimeout)
                {
                    transport.ThrowIfLaunchCancelled();
                    Thread.Sleep(1);
                }

                return new JsonObject();
            });

            transport.On("cancel", _ => new JsonObject());
        }, Request(1, "launch", []), Request(2, "cancel", new JsonObject { ["requestId"] = JsonNode.Parse(id) }));

        messages.Select(message => message.Int("request_seq")).Should().Equal(1, 2);
        messages.Select(message => message.Bool("success")).Should().Equal(false, true);
    }

    /// <summary>
    ///  Ordinary requests queued behind a paced launch do not cancel it or reorder replies.
    /// </summary>
    [TestMethod]
    public void FullRequestQueueDoesNotCancelLaunch()
    {
        const int RequestCount = 300;
        List<JsonObject> messages = Exchange(transport =>
        {
            transport.On("launch", _ =>
            {
                long started = Stopwatch.GetTimestamp();
                while (Stopwatch.GetElapsedTime(started) < TimeSpan.FromMilliseconds(250))
                {
                    transport.ThrowIfLaunchCancelled();
                    Thread.Sleep(1);
                }

                return new JsonObject();
            });

            transport.On("next", _ => new JsonObject());
        }, [Request(1, "launch", []), .. Enumerable.Range(2, RequestCount).Select(seq => Request(seq, "next", []))]);

        messages.Select(message => message.Int("request_seq")).Should().Equal(Enumerable.Range(1, RequestCount + 1).Select(seq => (int?)seq));
        messages.Should().OnlyContain(message => message.Bool("success") == true);
    }

    /// <summary>
    ///  EOF cancels paced work rather than leaving the adapter waiting for the launch to finish.
    /// </summary>
    [TestMethod]
    public void PacedLaunchStopsAtInputEof()
    {
        List<JsonObject> messages = Exchange(transport =>
        {
            transport.On("launch", _ =>
            {
                long started = Stopwatch.GetTimestamp();
                while (Stopwatch.GetElapsedTime(started) < TimeSpan.FromSeconds(1))
                {
                    transport.ThrowIfLaunchCancelled(requireInput: true);
                    Thread.Sleep(1);
                }

                return new JsonObject();
            });
        }, Request(1, "launch", []));

        messages.Should().ContainSingle().Which.String("message").Should().Contain("DAP input closed");
    }

    /// <summary>
    ///  A pre-cancelled launch consumes its configuration handshake without starting a replacement.
    /// </summary>
    [TestMethod]
    public void PreCancelledLaunchDoesNotConfigureTheRetry()
    {
        using ManualResetEventSlim sawEnd = new();
        using ManualResetEventSlim close = new(initialState: true);
        JsonObject apple1 = new()
        {
            ["machine"] = "apple1",
            ["sdkRoms"] = Path.Join(AppContext.BaseDirectory, "Inputs"),
            ["textOnly"] = true,
            ["stopOnEntry"] = true
        };

        using DisconnectReadStream input = new(
            [.. Request(1, "initialize", []), .. Request(2, "configurationDone", []), .. Request(3, "gate", []),
             .. Request(4, "launch", apple1), .. Request(5, "cancel", new JsonObject { ["requestId"] = 4 }),
             .. Request(6, "launch", apple1.DeepClone().AsObject())], sawEnd, close);

        using MemoryStream output = new();
        DapTransport transport = new(input, output, (bytes, token) => input.Read(bytes.Span, token));
        DebugSession session = new();
        session.Register(transport, transport.Stop);
        transport.On("gate", _ =>
        {
            sawEnd.Wait(s_threadTimeout).Should().BeTrue();
            return new JsonObject();
        });

        transport.Run(session.End);
        List<JsonObject> messages = Frames(output.ToArray());
        messages.Single(message => message.Int("request_seq") == 4).Bool("success").Should().BeFalse();
        messages.Single(message => message.Int("request_seq") == 6).Bool("success").Should().BeTrue();
        messages.Should().NotContain(message => message.String("event") == "stopped");
    }

    /// <summary>
    ///  Inspecting malformed requests for cancellation does not terminate the reader.
    /// </summary>
    [TestMethod]
    public void MalformedRequestDoesNotEndReadAhead()
    {
        List<JsonObject> messages = Exchange(transport =>
        {
            transport.On("cancel", args => new JsonObject { ["requestId"] = args.Int("requestId") });
            transport.On("next", _ => new JsonObject());
        },
        Encode(new JsonObject { ["type"] = "request", ["seq"] = 1, ["command"] = 99 }),
        Encode(new JsonObject { ["type"] = "request", ["seq"] = "bad", ["command"] = "launch" }),
        Request(3, "cancel", new JsonObject { ["requestId"] = "bad" }),
        Request(4, "next", []));

        messages.Select(message => message.Bool("success")).Should().Equal(false, false, false, true);
        messages[^1].Int("request_seq").Should().Be(4);
    }

    private static Task StartHost(Action run) =>
        Task.Factory.StartNew(run, CancellationToken.None, TaskCreationOptions.LongRunning, TaskScheduler.Default);

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

        return Encode(request);
    }

    private static byte[] Encode(JsonObject request)
    {
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
