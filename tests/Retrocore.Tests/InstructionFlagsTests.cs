// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
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
        FlagsOf([0x80], Z80Isa.InstructionSet).Should().Be("S Z H PV N C");
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
    ///  lines, are those the hover listed by hand before; B, only a bit of the byte BRK and PHP push, is no
    ///  flag, and the 65C02's BRK also clears D.
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
            InstructionDocs.Brief(mnemonic, set)?.Flags.Should().Be(flags, mnemonic);
            InstructionDocs.Describe(mnemonic, ProcessorVariant.Rockwell65C02).Should().Contain($"Flags: {flags}\n", mnemonic);
        }

        InstructionDocs.Brief("BRK", M6502Isa.Get(ProcessorVariant.Mos6502))?.Flags.Should().Be("I");
        InstructionDocs.Describe("PHX", ProcessorVariant.Mos6502).Should().Contain("Flags: none");
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
