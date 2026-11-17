// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Cpu.M6809;
using Retrocore.Cpu.Z80;
using Retrocore.Debug;
using Retrocore.Isa;

namespace Retrocore.Tests;

/// <summary>
///  Checks the cycles Retrocore Memory's inspector gives an instruction: from the Z80's instruction set, and measured
///  on a processor of their own for the 6502 family and the 6809.
/// </summary>
[TestClass]
public sealed class InstructionCyclesTests
{
    /// <summary>
    ///  The 6502's cycles, a branch's when taken, and a page crossed by a taken branch.
    /// </summary>
    [TestMethod]
    public void M6502()
    {
        Of([0xAD, 0x00, 0x03], 0x0400, M6502Isa.Get(ProcessorVariant.Wdc65C02)).Should().Be((4, 4));
        Of([0xD0, 0x02], 0x0400, M6502Isa.Get(ProcessorVariant.Wdc65C02)).Should().Be((2, 3));
        Of([0xD0, 0x7F], 0x04FD, M6502Isa.Get(ProcessorVariant.Wdc65C02)).Should().Be((2, 4));
    }

    /// <summary>
    ///  The Rockwell 65C02's bit branches, which test a byte rather than the flags.
    /// </summary>
    [TestMethod]
    public void BitBranches()
    {
        InstructionSet rockwell = M6502Isa.Get(ProcessorVariant.Rockwell65C02);
        Of([0x0F, 0x10, 0x00], 0x2000, rockwell).Should().Be((5, 6));
        Of([0x8F, 0x10, 0x00], 0x2000, rockwell).Should().Be((5, 6));
    }

    /// <summary>
    ///  The 6809's indexed indirect operand and register list add to the encoding's base.
    /// </summary>
    [TestMethod]
    public void M6809()
    {
        Of([0xA6, 0x94], 0x1000, M6809Isa.InstructionSet).Should().Be((7, 7));
        Of([0x34, 0x03], 0x1000, M6809Isa.InstructionSet).Should().Be((7, 7));
    }

    /// <summary>
    ///  The Z80's T-states come from its instruction set.
    /// </summary>
    [TestMethod]
    public void Z80()
    {
        Of([0xF3], 0x0000, Z80Isa.InstructionSet).Should().Be((4, 4));
    }

    private static (int Cycles, int Taken)? Of(byte[] bytes, ushort address, InstructionSet set)
    {
        Disassembler.TryDecode(bytes, address, set, out DisassembledInstruction instruction).Should().BeTrue();
        return InstructionCycles.Of(instruction);
    }
}
