// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Cpu.M6809;
using Retrocore.Debug.Language;
using Retrocore.Documentation;
using NativeAssembler = Retrocore.Assembler.Assembler;

namespace Retrocore.Tests;

/// <summary>
///  The MC6809's native assembly syntax, disassembler, flow analysis and documentation integration.
/// </summary>
[TestClass]
public class M6809AssemblerTests
{
    /// <summary>
    ///  Every MC6809 addressing mode, prefix page, postbyte form and mnemonic alias encodes to Motorola's bytes.
    /// </summary>
    /// <param name="source">The instruction, assembled at <c>$1000</c>.</param>
    /// <param name="expected">The encoded bytes as hex pairs.</param>
    [TestMethod]
    [DataRow("NOP", "12")]
    [DataRow("SYNC", "13")]
    [DataRow("DAA", "19")]
    [DataRow("SEX", "1D")]
    [DataRow("RTS", "39")]
    [DataRow("ABX", "3A")]
    [DataRow("RTI", "3B")]
    [DataRow("MUL", "3D")]
    [DataRow("SWI", "3F")]
    [DataRow("SWI2", "10 3F")]
    [DataRow("SWI3", "11 3F")]
    [DataRow("ASLA", "48")]
    [DataRow("LSLA", "48")]
    [DataRow("LSLB", "58")]
    [DataRow("ORCC #$50", "1A 50")]
    [DataRow("ANDCC #$AF", "1C AF")]
    [DataRow("CWAI #$EF", "3C EF")]
    [DataRow("LDA #$A5", "86 A5")]
    [DataRow("LDA (1+2)*2", "96 06")]
    [DataRow("LDA #(1+2)*2", "86 06")]
    [DataRow("LDD #$1234", "CC 12 34")]
    [DataRow("LDY #$BEEF", "10 8E BE EF")]
    [DataRow("LDS #$2000", "10 CE 20 00")]
    [DataRow("CMPD #$0100", "10 83 01 00")]
    [DataRow("CMPU #$0200", "11 83 02 00")]
    [DataRow("CMPS #$0300", "11 8C 03 00")]
    [DataRow("LDA $10", "96 10")]
    [DataRow("LDA <$10", "96 10")]
    [DataRow("LDA >$10", "B6 00 10")]
    [DataRow("LDA $1234", "B6 12 34")]
    [DataRow("LSL <$20", "08 20")]
    [DataRow("LSL >$20", "78 00 20")]
    [DataRow("JMP $1234", "7E 12 34")]
    [DataRow("JMP <$80", "0E 80")]
    [DataRow("LDA ,X", "A6 84")]
    [DataRow("LDA [,X]", "A6 94")]
    [DataRow("LDA 5,X", "A6 05")]
    [DataRow("LDA 0,X", "A6 84")]
    [DataRow("LDA 1-1,Y", "A6 A4")]
    [DataRow("LDA [0,X]", "A6 94")]
    [DataRow("LDA <<0,X", "A6 00")]
    [DataRow("LDA <0,X", "A6 88 00")]
    [DataRow("LDA [<0,X]", "A6 98 00")]
    [DataRow("LDA >0,X", "A6 89 00 00")]
    [DataRow("LDA -3,S", "A6 7D")]
    [DataRow("LEAX -2,U", "30 5E")]
    [DataRow("LDA <5,X", "A6 88 05")]
    [DataRow("LDA >5,X", "A6 89 00 05")]
    [DataRow("LDA $20,Y", "A6 A8 20")]
    [DataRow("LDA $1234,S", "A6 E9 12 34")]
    [DataRow("LDA [5,Y]", "A6 B8 05")]
    [DataRow("LDA [$1234,U]", "A6 D9 12 34")]
    [DataRow("LDA ,X+", "A6 80")]
    [DataRow("LDA ,X++", "A6 81")]
    [DataRow("LDA [,X++]", "A6 91")]
    [DataRow("LDA ,-Y", "A6 A2")]
    [DataRow("LDA ,--U", "A6 C3")]
    [DataRow("LDA [,--S]", "A6 F3")]
    [DataRow("LDA A,X", "A6 86")]
    [DataRow("LDA B,Y", "A6 A5")]
    [DataRow("LDA D,U", "A6 CB")]
    [DataRow("LDA [D,S]", "A6 FB")]
    [DataRow("LDA [$1234]", "A6 9F 12 34")]
    [DataRow("JMP [$FFFE]", "6E 9F FF FE")]
    [DataRow("LDA $1010,PCR", "A6 8C 0D")]
    [DataRow("LDA >$1010,PCR", "A6 8D 00 0C")]
    [DataRow("LDA [$1200,PCR]", "A6 9D 01 FC")]
    [DataRow("LDA $1082,PCR", "A6 8C 7F")]
    [DataRow("LDA $1083,PCR", "A6 8D 00 7F")]
    [DataRow("LDA $0F83,PCR", "A6 8C 80")]
    [DataRow("LDA $0F82,PCR", "A6 8D FF 7E")]
    [DataRow("CMPD [$1234,X]", "10 A3 99 12 34")]
    [DataRow("TFR D,X", "1F 01")]
    [DataRow("EXG A,CC", "1E 8A")]
    [DataRow("PSHS A,B,X,PC", "34 96")]
    [DataRow("PSHS D,Y,U", "34 66")]
    [DataRow("PSHS #$00", "34 00")]
    [DataRow("PULU CC,DP,S,PC", "37 C9")]
    [DataRow("BRA $1000", "20 FE")]
    [DataRow("BHS $1004", "24 02")]
    [DataRow("BLO $1004", "25 02")]
    [DataRow("LBRA $1000", "16 FF FD")]
    [DataRow("LBHS $0F00", "10 24 FE FC")]
    [DataRow("LBLO $0F00", "10 25 FE FC")]
    [DataRow("BSR $1020", "8D 1E")]
    [DataRow("LBSR $2000", "17 0F FD")]
    [DataRow("NEG $40", "00 40")]
    [DataRow("NEGA", "40")]
    [DataRow("LSRB", "54")]
    [DataRow("XNC $40", "02 40")]
    [DataRow("XNCA", "42")]
    [DataRow("XDECB", "5B")]
    [DataRow("XDEC ,X", "6B 84")]
    [DataRow("XCLRA", "4E")]
    [DataRow("X18", "18")]
    [DataRow("XANDCC #$AF", "38 AF")]
    [DataRow("XRES", "3E")]
    [DataRow("XSWI2", "10 3E")]
    [DataRow("XFIRQ", "11 3E")]
    [DataRow("XHCF", "14")]
    [DataRow("XSTA #$12", "87 12")]
    [DataRow("XSTB #$12", "C7 12")]
    [DataRow("XSTX #$1234", "8F 12 34")]
    [DataRow("XSTU #$1234", "CF 12 34")]
    [DataRow("XSTY #$1234", "10 8F 12 34")]
    [DataRow("XSTS #$1234", "10 CF 12 34")]
    [DataRow("XADDD #$0001", "10 C3 00 01")]
    [DataRow("XADDU $40", "11 D3 40")]
    public void EncodesInstructions(string source, string expected)
    {
        AssemblyResult result = Assemble(source, size: expected.Split(' ').Length);
        result.Diagnostics.Should().BeEmpty();
        Hex(result.Sections[0].Bytes.Span).Should().Be(expected);
    }

    /// <summary>
    ///  Invalid postbytes, mismatched register widths and illegal stack registers are diagnosed cleanly.
    /// </summary>
    /// <param name="source">The invalid instruction.</param>
    /// <param name="message">Substring expected in the diagnostic.</param>
    [TestMethod]
    [DataRow("TFR D,A", "two 8-bit or two 16-bit")]
    [DataRow("EXG X,CC", "two 8-bit or two 16-bit")]
    [DataRow("PSHS S", "cannot transfer S")]
    [DataRow("PULU U", "cannot transfer U")]
    [DataRow("LDA [,X+]", "Single-step auto-increment")]
    [DataRow("LDA [,-Y]", "Single-step auto-increment")]
    [DataRow("LDA <<20,X", "signed 5-bit range")]
    [DataRow("LEAX $1234", "unsupported addressing mode")]
    public void DiagnosesInvalidInstructions(string source, string message)
    {
        AssemblyResult result = Assemble(source);
        result.Diagnostics.Should().ContainSingle().Which.Message.Should().Contain(message);
    }

    /// <summary>
    ///  Disassembly and native export round-trip 1-to-5-byte MC6809 instructions, width overrides and vectors.
    /// </summary>
    [TestMethod]
    public void DisassemblesAndRoundTripsFiveByteAndWidthForcedEncodings()
    {
        const string Program = """
            .cpu M6809
                    .org $4000
            Entry:  LDS #$2000
                    LDA <$10
                    LDA >$0010
                    LDA 5,X
                    LDA <5,X
                    LDA >5,X
                    LDA <<0,Y
                    LDA [<0,U]
                    LDA >0,S
                    LDA 5,Y
                    LDA -3,S
                    LDA [,X++]
                    LDA [$1234]
                    CMPD [$1234,Y]
                    LEAX Data,PCR
                    LEAY >Entry,PCR
                    PSHS #$00
                    PSHS CC,A,B,DP,X,Y,U,PC
                    TFR D,U
                    EXG A,DP
                    LBNE Done
            Done:   RTS
            Data:   .dbyt $CAFE
            """;

        AssemblyResult assembled = new NativeAssembler().Assemble(
            new AssemblySource(Program, "coco.asm"),
            new AssemblyOptions(M6809Isa.Name, origin: 0x4000, imageSize: 96));

        assembled.Diagnostics.Should().BeEmpty();

        AnalysisProject project = new(assembled.Sections[0].Bytes.Span, origin: 0x4000, M6809Isa.InstructionSet);
        project.EntryPoints.Add(0x4000);
        DisassemblyResult analysis = Disassembler.Analyze(project);
        analysis.Success.Should().BeTrue();
        analysis.Instructions.Should().Contain(instruction => instruction.Size == 5 && instruction.Mnemonic == "CMPD");

        AssemblyResult roundTrip = new NativeAssembler().Assemble(
            new AssemblySource(analysis.ExportSource(), "roundtrip.asm"),
            analysis.Options);

        roundTrip.Diagnostics.Should().BeEmpty();
        roundTrip.Sections[0].Bytes.Span.SequenceEqual(assembled.Sections[0].Bytes.Span).Should().BeTrue();
    }

    /// <summary>
    ///  Undocumented encodings disassemble with Banks's names, and export round-trips them, the aliases of
    ///  documented instructions as bytes.
    /// </summary>
    [TestMethod]
    public void DisassemblesAndRoundTripsUndocumentedEncodings()
    {
        byte[] code =
        [
            0x01, 0x40,             // NEG <$40, the alias of $00
            0x02, 0x40,             // XNC <$40
            0x41,                   // NEGA, the alias of $40
            0x4E,                   // XCLRA
            0x1B,                   // NOP, the alias of $12
            0x18,                   // X18
            0x38, 0xAF,             // XANDCC #$AF
            0x10, 0xC3, 0x00, 0x01, // XADDD #$0001
            0x87, 0x12,             // XSTA #$12
            0x8F, 0x12, 0x34,       // XSTX #$1234
            0x11, 0x3E,             // XFIRQ
            0x14                    // XHCF
        ];

        AnalysisProject project = new(code, origin: 0x4000, M6809Isa.InstructionSet);
        project.EntryPoints.Add(0x4000);
        DisassemblyResult analysis = Disassembler.Analyze(project);
        analysis.Success.Should().BeTrue();
        string[] expected = ["NEG", "XNC", "NEGA", "XCLRA", "NOP", "X18", "XANDCC", "XADDD", "XSTA", "XSTX", "XFIRQ", "XHCF"];
        analysis.Instructions.Select(instruction => instruction.Mnemonic).Should().Equal(expected);
        analysis.Instructions.Should().OnlyContain(instruction => instruction.IsUndocumented);

        AssemblyResult roundTrip = new NativeAssembler().Assemble(
            new AssemblySource(analysis.ExportSource(), "undocumented.asm"),
            analysis.Options);

        roundTrip.Diagnostics.Should().BeEmpty();
        roundTrip.Sections[0].Bytes.ToArray().Should().Equal(code);
    }

    /// <summary>
    ///  Flow analysis follows big-endian MC6809 hardware vectors and indirect jumps.
    /// </summary>
    [TestMethod]
    public void FlowAnalysisFollowsBigEndianVectorsAndIndirectJumps()
    {
        byte[] rom = new byte[0x100];
        // $FF00: JMP [$FF10]; $FF10: .dbyt $FF20; $FF20: RTS; $FFFE (RESET): .dbyt $FF00
        rom[0x00] = 0x6E;
        rom[0x01] = 0x9F;
        rom[0x02] = 0xFF;
        rom[0x03] = 0x10;
        rom[0x10] = 0xFF;
        rom[0x11] = 0x20;
        rom[0x20] = 0x39;
        rom[0xFE] = 0xFF;
        rom[0xFF] = 0x00;

        AnalysisProject project = new(rom, origin: 0xFF00, M6809Isa.InstructionSet);
        DisassemblyResult result = Disassembler.Analyze(project);
        result.Success.Should().BeTrue();
        result.Instructions.Select(instruction => instruction.Address).Should().Equal(0xFF00, 0xFF20);
    }

    /// <summary>
    ///  Flow analysis follows a PC-relative jump to its target and a PC-relative indirect jump through its pointer.
    /// </summary>
    [TestMethod]
    public void FlowAnalysisFollowsProgramCounterRelativeJumps()
    {
        byte[] rom = new byte[0x100];
        // $FF00: JMP $FF10,PCR; $FF10: JMP [$FF20,PCR]; $FF20: .dbyt $FF30; $FF30: RTS; RESET: .dbyt $FF00
        rom[0x00] = 0x6E;
        rom[0x01] = 0x8C;
        rom[0x02] = 0x0D;
        rom[0x10] = 0x6E;
        rom[0x11] = 0x9C;
        rom[0x12] = 0x0D;
        rom[0x20] = 0xFF;
        rom[0x21] = 0x30;
        rom[0x30] = 0x39;
        rom[0xFE] = 0xFF;
        rom[0xFF] = 0x00;

        AnalysisProject project = new(rom, origin: 0xFF00, M6809Isa.InstructionSet);
        DisassemblyResult result = Disassembler.Analyze(project);
        result.Success.Should().BeTrue();
        result.Instructions.Select(instruction => instruction.Address).Should().Equal(0xFF00, 0xFF10, 0xFF30);
        result.Instructions[0].Flow.Should().Be(DisassemblyFlow.Jump);
        result.Instructions[0].DirectTarget.Should().Be((ushort)0xFF10);
        result.Instructions[1].Flow.Should().Be(DisassemblyFlow.IndirectJump);
        result.Instructions[1].DirectTarget.Should().BeNull();
    }

    /// <summary>
    ///  Scoped symbols, documentation flag words (<c>entire</c>, <c>fast-interrupt</c>) and instruction docs work.
    /// </summary>
    [TestMethod]
    public void ResolvesScopesDocumentationFlagsAndInstructionDocs()
    {
        const string Source = """
            .cpu M6809
            ;; Copies a byte and preserves interrupt state.
            ;; In:    X = source, Y = destination
            ;; Out:   zero = set when the copied byte was zero, carry = unchanged
            ;; Keeps: X, Y, entire, fast-interrupt
            .proc CopyByte
                    LDA ,X
                    STA ,Y
                    LEAX @tail,PCR
            @tail:  RTS
            .endproc
            """;

        AssemblySource assemblySource = new(Source, "copy.asm");
        AssemblyResult result = new NativeAssembler().Assemble(
            assemblySource,
            new AssemblyOptions(M6809Isa.Name, origin: 0x1000, imageSize: 16));

        result.Diagnostics.Should().BeEmpty();
        DocumentationSet set = DocumentationSet.Create([DocumentationParser.Parse(Source, "copy.asm")], result);
        DocumentationResolver resolver = new(set);
        resolver.Check().Should().BeEmpty();

        string? hover = InstructionDocs.Describe("CMPD", M6809Isa.InstructionSet);
        hover.Should().NotBeNull();
        hover.Should().Contain("10 83");
    }

    private static AssemblyResult Assemble(string line, int size = 8) =>
        new NativeAssembler().Assemble(
            new AssemblySource($".cpu M6809\n{line}\n", "test.asm"),
            new AssemblyOptions(M6809Isa.Name, origin: 0x1000, imageSize: size));

    private static string Hex(ReadOnlySpan<byte> bytes) =>
        string.Join(' ', bytes.ToArray().Select(value => value.ToString("X2")));
}
