// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text;
using System.Text.Json.Nodes;
using Retrocore.Debug;

namespace Retrocore.Tests;

/// <summary>
///  Verifies frame events written straight to the wire: the same JSON as before, pixels left out when asked, and no
///  allocation the size of the picture.
/// </summary>
[TestClass]
public sealed class DisplayFrameWriterTests
{
    private const int Width = 560;
    private const int Height = 192;

    /// <summary>
    ///  With pixels, the body is the state with <c>video.pixels</c> as base64, field for field as the whole frame
    ///  is written as a node, including the text rows' block characters and base64's <c>+</c> and <c>/</c>.
    /// </summary>
    [TestMethod]
    public void WritesTheWholeFrame()
    {
        byte[] pixels = Pixels();
        JsonObject state = State();
        JsonObject expected = (JsonObject)state.DeepClone();
        Video(expected)["pixels"] = Convert.ToBase64String(pixels);

        JsonObject body = Body(Send(state, pixels));
        JsonNode.DeepEquals(body, expected).Should().BeTrue();
        string text = Video(body).String("pixels") ?? "";
        text.Should().Contain("+").And.Contain("/");
        Convert.FromBase64String(text).Should().Equal(pixels);
    }

    /// <summary>
    ///  Without pixels, the video keeps its size and beam and has no <c>pixels</c>.
    /// </summary>
    [TestMethod]
    public void LeavesOutPixelsWhenNoneAreGiven()
    {
        JsonObject body = Body(Send(State(), []));
        JsonObject video = Video(body);
        video.ContainsKey("pixels").Should().BeFalse();
        video.Int("width").Should().Be(Width);
        JsonNode.DeepEquals(body, State()).Should().BeTrue();
    }

    /// <summary>
    ///  Events written this way and ordinary ones share one sequence, and a small event after a large one frames
    ///  only its own bytes, though the buffer is reused.
    /// </summary>
    [TestMethod]
    public void SharesTheSequenceAndReusesTheBuffer()
    {
        MemoryStream output = new();
        DapTransport transport = new(new MemoryStream(), output);
        transport.SendEvent("retro/frame", writer => DisplayFrameWriter.Write(writer, State(), Pixels()));
        transport.SendEvent("output", new JsonObject { ["text"] = "hi" });
        transport.SendEvent("retro/frame", writer => DisplayFrameWriter.Write(writer, State(), []));

        List<JsonObject> messages = Frames(output.ToArray());
        messages.Select(message => message.Int("seq") ?? 0).Should().Equal(1, 2, 3);
        messages.Select(message => message.String("event")).Should().Equal("retro/frame", "output", "retro/frame");
        messages.Should().OnlyContain(message => message.String("type") == "event");
        Video(messages[2]["body"] as JsonObject ?? []).ContainsKey("pixels").Should().BeFalse();
    }

    /// <summary>
    ///  Once its buffer has grown to fit, sending a 430 KB picture allocates a small fraction of its size: no base64
    ///  string, JSON text or byte array the size of the frame.
    /// </summary>
    [TestMethod]
    public void SendingAFrameAllocatesLittle()
    {
        DapTransport transport = new(new MemoryStream(), Stream.Null);
        byte[] pixels = Pixels();
        JsonObject state = State();
        void Send() => transport.SendEvent("retro/frame", writer => DisplayFrameWriter.Write(writer, state, pixels));
        Send();
        Send();
        long before = GC.GetAllocatedBytesForCurrentThread();
        Send();
        long allocated = GC.GetAllocatedBytesForCurrentThread() - before;
        allocated.Should().BeLessThan(pixels.Length / 20, "the old path allocated about 13 times the picture's size");
    }

    private static JsonObject Video(JsonObject frame) =>
        frame["video"] as JsonObject ?? throw new AssertFailedException("The frame has no video.");

    // A frame's state as the IIe sends it, without pixels.
    private static JsonObject State() => new()
    {
        ["machine"] = "apple2",
        ["columns"] = 40,
        ["rows"] = new JsonArray("]PRINT \"█▒\"", "HELLO"),
        ["cycles"] = 123456789UL,
        ["video"] = new JsonObject
        {
            ["width"] = Width,
            ["height"] = Height,
            ["pixelFormat"] = "rgba",
            ["beam"] = new JsonObject { ["scanline"] = 100, ["column"] = 25, ["verticalBlank"] = false },
            ["cycles"] = 123456789UL
        },
        ["disk"] = null,
        ["sound"] = "speaker",
        ["running"] = true
    };

    // Varied bytes, whose base64 has every character, + and / among them.
    private static byte[] Pixels()
    {
        byte[] pixels = new byte[Width * Height * 4];
        for (int index = 0; index < pixels.Length; index++) { pixels[index] = (byte)((index * 37) ^ (index >> 7)); }
        return pixels;
    }

    private static byte[] Send(JsonObject state, byte[] pixels)
    {
        MemoryStream output = new();
        DapTransport transport = new(new MemoryStream(), output);
        transport.SendEvent("retro/frame", writer => DisplayFrameWriter.Write(writer, state, pixels));
        return output.ToArray();
    }

    private static JsonObject Body(byte[] output)
    {
        JsonObject message = Frames(output).Should().ContainSingle().Subject;
        return message["body"] as JsonObject ?? throw new AssertFailedException("The frame has no body.");
    }

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
            int length = int.Parse(header["Content-Length: ".Length..], System.Globalization.CultureInfo.InvariantCulture);
            position += headerEnd + 4;
            messages.Add(JsonNode.Parse(output.AsSpan(position, length)) as JsonObject ?? []);
            position += length;
        }

        position.Should().Be(output.Length);
        return messages;
    }
}
