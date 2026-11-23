// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Debug;
using System.Text;
using System.Text.Json.Nodes;

namespace Retrocore.Tests;

/// <summary>
///  Verifies the debug host's <c>retro/memory/export</c>, Retrocore Memory's Save as .asm, through a debug session
///  on an Apple II built from the SDK's sources.
/// </summary>
[TestClass]
public sealed class MemoryExportTests
{
    private static readonly string s_inputs = Path.Join(AppContext.BaseDirectory, "Inputs");

    /// <summary>
    ///  A program that calls the Monitor names each routine as the Monitor's source does, a routine in a family scope
    ///  by its qualified name, defined inside its scopes, and the source assembles back to the program's bytes.
    /// </summary>
    [TestMethod]
    public void ExportNamesTheMonitorsScopedRoutines()
    {
        // $0800 JSR $FDED (CharacterOut); JSR $F800 (LowRes::Plot); JSR $F832 (LowRes::Clear); RTS
        byte[] program = [0x20, 0xED, 0xFD, 0x20, 0x00, 0xF8, 0x20, 0x32, 0xF8, 0x60];

        JsonObject export = Export(program, 0x0800);

        export.Bool("exact").Should().BeTrue();
        string source = export.String("source") ?? throw new AssertFailedException("The export has no source.");
        source.Should().Contain("JSR CharacterOut").And.Contain("JSR LowRes::Plot").And.Contain("JSR LowRes::Clear");
        source.Should().Contain(".scope LowRes\nClear = $F832\nPlot = $F800\n.endscope\n");

        AssemblyOptions options = new(ProcessorVariant.Mos6502, 0x0800, program.Length);
        AssemblyResult result = new Retrocore.Assembler.Assembler().Assemble(new AssemblySource(source, "export.asm"), options);
        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.ToArray().Should().Equal(program);
    }

    // Launches a II Plus from the SDK's sources, writes the program and exports it.
    private static JsonObject Export(byte[] program, int address)
    {
        byte[][] requests =
        [
            Request(1, "initialize", []),
            Request(2, "launch", new JsonObject
            {
                ["machine"] = "apple2",
                ["model"] = "iiplus",
                ["sdkRoms"] = s_inputs,
                ["controllers"] = false,
                ["stopOnEntry"] = true
            }),
            Request(3, "writeMemory", new JsonObject
            {
                ["memoryReference"] = $"0x{address:X4}",
                ["data"] = Convert.ToBase64String(program)
            }),
            Request(4, "retro/memory/export", new JsonObject
            {
                ["memoryReference"] = "0x0000",
                ["address"] = address,
                ["count"] = program.Length,
                ["starts"] = new JsonArray(address)
            })
        ];

        MemoryStream output = new();
        DapTransport transport = new(new MemoryStream([.. requests.SelectMany(request => request)]), output);
        DebugSession session = new();
        session.Register(transport, transport.Stop);
        try
        {
            transport.Run();
        }
        finally
        {
            session.End();
        }

        List<JsonObject> responses = [.. Frames(output.ToArray()).Where(message => message.String("type") == "response")];
        foreach (JsonObject response in responses)
        {
            response.Bool("success").Should().BeTrue($"{response.String("command")} failed: {response.String("message")}");
        }

        JsonObject reply = responses.Single(response => response.Int("request_seq") == 4);
        return reply["body"] as JsonObject ?? throw new AssertFailedException("The export has no body.");
    }

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

    // Splits the output into its messages.
    private static List<JsonObject> Frames(byte[] output)
    {
        List<JsonObject> messages = [];
        int position = 0;
        while (position < output.Length)
        {
            int headerEnd = output.AsSpan(position).IndexOf("\r\n\r\n"u8);
            string header = Encoding.ASCII.GetString(output, position, headerEnd);
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
