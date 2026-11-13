// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Cpu.I8080;
using Retrocore.Isa;
using NativeAssembler = Retrocore.Assembler.Assembler;

namespace Retrocore.Tests;

/// <summary>
///  The 8080's and 8085's native syntax, Intel's, assembles to Intel's encodings, including the undocumented
///  instructions.
/// </summary>
[TestClass]
public class I8080AssemblerTests
{
    /// <summary>
    ///  Instructions encode as the 8080 and 8085 manuals give them.
    /// </summary>
    /// <param name="source">The instruction, assembled at <c>$1000</c> for the 8080.</param>
    /// <param name="expected">The bytes, as hex pairs.</param>
    [TestMethod]
    [DataRow("MOV A,B", "78")]
    [DataRow("mov b, m", "46")]
    [DataRow("MOV M,A", "77")]
    [DataRow("MVI A,(1+2)*2", "3E 06")]
    [DataRow("MVI M,7", "36 07")]
    [DataRow("MVI C,'A'", "0E 41")]
    [DataRow("LXI B,$1234", "01 34 12")]
    [DataRow("LXI H,$ABCD", "21 CD AB")]
    [DataRow("LXI SP,$F000", "31 00 F0")]
    [DataRow("STAX B", "02")]
    [DataRow("LDAX D", "1A")]
    [DataRow("SHLD $1234", "22 34 12")]
    [DataRow("LHLD $1234", "2A 34 12")]
    [DataRow("STA $1234", "32 34 12")]
    [DataRow("LDA $1234", "3A 34 12")]
    [DataRow("INX SP", "33")]
    [DataRow("DCX H", "2B")]
    [DataRow("INR M", "34")]
    [DataRow("DCR A", "3D")]
    [DataRow("DAD D", "19")]
    [DataRow("RLC", "07")]
    [DataRow("RAR", "1F")]
    [DataRow("DAA", "27")]
    [DataRow("CMA", "2F")]
    [DataRow("STC", "37")]
    [DataRow("CMC", "3F")]
    [DataRow("HLT", "76")]
    [DataRow("ADD M", "86")]
    [DataRow("ADC B", "88")]
    [DataRow("SUB C", "91")]
    [DataRow("SBB D", "9A")]
    [DataRow("ANA E", "A3")]
    [DataRow("XRA A", "AF")]
    [DataRow("ORA H", "B4")]
    [DataRow("CMP L", "BD")]
    [DataRow("ADI 5", "C6 05")]
    [DataRow("ACI 5", "CE 05")]
    [DataRow("SUI 5", "D6 05")]
    [DataRow("SBI 5", "DE 05")]
    [DataRow("ANI $0F", "E6 0F")]
    [DataRow("XRI $FF", "EE FF")]
    [DataRow("ORI $80", "F6 80")]
    [DataRow("CPI 'A'", "FE 41")]
    [DataRow("RNZ", "C0")]
    [DataRow("RM", "F8")]
    [DataRow("RET", "C9")]
    [DataRow("POP PSW", "F1")]
    [DataRow("PUSH B", "C5")]
    [DataRow("JMP $1234", "C3 34 12")]
    [DataRow("JPE $1234", "EA 34 12")]
    [DataRow("CALL $1234", "CD 34 12")]
    [DataRow("CP $1234", "F4 34 12")]
    [DataRow("RST 0", "C7")]
    [DataRow("RST 7", "FF")]
    [DataRow("OUT $10", "D3 10")]
    [DataRow("IN $10", "DB 10")]
    [DataRow("XTHL", "E3")]
    [DataRow("XCHG", "EB")]
    [DataRow("DI", "F3")]
    [DataRow("EI", "FB")]
    [DataRow("PCHL", "E9")]
    [DataRow("SPHL", "F9")]
    [DataRow("NOP", "00")]
    public void EncodesInstructions(string source, string expected)
    {
        AssemblyResult result = Assemble(I8080Isa.Name, source, size: expected.Split(' ').Length);
        result.Diagnostics.Should().BeEmpty();
        Hex(result.Sections[0].Bytes.Span).Should().Be(expected);
    }

    /// <summary>
    ///  The 8085 adds RIM and SIM and its undocumented instructions in the 8080's undocumented opcodes.
    /// </summary>
    /// <param name="source">The instruction, assembled at <c>$1000</c> for the 8085.</param>
    /// <param name="expected">The bytes, as hex pairs.</param>
    [TestMethod]
    [DataRow("RIM", "20")]
    [DataRow("SIM", "30")]
    [DataRow("DSUB", "08")]
    [DataRow("ARHL", "10")]
    [DataRow("RDEL", "18")]
    [DataRow("LDHI 5", "28 05")]
    [DataRow("LDSI 5", "38 05")]
    [DataRow("RSTV", "CB")]
    [DataRow("SHLX", "D9")]
    [DataRow("JNK $1234", "DD 34 12")]
    [DataRow("LHLX", "ED")]
    [DataRow("JK $1234", "FD 34 12")]
    [DataRow("JMP $1234", "C3 34 12")]
    public void Encodes8085Instructions(string source, string expected)
    {
        AssemblyResult result = Assemble(I8080Isa.Name8085, source, size: expected.Split(' ').Length);
        result.Diagnostics.Should().BeEmpty();
        Hex(result.Sections[0].Bytes.Span).Should().Be(expected);
    }

    /// <summary>
    ///  Out-of-range fields and forms the CPU lacks are diagnosed.
    /// </summary>
    /// <param name="cpu">The CPU.</param>
    /// <param name="source">The instruction.</param>
    /// <param name="message">Text the diagnostic contains.</param>
    [TestMethod]
    [DataRow("I8080", "RST 8", "Restart number must be 0-7")]
    [DataRow("I8080", "MVI A,$100", "outside the byte range")]
    [DataRow("I8080", "RIM", "unsupported addressing mode")]
    [DataRow("I8080", "MOV M,M", "unsupported addressing mode")]
    [DataRow("I8080", "LXI PSW,0", "unsupported addressing mode")]
    [DataRow("I8080", "PUSH SP", "unsupported addressing mode")]
    public void DiagnosesInvalidInstructions(string cpu, string source, string message)
    {
        AssemblyResult result = Assemble(cpu, source);
        result.Diagnostics.Should().ContainSingle().Which.Message.Should().Contain(message);
    }

    /// <summary>
    ///  Labels and forward references resolve, and <c>.cpu</c> switches between the 8080, the 8085 and the Z80.
    /// </summary>
    [TestMethod]
    public void ResolvesLabelsAndSwitchesCpus()
    {
        AssemblyResult result = new NativeAssembler().Assemble(
            new AssemblySource(
                """
                .cpu I8080
                Start:  LXI H,Table
                        MOV A,M
                Loop:   DCR B
                        JNZ Loop
                        CC Start
                .cpu I8085
                        RIM
                .cpu Z80
                        DJNZ Start
                Table:  .byte 1
                """,
                "i8080.asm"),
            new AssemblyOptions(I8080Isa.Name, 0x4000, 15));

        result.Diagnostics.Should().BeEmpty();
        Hex(result.Sections[0].Bytes.Span).Should().Be("21 0E 40 7E 05 C2 04 40 DC 00 40 20 10 F2 01");
    }

    /// <summary>
    ///  Every opcode of both CPUs decodes, formats in native syntax and assembles back to its own bytes, or for
    ///  an undocumented alias to the canonical encoding of its mnemonic and form.
    /// </summary>
    /// <param name="cpu">The CPU.</param>
    /// <param name="expectedAliases">How many undocumented aliases it has.</param>
    [TestMethod]
    [DataRow("I8080", 12)]
    [DataRow("I8085", 0)]
    public void EveryOpcodeRoundTrips(string cpu, int expectedAliases)
    {
        InstructionSet set = CpuCatalog.Get(cpu);
        int aliases = 0;
        for (int opcode = 0; opcode < 256; opcode++)
        {
            const ushort Address = 0x4000;
            byte[] bytes = WithOperands(set, (byte)opcode);
            Disassembler.TryDecode(bytes, Address, set, out DisassembledInstruction instruction).Should().BeTrue(Hex(bytes));
            instruction.Size.Should().Be(bytes.Length, Hex(bytes));

            string text = instruction.ToString();
            AssemblyResult result = Assemble(cpu, text, size: 3, address: Address);
            result.Diagnostics.Should().BeEmpty($"{Hex(bytes)} {text}");
            set.TryGet(instruction.Encoding.Mnemonic, instruction.Encoding.Form, out int canonical).Should().BeTrue(text);
            if (canonical == instruction.EncodingId)
            {
                Hex(result.Sections[0].Bytes.Span[..bytes.Length]).Should().Be(Hex(bytes), text);
                continue;
            }

            aliases++;
            instruction.IsUndocumented.Should().BeTrue($"{Hex(bytes)} {text} aliases a documented encoding");
            Disassembler.TryDecode(result.Sections[0].Bytes.Span, Address, set, out DisassembledInstruction canonicalInstruction)
                .Should().BeTrue(text);

            canonicalInstruction.EncodingId.Should().Be(canonical, text);
            canonicalInstruction.ToString().Should().Be(text);
        }

        aliases.Should().Be(expectedAliases);
    }

    /// <summary>
    ///  The disassembler writes Intel's operands: M, register pairs by their first register, and restart numbers.
    /// </summary>
    /// <param name="bytes">The encoding, as hex pairs.</param>
    /// <param name="text">The native text at <c>$1000</c>.</param>
    [TestMethod]
    [DataRow("7E", "MOV A,M")]
    [DataRow("36 5A", "MVI M,$5A")]
    [DataRow("21 34 12", "LXI H,$1234")]
    [DataRow("F5", "PUSH PSW")]
    [DataRow("EF", "RST 5")]
    [DataRow("C3 34 12", "JMP $1234")]
    public void FormatsNativeSyntax(string bytes, string text)
    {
        byte[] code = Convert.FromHexString(bytes.Replace(" ", "", StringComparison.Ordinal));
        Disassembler.TryDecode(code, 0x1000, I8080Isa.InstructionSet, out DisassembledInstruction instruction).Should().BeTrue();
        instruction.ToString().Should().Be(text);
    }

    /// <summary>
    ///  Flow analysis follows absolute and conditional jumps, calls and restarts, and records memory reads and
    ///  writes.
    /// </summary>
    [TestMethod]
    public void AnalysisFollowsFlow()
    {
        // $0000: JNZ $0008 / STA $0020 / RST 2 / HLT ... $0008: LDA $0021 / RET ... $0010: PCHL
        byte[] image = new byte[0x30];
        byte[] code = [0xC2, 0x08, 0x00, 0x32, 0x20, 0x00, 0xD7, 0x76];
        code.CopyTo(image, 0);
        byte[] target = [0x3A, 0x21, 0x00, 0xC9];
        target.CopyTo(image, 8);
        image[0x10] = 0xE9;

        DisassemblyResult result = Disassembler.Analyze(new AnalysisProject(image, 0, I8080Isa.InstructionSet));
        result.Diagnostics.Where(diagnostic => diagnostic.IsError).Should().BeEmpty();
        ushort[] starts = [0x0000, 0x0003, 0x0006, 0x0007, 0x0008, 0x000B, 0x0010];
        result.Instructions.Select(instruction => instruction.Address).Should().Contain(starts);
        result.References.Should().Contain(reference => reference.Target == 0x0008 && reference.Kind == DisassemblyReferenceKind.Branch);
        result.References.Should().Contain(reference => reference.Target == 0x0010 && reference.Kind == DisassemblyReferenceKind.Call);
        result.References.Should().Contain(reference => reference.Target == 0x0020 && reference.Kind == DisassemblyReferenceKind.Write);
        result.References.Should().Contain(reference => reference.Target == 0x0021 && reference.Kind == DisassemblyReferenceKind.Read);
    }

    /// <summary>
    ///  A subroutine hint ends or skips the path after an unconditional call, but not after a conditional one,
    ///  which continues when it is not taken.
    /// </summary>
    [TestMethod]
    public void HintsDoNotEndConditionalCalls()
    {
        // $0000: CNZ $0020 / MVI A,1 / CALL $0020 / MVI A,2 ... $0020: HLT
        byte[] image = new byte[0x30];
        byte[] code = [0xC4, 0x20, 0x00, 0x3E, 0x01, 0xCD, 0x20, 0x00, 0x3E, 0x02];
        code.CopyTo(image, 0);
        image[0x20] = 0x76;
        AnalysisProject project = new(image, 0, I8080Isa.InstructionSet) { FollowVectors = false };
        project.EntryPoints.Add(0x0000);
        project.Calls.Add(0x0020, AnalysisCall.NoReturn);

        DisassemblyResult result = Disassembler.Analyze(project);
        ushort[] addresses = [.. result.Instructions.Select(instruction => instruction.Address)];
        addresses.Should().Contain([0x0000, 0x0003, 0x0005, 0x0020], "CNZ falls through to MVI A,1 and the CALL");
        addresses.Should().NotContain(0x0008, "the unconditional CALL never returns");
    }

    /// <summary>
    ///  An exported disassembly, with undocumented aliases as bytes, assembles back to the same image.
    /// </summary>
    /// <param name="cpu">The CPU.</param>
    [TestMethod]
    [DataRow("I8080")]
    [DataRow("I8085")]
    public void ExportedDisassemblyReassembles(string cpu)
    {
        InstructionSet set = CpuCatalog.Get(cpu);
        byte[] image = [.. Enumerable.Range(0, 256).SelectMany(opcode => WithOperands(set, (byte)opcode))];
        DisassemblyResult result = Disassembler.Disassemble(image, 0x2000, set);
        string source = result.ExportSource();
        source.Should().StartWith($".cpu {cpu}\n");

        AssemblyResult assembled = new NativeAssembler().Assemble(new AssemblySource(source, "export.asm"), result.Options);
        assembled.Diagnostics.Should().BeEmpty();
        assembled.Sections[0].Bytes.ToArray().Should().Equal(image);
    }

    /// <summary>
    ///  An exported symbol named like a register or <c>M</c> keeps its meaning as an address.
    /// </summary>
    [TestMethod]
    public void ExportKeepsSymbolsNamedLikeRegisters()
    {
        byte[] image = [0x3A, 0x05, 0x00, 0x76, 0x00, 0x42];
        AnalysisProject project = new(image, 0, I8080Isa.InstructionSet) { FollowVectors = false };
        project.Symbols[0x0005] = "M";
        DisassemblyResult result = Disassembler.Analyze(project);
        string source = result.ExportSource();

        AssemblyResult assembled = new NativeAssembler().Assemble(new AssemblySource(source, "names.asm"), result.Options);
        assembled.Diagnostics.Should().BeEmpty(source);
        assembled.Sections[0].Bytes.ToArray().Should().Equal(image);
    }

    // The opcode with sample operand bytes for the encoding it decodes to.
    private static byte[] WithOperands(InstructionSet set, byte opcode)
    {
        byte[] padded = [opcode, 0x34, 0x12];
        return set.TryDecode(padded, out int encoding) ? padded[..set.Size(encoding)] : [opcode];
    }

    private static AssemblyResult Assemble(string cpu, string source, int size = 4, ushort address = 0x1000) =>
        new NativeAssembler().Assemble(
            new AssemblySource($".cpu {cpu}\n{source}\n", "i8080.asm"),
            new AssemblyOptions(cpu, address, size));

    private static string Hex(ReadOnlySpan<byte> bytes) => string.Join(' ', bytes.ToArray().Select(value => $"{value:X2}"));
}
