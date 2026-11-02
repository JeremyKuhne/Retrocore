// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json;
using Retrocore.Assembler;
using Retrocore.Cpu.Z80;
using Retrocore.Isa;
using NativeAssembler = Retrocore.Assembler.Assembler;

namespace Retrocore.Tests;

/// <summary>
///  The Z80 description against external references: the SingleStepTests opcode files and ZEXALL/ZEXDOC.
/// </summary>
/// <remarks>
///  <para>
///   The fixtures stay in the external cache; <c>tools\Fetch-Z80Tests.ps1</c> fetches and verifies them. The
///   tests are inconclusive without them.
///  </para>
/// </remarks>
[TestClass]
public class Z80OracleTests
{
    /// <summary>
    ///  The pinned MIT SingleStepTests Z80 revision.
    /// </summary>
    internal const string SingleStepPin = "ebe1875d48f374bcfd4b505d8eb8ee751568b5f7";

    /// <summary>
    ///  The pinned GPL ZEXALL revision. No sources or binaries are bundled.
    /// </summary>
    internal const string ZexallPin = "8f71d418bae69a476a5a0e5c6e122c8801b8d9f4";

    // The tests of each file that are checked; every one starts from different registers and memory.
    private const int CasesPerFile = 25;

    /// <summary>
    ///  Every opcode file names an opcode the description decodes, and an instruction that does not change the
    ///  flow ends where the reference's next PC says it does.
    /// </summary>
    [TestMethod]
    [TestCategory("Conformance")]
    public void EncodingsMatchSingleStepTests()
    {
        string root = Fixtures(SingleStepPin);
        InstructionSet set = Z80Isa.InstructionSet;
        int files = 0;
        List<string> failures = [];
        foreach (string name in FixtureNames(root))
        {
            files++;
            byte[] bytes = ExternalTestData.Read(SingleStepPin, name);
            int cases = 0;
            foreach (JsonElement test in Tests(bytes).Take(CasesPerFile))
            {
                cases++;
                if (Check(set, name, test) is { } failure)
                {
                    failures.Add(failure);
                    break;
                }
            }

            cases.Should().BePositive(name);
        }

        failures.Should().BeEmpty();
        files.Should().Be(1604);
    }

    /// <summary>
    ///  ZEXALL and ZEXDOC disassemble, by flow and linearly, to native source that assembles to the same bytes.
    /// </summary>
    /// <param name="file">The CP/M program.</param>
    /// <param name="mode">How the disassembler finds code.</param>
    [TestMethod]
    [TestCategory("Conformance")]
    [DataRow("zexall.com", DisassemblyMode.Flow)]
    [DataRow("zexall.com", DisassemblyMode.Linear)]
    [DataRow("zexdoc.com", DisassemblyMode.Flow)]
    [DataRow("zexdoc.com", DisassemblyMode.Linear)]
    public void ExercisersReassembleFromTheirDisassembly(string file, DisassemblyMode mode)
    {
        Fixtures(ZexallPin);
        byte[] program = ExternalTestData.Read(ZexallPin, file);

        // A CP/M program loads at $0100; its entry is the first byte.
        const int Origin = 0x0100;
        DisassemblyResult result = Disassembler.Analyze(new AnalysisProject(program, Origin, Z80Isa.InstructionSet)
        {
            Mode = mode,
            FollowVectors = false
        });

        result.Success.Should().BeTrue();
        result.Instructions.Count.Should().BeGreaterThan(mode == DisassemblyMode.Flow ? 300 : 1000);
        string source = result.ExportSource();
        AssemblyResult assembled = new NativeAssembler().Assemble(new AssemblySource(source, file + ".asm"), result.Options);
        assembled.Diagnostics.Should().BeEmpty();
        assembled.Sections[0].Bytes.ToArray().Should().Equal(program);
    }

    // The reference's next PC for an instruction that continues in order, from the first case's memory.
    private static string? Check(InstructionSet set, string name, JsonElement test)
    {
        JsonElement initial = test.GetProperty("initial");
        ushort pc = initial.GetProperty("pc").GetUInt16();
        Dictionary<ushort, byte> memory = [];
        foreach (JsonElement cell in initial.GetProperty("ram").EnumerateArray())
        {
            memory[cell[0].GetUInt16()] = cell[1].GetByte();
        }

        Span<byte> code = stackalloc byte[4];
        for (int index = 0; index < code.Length; index++)
        {
            code[index] = memory.TryGetValue(unchecked((ushort)(pc + index)), out byte value) ? value : (byte)0;
        }

        if (!Disassembler.TryDecode(code, pc, set, out DisassembledInstruction instruction))
        {
            return $"{name}: {Convert.ToHexString(code)} does not decode.";
        }

        // The file name is the opcode, with __ for a DD CB displacement.
        string expected = Path.GetFileNameWithoutExtension(name).Replace("__ ", "", StringComparison.Ordinal);
        string actual = string.Join(' ', Enumerable.Range(0, instruction.Encoding.OpcodeLength)
            .Select(index => instruction.GetByte(instruction.Encoding.OpcodeBytePosition(index, instruction.Form.Size)).ToString("x2")));

        if (actual != expected) { return $"{name}: decoded opcode {actual}."; }
        if (instruction.Flow != DisassemblyFlow.Next || Repeats(instruction.Mnemonic)) { return null; }
        ushort next = test.GetProperty("final").GetProperty("pc").GetUInt16();
        return next == unchecked((ushort)(pc + instruction.Size))
            ? null
            : $"{name}: {instruction} is {instruction.Size} bytes, but the reference continues at ${next:X4} from ${pc:X4}.";
    }

    // Block instructions repeat until their count runs out, a conditional return may return, and HALT holds PC.
    private static bool Repeats(string mnemonic) =>
        Array.IndexOf(s_repeating, mnemonic) >= 0;

    private static readonly string[] s_repeating = ["LDIR", "LDDR", "CPIR", "CPDR", "INIR", "INDR", "OTIR", "OTDR", "RET", "HALT"];

    private static IEnumerable<JsonElement> Tests(byte[] bytes)
    {
        using JsonDocument document = JsonDocument.Parse(bytes);
        foreach (JsonElement test in document.RootElement.EnumerateArray()) { yield return test.Clone(); }
    }

    private static IEnumerable<string> FixtureNames(string root) =>
        Directory.EnumerateFiles(Path.Join(root, "v1"), "*.json")
            .Select(path => "v1/" + Path.GetFileName(path))
            .Order(StringComparer.Ordinal);

    private static string Fixtures(string pin)
    {
        string root = Path.Join(ExternalTestData.Cache, pin);
        if (!File.Exists(Path.Join(root, "manifest.json")))
        {
            Assert.Inconclusive($"Z80 fixtures are missing from {root}. Run tools\\Fetch-Z80Tests.ps1 with PowerShell 7.");
        }

        return root;
    }
}
