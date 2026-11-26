// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Cpu.I8080;
using Retrocore.Cpu.M6809;
using Retrocore.Cpu.Z80;
using Retrocore.Debug.Language;
using Retrocore.Isa;

namespace Retrocore.Tests;

/// <summary>
///  Checks the flags Retrocore Memory's inspector says one decoded instruction changes, where its mnemonic's depend
///  on its operands.
/// </summary>
[TestClass]
public sealed class InstructionFlagsTests
{
    /// <summary>
    ///  The Z80's register pairs, I and R, AF and port reads.
    /// </summary>
    [TestMethod]
    public void Z80()
    {
        FlagsOf([0x09], Z80Isa.InstructionSet).Should().Be("H N C");
        FlagsOf([0x80], Z80Isa.InstructionSet).Should().Be("all", "ADD A,B changes every documented flag");
        FlagsOf([0x23], Z80Isa.InstructionSet).Should().Be("none");
        FlagsOf([0x34], Z80Isa.InstructionSet).Should().Be("S Z H PV N");
        FlagsOf([0xED, 0x57], Z80Isa.InstructionSet).Should().Be("S Z H PV N");
        FlagsOf([0x78], Z80Isa.InstructionSet).Should().Be("none");
        FlagsOf([0xF1], Z80Isa.InstructionSet).Should().Be("all");
        FlagsOf([0xDB, 0x10], Z80Isa.InstructionSet).Should().Be("none");
    }

    /// <summary>
    ///  The 6502's immediate BIT and BRK on each CPU.
    /// </summary>
    [TestMethod]
    public void M6502()
    {
        FlagsOf([0x89, 0x80], M6502Isa.Get(ProcessorVariant.Wdc65C02)).Should().Be("Z");
        FlagsOf([0x2C, 0x00, 0xC0], M6502Isa.Get(ProcessorVariant.Wdc65C02)).Should().Be("N V Z");
        FlagsOf([0x00, 0x00], M6502Isa.Get(ProcessorVariant.Mos6502)).Should().Be("I");
        FlagsOf([0x00, 0x00], M6502Isa.Get(ProcessorVariant.Wdc65C02)).Should().Be("D I");
        FlagsOf([0x28], M6502Isa.Get(ProcessorVariant.Mos6502)).Should().Be("all");
        FlagsOf([0x0B, 0x00], M6502Isa.Get(ProcessorVariant.Mos6502)).Should().Be("N Z C", "undocumented ANC has effects too");
    }

    /// <summary>
    ///  The hover's flags for each documented 6502 family mnemonic, which come from the description's effects
    ///  lines, change the flags the hover listed by hand before; B, only a bit of the byte BRK and PHP push, is
    ///  no flag, and the 65C02's BRK also clears D.
    /// </summary>
    [TestMethod]
    public void M6502HoverFlagsComeFromTheEffects()
    {
        (string Mnemonic, string Flags)[] expected =
        [
            ("ADC", "N V Z C"), ("AND", "N Z"), ("ASL", "N Z C"), ("BBR0", "none"), ("BBS7", "none"),
            ("BCC", "none"), ("BCS", "none"), ("BEQ", "none"), ("BIT", "N V Z"), ("BMI", "none"), ("BNE", "none"),
            ("BPL", "none"), ("BRA", "none"), ("BRK", "D I"), ("BVC", "none"), ("BVS", "none"), ("CLC", "C"),
            ("CLD", "D"), ("CLI", "I"), ("CLV", "V"), ("CMP", "N Z C"), ("CPX", "N Z C"), ("CPY", "N Z C"),
            ("DEC", "N Z"), ("DEX", "N Z"), ("DEY", "N Z"), ("EOR", "N Z"), ("INC", "N Z"), ("INX", "N Z"),
            ("INY", "N Z"), ("JMP", "none"), ("JSR", "none"), ("LDA", "N Z"), ("LDX", "N Z"), ("LDY", "N Z"),
            ("LSR", "N Z C"), ("NOP", "none"), ("ORA", "N Z"), ("PHA", "none"), ("PHP", "none"), ("PHX", "none"),
            ("PHY", "none"), ("PLA", "N Z"), ("PLP", "all"), ("PLX", "N Z"), ("PLY", "N Z"), ("RMB2", "none"),
            ("ROL", "N Z C"), ("ROR", "N Z C"), ("RTI", "all"), ("RTS", "none"), ("SBC", "N V Z C"), ("SEC", "C"),
            ("SED", "D"), ("SEI", "I"), ("SMB5", "none"), ("STA", "none"), ("STP", "none"), ("STX", "none"),
            ("STY", "none"), ("STZ", "none"), ("TAX", "N Z"), ("TAY", "N Z"), ("TRB", "Z"), ("TSB", "Z"),
            ("TSX", "N Z"), ("TXA", "N Z"), ("TXS", "none"), ("TYA", "N Z"), ("WAI", "none")
        ];

        InstructionSet set = M6502Isa.Get(ProcessorVariant.Rockwell65C02);
        foreach ((string mnemonic, string flags) in expected)
        {
            string generated = InstructionDocs.Brief(mnemonic, set)?.Flags ?? "";
            Letters(generated, set).Should().BeEquivalentTo(Letters(flags, set), mnemonic);
            InstructionDocs.Describe(mnemonic, ProcessorVariant.Rockwell65C02).Should().Contain($"Flags: {generated}\n", mnemonic);
        }

        // BIT # changes only Z, so the 65C02's BIT varies by operand; the NMOS 6502 has no BIT #.
        InstructionDocs.Brief("BIT", set)?.Flags.Should().Be("Z or N V Z, by operands");
        InstructionDocs.Brief("BIT", M6502Isa.Get(ProcessorVariant.Mos6502))?.Flags.Should().Be("N V Z");
        InstructionDocs.Brief("LDA", set)?.Flags.Should().Be("N Z");
        InstructionDocs.Brief("BRK", M6502Isa.Get(ProcessorVariant.Mos6502))?.Flags.Should().Be("I");
        InstructionDocs.Describe("PHX", ProcessorVariant.Mos6502).Should().Contain("Flags: none");
    }

    /// <summary>
    ///  The Z80's, 6809's and 8080's hover flags, which come from the effects lines, change the flags the hover
    ///  listed by hand before, kept here as the expectations: as sets of letters, the union over a mnemonic's
    ///  operands, where "all", or a note naming AF or CC, means every flag.
    /// </summary>
    [TestMethod]
    public void OtherHoverFlagsComeFromTheEffects()
    {
        (string Mnemonic, string Flags)[] z80 =
        [
            ("ADC", "S Z H PV N C"), ("ADD", "S Z H PV N C (pairs: H N C)"), ("AND", "S Z H PV N C"),
            ("BIT", "S Z H PV N"), ("CALL", "none"), ("CCF", "H N C"), ("CP", "S Z H PV N C"), ("CPD", "S Z H PV N"),
            ("CPDR", "S Z H PV N"), ("CPI", "S Z H PV N"), ("CPIR", "S Z H PV N"), ("CPL", "H N"),
            ("DAA", "S Z H PV C"), ("DEC", "S Z H PV N"), ("DI", "none"), ("DJNZ", "none"), ("EI", "none"),
            ("EX", "none (AF,AF' swaps them)"), ("EXX", "none"), ("HALT", "none"), ("IM", "none"),
            ("IN", "S Z H PV N (none for IN A,[n])"), ("INC", "S Z H PV N"), ("IND", "S Z H PV N C"),
            ("INDR", "S Z H PV N C"), ("INI", "S Z H PV N C"), ("INIR", "S Z H PV N C"), ("JP", "none"),
            ("JR", "none"), ("LD", "none (LD A,I/R: S Z H PV N)"), ("LDD", "H PV N"), ("LDDR", "H PV N"),
            ("LDI", "H PV N"), ("LDIR", "H PV N"), ("NEG", "S Z H PV N C"), ("NOP", "none"), ("OR", "S Z H PV N C"),
            ("OTDR", "S Z H PV N C"), ("OTIR", "S Z H PV N C"), ("OUT", "none"), ("OUTD", "S Z H PV N C"),
            ("OUTI", "S Z H PV N C"), ("POP", "none (POP AF: all)"), ("PUSH", "none"), ("RES", "none"),
            ("RET", "none"), ("RETI", "none"), ("RETN", "none"), ("RL", "S Z H PV N C"), ("RLA", "H N C"),
            ("RLC", "S Z H PV N C"), ("RLCA", "H N C"), ("RLD", "S Z H PV N"), ("RR", "S Z H PV N C"),
            ("RRA", "H N C"), ("RRC", "S Z H PV N C"), ("RRCA", "H N C"), ("RRD", "S Z H PV N"), ("RST", "none"),
            ("SBC", "S Z H PV N C"), ("SCF", "H N C"), ("SET", "none"), ("SLA", "S Z H PV N C"),
            ("SLL", "S Z H PV N C"), ("SRA", "S Z H PV N C"), ("SRL", "S Z H PV N C"), ("SUB", "S Z H PV N C"),
            ("XOR", "S Z H PV N C")
        ];

        (string Mnemonic, string Flags)[] m6809 =
        [
            ("ABX", "none"), ("ADCA", "H N Z V C"), ("ADCB", "H N Z V C"), ("ADDA", "H N Z V C"),
            ("ADDB", "H N Z V C"), ("ADDD", "N Z V C"), ("ANDA", "N Z V"), ("ANDB", "N Z V"), ("ANDCC", "all"),
            ("ASL", "N Z V C"), ("ASLA", "N Z V C"), ("ASLB", "N Z V C"), ("ASR", "N Z C"), ("ASRA", "N Z C"),
            ("ASRB", "N Z C"), ("BCC", "none"), ("BCS", "none"), ("BEQ", "none"), ("BGE", "none"), ("BGT", "none"),
            ("BHI", "none"), ("BHS", "none"), ("BITA", "N Z V"), ("BITB", "N Z V"), ("BLE", "none"), ("BLO", "none"),
            ("BLS", "none"), ("BLT", "none"), ("BMI", "none"), ("BNE", "none"), ("BPL", "none"), ("BRA", "none"),
            ("BRN", "none"), ("BSR", "none"), ("BVC", "none"), ("BVS", "none"), ("CLR", "N Z V C"),
            ("CLRA", "N Z V C"), ("CLRB", "N Z V C"), ("CMPA", "N Z V C"), ("CMPB", "N Z V C"), ("CMPD", "N Z V C"),
            ("CMPS", "N Z V C"), ("CMPU", "N Z V C"), ("CMPX", "N Z V C"), ("CMPY", "N Z V C"), ("COM", "N Z V C"),
            ("COMA", "N Z V C"), ("COMB", "N Z V C"), ("CWAI", "all"), ("DAA", "N Z V C"), ("DEC", "N Z V"),
            ("DECA", "N Z V"), ("DECB", "N Z V"), ("EORA", "N Z V"), ("EORB", "N Z V"),
            ("EXG", "none (CC when named)"), ("INC", "N Z V"), ("INCA", "N Z V"), ("INCB", "N Z V"), ("JMP", "none"),
            ("JSR", "none"), ("LBCC", "none"), ("LBCS", "none"), ("LBEQ", "none"), ("LBGE", "none"),
            ("LBGT", "none"), ("LBHI", "none"), ("LBHS", "none"), ("LBLE", "none"), ("LBLO", "none"),
            ("LBLS", "none"), ("LBLT", "none"), ("LBMI", "none"), ("LBNE", "none"), ("LBPL", "none"),
            ("LBRA", "none"), ("LBRN", "none"), ("LBSR", "none"), ("LBVC", "none"), ("LBVS", "none"),
            ("LDA", "N Z V"), ("LDB", "N Z V"), ("LDD", "N Z V"), ("LDS", "N Z V"), ("LDU", "N Z V"),
            ("LDX", "N Z V"), ("LDY", "N Z V"), ("LEAS", "none"), ("LEAU", "none"), ("LEAX", "Z"), ("LEAY", "Z"),
            ("LSL", "N Z V C"), ("LSLA", "N Z V C"), ("LSLB", "N Z V C"), ("LSR", "N Z C"), ("LSRA", "N Z C"),
            ("LSRB", "N Z C"), ("MUL", "Z C"), ("NEG", "N Z V C"), ("NEGA", "N Z V C"), ("NEGB", "N Z V C"),
            ("NOP", "none"), ("ORA", "N Z V"), ("ORB", "N Z V"), ("ORCC", "all"), ("PSHS", "none"), ("PSHU", "none"),
            ("PULS", "none (CC when pulled)"), ("PULU", "none (CC when pulled)"), ("ROL", "N Z V C"),
            ("ROLA", "N Z V C"), ("ROLB", "N Z V C"), ("ROR", "N Z C"), ("RORA", "N Z C"), ("RORB", "N Z C"),
            ("RTI", "all"), ("RTS", "none"), ("SBCA", "N Z V C"), ("SBCB", "N Z V C"), ("SEX", "N Z"),
            ("STA", "N Z V"), ("STB", "N Z V"), ("STD", "N Z V"), ("STS", "N Z V"), ("STU", "N Z V"),
            ("STX", "N Z V"), ("STY", "N Z V"), ("SUBA", "N Z V C"), ("SUBB", "N Z V C"), ("SUBD", "N Z V C"),
            ("SWI", "E F I"), ("SWI2", "E"), ("SWI3", "E"), ("SYNC", "none"), ("TFR", "none (CC when destination)"),
            ("TST", "N Z V"), ("TSTA", "N Z V"), ("TSTB", "N Z V"), ("X18", "all"), ("XADDD", "N Z V C"),
            ("XADDU", "N Z V C"), ("XANDCC", "all"), ("XCLRA", "N Z V"), ("XCLRB", "N Z V"), ("XDEC", "N Z V C"),
            ("XDECA", "N Z V C"), ("XDECB", "N Z V C"), ("XFIRQ", "none"), ("XHCF", "none"), ("XNC", "N Z V C"),
            ("XNCA", "N Z V C"), ("XNCB", "N Z V C"), ("XRES", "none"), ("XSTA", "N Z V"), ("XSTB", "N Z V"),
            ("XSTS", "N Z V"), ("XSTU", "N Z V"), ("XSTX", "N Z V"), ("XSTY", "N Z V"), ("XSWI2", "none")
        ];

        (string Mnemonic, string Flags)[] i8080 =
        [
            ("ACI", "S Z AC P CY"), ("ADC", "S Z AC P CY"), ("ADD", "S Z AC P CY"), ("ADI", "S Z AC P CY"),
            ("ANA", "S Z AC P CY"), ("ANI", "S Z AC P CY"), ("ARHL", "CY"), ("CALL", "none"), ("CC", "none"),
            ("CM", "none"), ("CMA", "none"), ("CMC", "CY"), ("CMP", "S Z AC P CY"), ("CNC", "none"), ("CNZ", "none"),
            ("CP", "none"), ("CPE", "none"), ("CPI", "S Z AC P CY"), ("CPO", "none"), ("CZ", "none"),
            ("DAA", "S Z AC P CY"), ("DAD", "CY"), ("DCR", "S Z AC P"), ("DCX", "none"), ("DI", "none"),
            ("DSUB", "S Z AC P CY"), ("EI", "none"), ("HLT", "none"), ("IN", "none"), ("INR", "S Z AC P"),
            ("INX", "none"), ("JC", "none"), ("JK", "none"), ("JM", "none"), ("JMP", "none"), ("JNC", "none"),
            ("JNK", "none"), ("JNZ", "none"), ("JP", "none"), ("JPE", "none"), ("JPO", "none"), ("JZ", "none"),
            ("LDA", "none"), ("LDAX", "none"), ("LDHI", "none"), ("LDSI", "none"), ("LHLD", "none"),
            ("LHLX", "none"), ("LXI", "none"), ("MOV", "none"), ("MVI", "none"), ("NOP", "none"),
            ("ORA", "S Z AC P CY"), ("ORI", "S Z AC P CY"), ("OUT", "none"), ("PCHL", "none"),
            ("POP", "none (POP PSW: all)"), ("PUSH", "none"), ("RAL", "CY"), ("RAR", "CY"), ("RC", "none"),
            ("RDEL", "CY"), ("RET", "none"), ("RIM", "none"), ("RLC", "CY"), ("RM", "none"), ("RNC", "none"),
            ("RNZ", "none"), ("RP", "none"), ("RPE", "none"), ("RPO", "none"), ("RRC", "CY"), ("RST", "none"),
            ("RSTV", "none"), ("RZ", "none"), ("SBB", "S Z AC P CY"), ("SBI", "S Z AC P CY"), ("SHLD", "none"),
            ("SHLX", "none"), ("SIM", "none"), ("SPHL", "none"), ("STA", "none"), ("STAX", "none"), ("STC", "CY"),
            ("SUB", "S Z AC P CY"), ("SUI", "S Z AC P CY"), ("XCHG", "none"), ("XRA", "S Z AC P CY"),
            ("XRI", "S Z AC P CY"), ("XTHL", "none")
        ];

        Check(z80, Z80Isa.InstructionSet);
        Check(m6809, M6809Isa.InstructionSet);
        Check(i8080, I8080Isa.InstructionSet);

        static void Check((string Mnemonic, string Flags)[] expected, InstructionSet set)
        {
            foreach ((string mnemonic, string flags) in expected)
            {
                string generated = InstructionDocs.Brief(mnemonic, set)?.Flags ?? "";
                Letters(generated, set).Should().BeEquivalentTo(Letters(flags, set), $"{mnemonic}: \"{generated}\" for \"{flags}\"");
                InstructionDocs.Describe(mnemonic, set).Should().Contain($"Flags: {generated}", mnemonic);
            }
        }
    }

    /// <summary>
    ///  A hover lists each encoding's flags, and where its operands decide, the possibilities.
    /// </summary>
    [TestMethod]
    public void HoversListEachEncodingsFlags()
    {
        string add = InstructionDocs.Describe("ADD", Z80Isa.InstructionSet) ?? "";
        add.Should().Contain("Flags: H N C or all, by operands\n");
        add.Should().Contain("| `ADD HL,BC` | `09` | 11 | H N C |");
        add.Should().Contain("| `ADD A,B` | `80` | 4 | all |");
        string tfr = InstructionDocs.Describe("TFR", M6809Isa.InstructionSet) ?? "";
        tfr.Should().Contain("Flags: none or all, by operands\n").And.Contain("| none or all |");
        InstructionDocs.Describe("PULS", M6809Isa.InstructionSet).Should().Contain("| none or all |");
        InstructionDocs.Describe("LDA", ProcessorVariant.Mos6502).Should().Contain("| immediate `#value` | $A9 | N Z |");
        InstructionDocs.Describe("DSUB", I8080Isa.InstructionSet).Should().Contain("Flags: all", "the 8080's hover finds the 8085's instruction");
    }

    // The documented flag letters a hover's text names, every one for "all" or a note naming AF or CC.
    private static HashSet<string> Letters(string text, InstructionSet set)
    {
        HashSet<string> all = [];
        foreach (IsaFlag flag in set.Description.Flags)
        {
            if (flag.Words.Count != 0) { all.Add(flag.Name.Replace("/", "", StringComparison.Ordinal)); }
        }

        HashSet<string> letters = [];
        foreach (string word in text.Split([' ', '(', ')', ',', ';', ':'], StringSplitOptions.RemoveEmptyEntries))
        {
            if (word is "all" or "AF" or "CC") { letters.UnionWith(all); }
            else if (all.Contains(word)) { letters.Add(word); }
        }

        return letters;
    }

    /// <summary>
    ///  The 6809's transfers and pulls change CC only when they name it.
    /// </summary>
    [TestMethod]
    public void M6809()
    {
        FlagsOf([0x1F, 0x8A], M6809Isa.InstructionSet).Should().Be("all");
        FlagsOf([0x1F, 0x89], M6809Isa.InstructionSet).Should().Be("none");
        FlagsOf([0x35, 0x01], M6809Isa.InstructionSet).Should().Be("all");
        FlagsOf([0x35, 0x02], M6809Isa.InstructionSet).Should().Be("none");
    }

    private static string? FlagsOf(byte[] bytes, InstructionSet set)
    {
        Disassembler.TryDecode(bytes, 0x1000, set, out DisassembledInstruction instruction).Should().BeTrue();
        return InstructionDocs.FlagsOf(instruction);
    }
}
