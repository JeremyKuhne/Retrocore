// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Media;
using Retrocore.Pascal;

namespace Retrocore.Tests;

/// <summary>
///  Decoding and disassembling Apple Pascal's p-code.
/// </summary>
[TestClass]
public class PcodeTests
{
    /// <summary>
    ///  Each operand form decodes and formats: short forms, big numbers of one and two bytes, levels, words,
    ///  strings, and comparisons with and without a size.
    /// </summary>
    /// <param name="bytes">The p-code's bytes, from offset 0.</param>
    /// <param name="length">Its length.</param>
    /// <param name="text">How it formats.</param>
    [TestMethod]
    [DataRow(new byte[] { 5 }, 1, "SLDC 5")]
    [DataRow(new byte[] { 216 }, 1, "SLDL1")]
    [DataRow(new byte[] { 247 }, 1, "SLDO16")]
    [DataRow(new byte[] { 255 }, 1, "SIND7")]
    [DataRow(new byte[] { 202, 0x7F }, 2, "LDL 127")]
    [DataRow(new byte[] { 202, 0x81, 0x02 }, 3, "LDL 258")]
    [DataRow(new byte[] { 182, 2, 3 }, 3, "LOD 2, 3")]
    [DataRow(new byte[] { 199, 0x34, 0x12 }, 3, "LDCI 4660")]
    [DataRow(new byte[] { 199, 0xFF, 0xFF }, 3, "LDCI -1")]
    [DataRow(new byte[] { 205, 20, 3 }, 3, "CXP 20, 3")]
    [DataRow(new byte[] { 158, 2 }, 2, "CSP MVL")]
    [DataRow(new byte[] { 166, 3, (byte)'I', (byte)'\'', (byte)'M' }, 5, "LSA 'I''M'")]
    [DataRow(new byte[] { 175, 4 }, 2, "EQUSTR")]
    [DataRow(new byte[] { 183, 10, 6 }, 3, "NEQBYT 6")]
    [DataRow(new byte[] { 157, 22, 1 }, 3, "LDE 22, 1")]
    [DataRow(new byte[] { 173, 1 }, 2, "RNP 1")]
    public void OperandFormsDecode(byte[] bytes, int length, string text)
    {
        PcodeInstruction instruction = PcodeDisassembler.Decode(bytes, offset: 0, jumpTable: 0);
        instruction.Length.Should().Be(length);
        instruction.ToString().Should().Be(text);
    }

    /// <summary>
    ///  A jump goes forward from the next p-code; a negative one through the jump table, whose entries count back
    ///  from the procedure's attributes and hold self-relative targets.
    /// </summary>
    [TestMethod]
    public void JumpsGoForwardOrThroughTheJumpTable()
    {
        byte[] code = new byte[32];
        code[0] = Pcode.Ujp;
        code[1] = 4;
        code[2] = Pcode.Fjp;
        code[3] = 0xF6;                          // -10: the entry at 30 - 10 = 20

        // The entry at 20 holds 20 - 2, so the target is 2.
        code[20] = 18;

        PcodeDisassembler.Decode(code, 0, jumpTable: 30).Targets.Should().Equal(6);
        PcodeDisassembler.Decode(code, 2, jumpTable: 30).Targets.Should().Equal(2);
        PcodeDisassembler.Decode(code, 2, jumpTable: 30).ToString().Should().Be("FJP $0002");
    }

    /// <summary>
    ///  <c>LDC</c>'s words and <c>XJP</c>'s table start on a word boundary; a missing case goes where the
    ///  <c>XJP</c>'s own <c>UJP</c> goes.
    /// </summary>
    [TestMethod]
    public void WordAlignedOperandsDecode()
    {
        byte[] constant = [0, Pcode.Opcode(179).Code, 2, 0, 0x01, 0x00, 0x02, 0x00];
        PcodeInstruction load = PcodeDisassembler.Decode(constant, offset: 1, jumpTable: 0);
        load.Length.Should().Be(7);
        load.ToString().Should().Be("LDC 2: $0001 $0002");

        // XJP at 0: pad, 1..2, UJP +4 (to 12), then case 1 at 8 goes to 2 and case 2 at 10 to the UJP at 6.
        byte[] cases = [Pcode.Xjp, 0, 1, 0, 2, 0, Pcode.Ujp, 4, 6, 0, 4, 0];
        PcodeInstruction jump = PcodeDisassembler.Decode(cases, offset: 0, jumpTable: 0);
        jump.Length.Should().Be(12);
        jump.Targets.Should().Equal(12, 2, 12);
        jump.ToString().Should().Be("XJP 1..2, else $000C: $0002 $000C");
    }

    /// <summary>
    ///  A p-code that runs past the end of the code is refused.
    /// </summary>
    [TestMethod]
    public void PcodePastTheEndIsRefused()
    {
        Action decode = () => PcodeDisassembler.Decode([202, 0x81], offset: 0, jumpTable: 0);
        decode.Should().Throw<InvalidDataException>();
    }

    /// <summary>
    ///  Apple Pascal 1.1's HILBERT sample disassembles as its source reads: <c>HIL</c> turns 180 degrees through
    ///  TURTLEGRAPHICS (segment 20) when <c>I</c> is 0, and otherwise calls <c>HIL1</c>, <c>HIL2</c> and <c>HIL1</c>.
    /// </summary>
    [TestMethod]
    public void HilbertDisassemblesAsItsSourceReads()
    {
        PascalVolume volume = PascalMediaTests.Apple2Volume("UCSD Pascal 1.1_3.dsk");
        PascalSegment segment = PascalCodeFile.Read(volume.ReadFile("HILBERT.CODE")).Segments[0];
        PascalProcedure hil = segment.Procedures.Single(procedure => procedure.Index == 2);
        string[] text = [.. PcodeDisassembler.Disassemble(segment, hil).Select(instruction => instruction.ToString())];
        text.Should().StartWith(["SLDL1", "SLDC 0", "EQUI", "FJP $005B", "LDCI 180", "CXP 20, 3", "UJP $0079"]);
        text.Should().EndWith(["CLP 3", "CLP 4", "CLP 3", "RNP 0"]);
    }

    /// <summary>
    ///  Every p-code procedure on Apple Pascal 1.1's and Apple III Pascal 1.1's and 1.2's disks decodes from its entry
    ///  to its exit, and every jump lands on a p-code of the procedure.
    /// </summary>
    [TestMethod]
    public void EveryProcedureOnTheDisksDecodes()
    {
        int procedures = 0;
        foreach ((string name, byte[] data) in PascalMediaTests.CodeFiles())
        {
            foreach (PascalSegment segment in PascalCodeFile.Read(data).Segments)
            {
                foreach (PascalProcedure procedure in segment.Procedures.Where(procedure => !procedure.IsNative))
                {
                    IReadOnlyList<PcodeInstruction> instructions = PcodeDisassembler.Disassemble(segment, procedure);
                    HashSet<int> starts = [.. instructions.Select(instruction => instruction.Offset)];
                    instructions.SelectMany(instruction => instruction.Targets)
                        .Where(target => !starts.Contains(target))
                        .Should().BeEmpty($"{name} {segment.Name}.{procedure.Index} jumps only to its own p-code");

                    procedures++;
                }
            }
        }

        procedures.Should().BeGreaterThan(2500);
    }
}
