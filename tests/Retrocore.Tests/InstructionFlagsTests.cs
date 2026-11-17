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
        FlagsOf([0x00, 0x00], M6502Isa.Get(ProcessorVariant.Mos6502)).Should().Be("B I");
        FlagsOf([0x00, 0x00], M6502Isa.Get(ProcessorVariant.Wdc65C02)).Should().Be("B I D");
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
