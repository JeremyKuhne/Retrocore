// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Cpu.Z80;
using Retrocore.Isa;
using NativeAssembler = Retrocore.Assembler.Assembler;

namespace Retrocore.Tests;

/// <summary>
///  The Z80's native syntax assembles to Zilog's encodings, including the undocumented instructions.
/// </summary>
[TestClass]
public class Z80AssemblerTests
{
    /// <summary>
    ///  Instructions encode as the Z80 CPU User Manual and the undocumented-instruction references give them.
    /// </summary>
    /// <param name="source">The instruction, assembled at <c>$1000</c>.</param>
    /// <param name="expected">The bytes, as hex pairs.</param>
    [TestMethod]
    [DataRow("LD A,B", "78")]
    [DataRow("ld b, [hl]", "46")]
    [DataRow("LD [HL],7", "36 07")]
    [DataRow("LD A,[IX+5]", "DD 7E 05")]
    [DataRow("LD [IY-3],A", "FD 77 FD")]
    [DataRow("LD [IX+2],$41", "DD 36 02 41")]
    [DataRow("LD [IX],A", "DD 77 00")]
    [DataRow("LD A,[IX + 1 + 2]", "DD 7E 03")]
    [DataRow("LD A,[BC]", "0A")]
    [DataRow("LD [DE],A", "12")]
    [DataRow("LD A,[$1234]", "3A 34 12")]
    [DataRow("LD [$1234],A", "32 34 12")]
    [DataRow("LD HL,[$1234]", "2A 34 12")]
    [DataRow("LD [$1234],HL", "22 34 12")]
    [DataRow("LD BC,[$1234]", "ED 4B 34 12")]
    [DataRow("LD [$1234],SP", "ED 73 34 12")]
    [DataRow("LD IX,[$1234]", "DD 2A 34 12")]
    [DataRow("LD [$1234],IY", "FD 22 34 12")]
    [DataRow("LD SP,HL", "F9")]
    [DataRow("LD SP,IX", "DD F9")]
    [DataRow("LD HL,$ABCD", "21 CD AB")]
    [DataRow("LD IY,$ABCD", "FD 21 CD AB")]
    [DataRow("LD A,(1+2)*2", "3E 06")]
    [DataRow("LD A,I", "ED 57")]
    [DataRow("LD R,A", "ED 4F")]
    [DataRow("PUSH AF", "F5")]
    [DataRow("POP IX", "DD E1")]
    [DataRow("EX AF,AF'", "08")]
    [DataRow("EX AF, AF' ; swap the accumulator and flags", "08")]
    [DataRow("EX DE,HL", "EB")]
    [DataRow("EX [SP],HL", "E3")]
    [DataRow("EX [SP],IY", "FD E3")]
    [DataRow("EXX", "D9")]
    [DataRow("LDIR", "ED B0")]
    [DataRow("CPDR", "ED B9")]
    [DataRow("OTIR", "ED B3")]
    [DataRow("INDR", "ED BA")]
    [DataRow("ADD A,5", "C6 05")]
    [DataRow("ADD A,[HL]", "86")]
    [DataRow("ADC A,[IX+1]", "DD 8E 01")]
    [DataRow("SUB B", "90")]
    [DataRow("SBC A,$10", "DE 10")]
    [DataRow("AND [IY]", "FD A6 00")]
    [DataRow("XOR A", "AF")]
    [DataRow("OR $80", "F6 80")]
    [DataRow("CP [HL]", "BE")]
    [DataRow("CP 'A'", "FE 41")]
    [DataRow("INC [IX+4]", "DD 34 04")]
    [DataRow("DEC IY", "FD 2B")]
    [DataRow("INC SP", "33")]
    [DataRow("ADD HL,DE", "19")]
    [DataRow("ADC HL,SP", "ED 7A")]
    [DataRow("SBC HL,BC", "ED 42")]
    [DataRow("ADD IX,IX", "DD 29")]
    [DataRow("ADD IY,DE", "FD 19")]
    [DataRow("DAA", "27")]
    [DataRow("CPL", "2F")]
    [DataRow("NEG", "ED 44")]
    [DataRow("CCF", "3F")]
    [DataRow("SCF", "37")]
    [DataRow("NOP", "00")]
    [DataRow("HALT", "76")]
    [DataRow("DI", "F3")]
    [DataRow("EI", "FB")]
    [DataRow("IM 0", "ED 46")]
    [DataRow("IM 1", "ED 56")]
    [DataRow("IM 2", "ED 5E")]
    [DataRow("RLCA", "07")]
    [DataRow("RRA", "1F")]
    [DataRow("RLC B", "CB 00")]
    [DataRow("RL [HL]", "CB 16")]
    [DataRow("SRL A", "CB 3F")]
    [DataRow("SLA [IX+3]", "DD CB 03 26")]
    [DataRow("RRD", "ED 67")]
    [DataRow("RLD", "ED 6F")]
    [DataRow("BIT 7,A", "CB 7F")]
    [DataRow("BIT 0,[HL]", "CB 46")]
    [DataRow("SET 3,[IY-2]", "FD CB FE DE")]
    [DataRow("RES 1,C", "CB 89")]
    [DataRow("BIT 6,[IX+$10]", "DD CB 10 76")]
    [DataRow("BIT 2+1,E", "CB 5B")]
    [DataRow("JP $1234", "C3 34 12")]
    [DataRow("JP NZ,$1234", "C2 34 12")]
    [DataRow("JP C,$1234", "DA 34 12")]
    [DataRow("JP M,$1234", "FA 34 12")]
    [DataRow("JP [HL]", "E9")]
    [DataRow("JP [IY]", "FD E9")]
    [DataRow("JR $1000", "18 FE")]
    [DataRow("JR NC,$1005", "30 03")]
    [DataRow("JR C,$1000", "38 FE")]
    [DataRow("DJNZ $1000", "10 FE")]
    [DataRow("CALL $1234", "CD 34 12")]
    [DataRow("CALL PE,$1234", "EC 34 12")]
    [DataRow("RET", "C9")]
    [DataRow("RET Z", "C8")]
    [DataRow("RET C", "D8")]
    [DataRow("RETI", "ED 4D")]
    [DataRow("RETN", "ED 45")]
    [DataRow("RST $38", "FF")]
    [DataRow("RST 0", "C7")]
    [DataRow("RST 8", "CF")]
    [DataRow("IN A,[$FE]", "DB FE")]
    [DataRow("IN B,[C]", "ED 40")]
    [DataRow("OUT [$FE],A", "D3 FE")]
    [DataRow("OUT [C],E", "ED 59")]
    [DataRow("INI", "ED A2")]
    [DataRow("OUTD", "ED AB")]
    [DataRow("SLL B", "CB 30")]
    [DataRow("LD IXH,5", "DD 26 05")]
    [DataRow("ADD A,IYL", "FD 85")]
    [DataRow("LD B,IXL", "DD 45")]
    [DataRow("LD IXH,IXL", "DD 65")]
    [DataRow("INC IXL", "DD 2C")]
    [DataRow("IN [C]", "ED 70")]
    [DataRow("OUT [C],0", "ED 71")]
    [DataRow("RLC [IX+1],B", "DD CB 01 00")]
    [DataRow("SET 0,[IY+2],A", "FD CB 02 C7")]
    [DataRow("SLL [IX-1]", "DD CB FF 36")]
    public void EncodesInstructions(string source, string expected)
    {
        AssemblyResult result = Assemble(source, size: expected.Split(' ').Length);
        result.Diagnostics.Should().BeEmpty();
        Hex(result.Sections[0].Bytes.Span).Should().Be(expected);
    }

    /// <summary>
    ///  Out-of-range fields and forms the Z80 lacks are diagnosed.
    /// </summary>
    /// <param name="source">The instruction.</param>
    /// <param name="message">Text the diagnostic contains.</param>
    [TestMethod]
    [DataRow("LD A,[IX+128]", "Displacement is outside the signed 8-bit range.")]
    [DataRow("LD A,[IX-129]", "Displacement is outside the signed 8-bit range.")]
    [DataRow("BIT 8,A", "Bit number must be 0-7.")]
    [DataRow("RST $39", "Restart address must be")]
    [DataRow("RST $40", "Restart address must be")]
    [DataRow("JR $1100", "outside the signed 8-bit range")]
    [DataRow("LD A,256", "outside the byte range")]
    [DataRow("LD [HL],[HL]", "Invalid expression")]
    [DataRow("JR PO,$1000", "Invalid expression")]
    [DataRow("LDA #1", "Unknown instruction")]
    public void DiagnosesInvalidInstructions(string source, string message)
    {
        AssemblyResult result = Assemble(source);
        result.Diagnostics.Should().ContainSingle().Which.Message.Should().Contain(message);
    }

    /// <summary>
    ///  Labels, forward references and <c>.cpu</c> select and resolve as for the 6502.
    /// </summary>
    [TestMethod]
    public void ResolvesLabelsAndSwitchesCpus()
    {
        AssemblyResult result = new NativeAssembler().Assemble(
            new AssemblySource(
                """
                .cpu Z80
                Start:  LD HL,Table
                        LD A,[IX+Offset]
                Loop:   DJNZ Loop
                        JR NZ,Start
                        CALL C,Table
                Offset = 3
                Table:  .byte 1
                .cpu Mos6502
                        LDA #1
                """,
                "z80.asm"),
            new AssemblyOptions(ProcessorVariant.Mos6502, 0x4000, 16));

        result.Diagnostics.Should().BeEmpty();
        Hex(result.Sections[0].Bytes.Span[..15]).Should().Be("21 0D 40 DD 7E 03 10 FE 20 F6 DC 0D 40 01 A9");
    }

    /// <summary>
    ///  The extension README's Z80 example assembles to the bytes its comments give.
    /// </summary>
    [TestMethod]
    public void ReadmeExampleAssembles()
    {
        AssemblyResult result = new NativeAssembler().Assemble(
            new AssemblySource(
                """
                .cpu Z80
                Flags = 2
                Loop:   LD   A,[HL]
                        LD   A,(5+3)*2
                        LD   [IX+5],A
                        LD   B,[IY-2]
                        LD   A,[IX]
                        LD   HL,[Table]
                        IN   A,[$FE]
                        BIT  7,[IX+Flags]
                        RST  $38
                        EX   AF,AF'
                        JR   NZ,Loop
                Table:
                """,
                "readme.asm"),
            new AssemblyOptions(Z80Isa.Name, 0x8000, 29));

        result.Diagnostics.Should().BeEmpty();
        Hex(result.Sections[0].Bytes.Span).Should().Be(
            "7E 3E 10 DD 77 05 FD 46 FE DD 7E 00 2A 19 80 DB FE DD CB 02 7E FF 08 20 E7 00 00 00 00");
    }

    /// <summary>
    ///  A register name in an operand's register place is not a scoped symbol, even when a scope defines one.
    /// </summary>
    [TestMethod]
    public void RegisterNamesAreNotQualified()
    {
        AssemblyResult result = new NativeAssembler().Assemble(
            new AssemblySource(
                """
                .cpu Z80
                .scope Inner
                IX = 1
                HL = 2
                        LD A,[IX+HL]
                        LD HL,[HL+$1000]
                .endscope
                """,
                "scope.asm"),
            new AssemblyOptions(Z80Isa.Name, 0x4000, 6));

        result.Diagnostics.Should().BeEmpty();
        Hex(result.Sections[0].Bytes.Span).Should().Be("DD 7E 02 2A 02 10");
    }

    /// <summary>
    ///  Every Z80 opcode, prefixed and undocumented ones included, decodes, formats in native syntax and
    ///  assembles back to its own bytes, or for an alias to the canonical encoding of its mnemonic and form.
    /// </summary>
    [TestMethod]
    public void EveryOpcodeRoundTrips()
    {
        InstructionSet set = Z80Isa.InstructionSet;
        int decoded = 0;
        int aliases = 0;
        foreach (byte[] bytes in AllOpcodes())
        {
            const ushort Address = 0x4000;
            Disassembler.TryDecode(bytes, Address, set, out DisassembledInstruction instruction).Should().BeTrue(Hex(bytes));
            instruction.Size.Should().Be(bytes.Length, Hex(bytes));
            decoded++;

            string text = instruction.ToString();
            AssemblyResult result = new NativeAssembler().Assemble(
                new AssemblySource(text, "opcode.asm"),
                new AssemblyOptions(Z80Isa.Name, Address, 4));

            result.Diagnostics.Should().BeEmpty($"{Hex(bytes)} {text}");
            set.TryGet(instruction.Encoding.Mnemonic, instruction.Encoding.Form, out int canonical).Should().BeTrue(text);
            if (canonical == instruction.EncodingId)
            {
                Hex(result.Sections[0].Bytes.Span[..bytes.Length]).Should().Be(Hex(bytes), text);
                continue;
            }

            // An alias assembles to the canonical encoding, which decodes back to the same text.
            aliases++;
            instruction.IsUndocumented.Should().BeTrue($"{Hex(bytes)} {text} aliases a documented encoding");
            Disassembler.TryDecode(result.Sections[0].Bytes.Span, Address, set, out DisassembledInstruction canonicalInstruction)
                .Should().BeTrue(text);

            canonicalInstruction.EncodingId.Should().Be(canonical, text);
            canonicalInstruction.ToString().Should().Be(text);
        }

        // 252 unprefixed, 256 CB, 256 ED, 2 x 252 DD and FD (without DD, ED and FD after them), 2 x 256 DD CB.
        decoded.Should().Be(1780);
        aliases.Should().BeGreaterThan(400);
    }

    /// <summary>
    ///  The decoder never mistakes a <c>DD CB</c> displacement for the opcode byte after it.
    /// </summary>
    [TestMethod]
    public void SplitOpcodesSkipTheirDisplacement()
    {
        InstructionSet set = Z80Isa.InstructionSet;
        for (int displacement = 0; displacement < 256; displacement++)
        {
            byte[] bytes = [0xFD, 0xCB, (byte)displacement, 0x46];
            Disassembler.TryDecode(bytes, 0, set, out DisassembledInstruction instruction).Should().BeTrue();
            instruction.Mnemonic.Should().Be("BIT");
            instruction.Field(0).Should().Be(0);
            ((short)instruction.Field(1)).Should().Be((sbyte)displacement);
        }

        Disassembler.TryDecode([0xDD, 0xCB, 0x05], 0, set, out _).Should().BeFalse("the opcode byte is missing");
    }

    /// <summary>
    ///  The disassembler writes signed displacements, bit numbers and restarts in native syntax.
    /// </summary>
    /// <param name="bytes">The encoding, as hex pairs.</param>
    /// <param name="text">The native text at <c>$1000</c>.</param>
    [TestMethod]
    [DataRow("DD 7E 05", "LD A,[IX+$05]")]
    [DataRow("FD 77 FD", "LD [IY-$03],A")]
    [DataRow("DD 36 80 41", "LD [IX-$80],$41")]
    [DataRow("FD CB FE DE", "SET 3,[IY-$02]")]
    [DataRow("DD CB 01 00", "RLC [IX+$01],B")]
    [DataRow("CB 7F", "BIT 7,A")]
    [DataRow("EF", "RST $28")]
    [DataRow("18 FE", "JR $1000")]
    [DataRow("DB FE", "IN A,[$FE]")]
    [DataRow("08", "EX AF,AF'")]
    [DataRow("ED 70", "IN [C]")]
    public void FormatsNativeSyntax(string bytes, string text)
    {
        byte[] code = Convert.FromHexString(bytes.Replace(" ", "", StringComparison.Ordinal));
        Disassembler.TryDecode(code, 0x1000, Z80Isa.InstructionSet, out DisassembledInstruction instruction).Should().BeTrue();
        instruction.ToString().Should().Be(text);
    }

    /// <summary>
    ///  Flow analysis follows absolute and conditional jumps, calls and restarts, and records memory reads and
    ///  writes by form.
    /// </summary>
    [TestMethod]
    public void AnalysisFollowsZ80Flow()
    {
        // $0000: JP NZ,$0008 / LD [$0020],A / RST $10 / HALT ... $0008: LD A,[$0021] / RET ... $0010: JP [HL]
        byte[] image = new byte[0x30];
        byte[] code = [0xC2, 0x08, 0x00, 0x32, 0x20, 0x00, 0xD7, 0x76];
        code.CopyTo(image, 0);
        byte[] target = [0x3A, 0x21, 0x00, 0xC9];
        target.CopyTo(image, 8);
        image[0x10] = 0xE9;

        DisassemblyResult result = Disassembler.Analyze(new AnalysisProject(image, 0, Z80Isa.InstructionSet));
        result.Diagnostics.Where(diagnostic => diagnostic.IsError).Should().BeEmpty();
        ushort[] starts = [0x0000, 0x0003, 0x0006, 0x0007, 0x0008, 0x000B, 0x0010];
        result.Instructions.Select(instruction => instruction.Address).Should().Contain(starts);
        result.References.Should().Contain(reference => reference.Target == 0x0008 && reference.Kind == DisassemblyReferenceKind.Branch);
        result.References.Should().Contain(reference => reference.Target == 0x0010 && reference.Kind == DisassemblyReferenceKind.Call);
        result.References.Should().Contain(reference => reference.Target == 0x0020 && reference.Kind == DisassemblyReferenceKind.Write);
        result.References.Should().Contain(reference => reference.Target == 0x0021 && reference.Kind == DisassemblyReferenceKind.Read);
        result.References.Should().NotContain(reference => reference.Kind == DisassemblyReferenceKind.IndirectJump);
    }

    /// <summary>
    ///  An exported Z80 disassembly, with aliases and data as bytes, assembles back to the same image.
    /// </summary>
    [TestMethod]
    public void ExportedDisassemblyReassembles()
    {
        byte[] image = [.. AllOpcodes().SelectMany(bytes => bytes)];
        DisassemblyResult result = Disassembler.Disassemble(image, 0x2000, Z80Isa.InstructionSet);
        string source = result.ExportSource();
        source.Should().StartWith(".cpu Z80\n");

        AssemblyResult assembled = new NativeAssembler().Assemble(new AssemblySource(source, "export.asm"), result.Options);
        assembled.Diagnostics.Should().BeEmpty();
        assembled.Sections[0].Bytes.ToArray().Should().Equal(image);
    }

    /// <summary>
    ///  An exported symbol named like a register keeps its meaning as an address.
    /// </summary>
    [TestMethod]
    public void ExportKeepsSymbolsNamedLikeRegisters()
    {
        byte[] image = [0x3A, 0x05, 0x00, 0x76, 0x00, 0x42];
        AnalysisProject project = new(image, 0, Z80Isa.InstructionSet) { FollowVectors = false };
        project.Symbols[0x0005] = "HL";
        DisassemblyResult result = Disassembler.Analyze(project);
        string source = result.ExportSource();
        source.Should().Contain("LD A,[HL+0]");

        AssemblyResult assembled = new NativeAssembler().Assemble(new AssemblySource(source, "names.asm"), result.Options);
        assembled.Diagnostics.Should().BeEmpty();
        assembled.Sections[0].Bytes.ToArray().Should().Equal(image);
    }

    /// <summary>
    ///  Every encoding of every opcode space, with sample operands: bit and restart fields vary in the opcode.
    /// </summary>
    /// <returns>Each instruction's bytes.</returns>
    private static IEnumerable<byte[]> AllOpcodes()
    {
        static bool Prefix(int value) => value is 0xCB or 0xDD or 0xED or 0xFD;
        for (int opcode = 0; opcode < 256; opcode++)
        {
            if (!Prefix(opcode)) { yield return WithOperands([(byte)opcode]); }
        }

        foreach (byte prefix in (byte[])[0xCB, 0xED])
        {
            for (int opcode = 0; opcode < 256; opcode++) { yield return WithOperands([prefix, (byte)opcode]); }
        }

        foreach (byte prefix in (byte[])[0xDD, 0xFD])
        {
            for (int opcode = 0; opcode < 256; opcode++)
            {
                if (opcode is not (0xCB or 0xDD or 0xED or 0xFD)) { yield return WithOperands([prefix, (byte)opcode]); }
            }

            for (int opcode = 0; opcode < 256; opcode++) { yield return [prefix, 0xCB, 0xFB, (byte)opcode]; }
        }
    }

    // Appends sample operand bytes for the encoding the opcode decodes to: a negative displacement, $34 bytes.
    private static byte[] WithOperands(byte[] opcode)
    {
        InstructionSet set = Z80Isa.InstructionSet;
        byte[] padded = [.. opcode, 0xFB, 0x34, 0x12];
        if (!set.TryDecode(padded, out int encoding)) { return opcode; }
        int size = set.Size(encoding);
        byte[] bytes = padded[..size];
        OperandForm form = set.GetForm(set.GetEncoding(encoding).Form);
        int offset = set.GetEncoding(encoding).OpcodeBytesBeforeOperands;
        for (int field = 0; field < form.FieldCount; field++)
        {
            int at = offset + form.FieldOffset(field);
            switch (form.Field(field))
            {
                case OperandFieldKind.Byte:
                    bytes[at] = 0x5A;
                    break;
                case OperandFieldKind.Relative8:
                    bytes[at] = 0x05;
                    break;
                case OperandFieldKind.Word:
                    bytes[at] = 0x34;
                    bytes[at + 1] = 0x12;
                    break;
            }
        }

        return bytes;
    }

    private static AssemblyResult Assemble(string source, int size = 4) =>
        new NativeAssembler().Assemble(
            new AssemblySource($".cpu Z80\n{source}\n", "z80.asm"),
            new AssemblyOptions(Z80Isa.Name, 0x1000, size));

    private static string Hex(ReadOnlySpan<byte> bytes) => string.Join(' ', bytes.ToArray().Select(value => $"{value:X2}"));
}
