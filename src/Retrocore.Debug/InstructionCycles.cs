// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Isa;

namespace Retrocore.Debug;

/// <summary>
///  An instruction's nominal clock cycles, for Retrocore Memory's inspector.
/// </summary>
/// <remarks>
///  <para>
///   The Z80's, 6809's and 8080's instruction sets list their cycles. The 6502 family's describe no timing, which the
///   processor works out cycle by cycle, so the instruction is run once on a processor of its own, over memory of
///   zeros with X and Y zero, so no index crosses a page: once with the flags clear and once with them set, so a
///   branch is taken in one and not the other.
///  </para>
/// </remarks>
internal static class InstructionCycles
{
    // More than any 6502 instruction takes, BRK's 7 included.
    private const int MostCycles = 16;

    /// <summary>
    ///  Gets an instruction's cycles: when a branch is not taken, and when it is.
    /// </summary>
    /// <param name="instruction">The instruction.</param>
    /// <returns>The cycles, or null where the instruction set gives none.</returns>
    public static (int Cycles, int Taken)? Of(in DisassembledInstruction instruction)
    {
        InstructionSet set = instruction.InstructionSet;
        IsaEncoding encoding = instruction.Encoding;
        if (encoding.Cycles != 0) { return (encoding.Cycles, encoding.CyclesTaken); }
        if (!ReferenceEquals(set.Description, M6502Isa.Description)) { return null; }

        byte[] bytes = new byte[instruction.Size];
        for (int index = 0; index < bytes.Length; index++)
        {
            bytes[index] = instruction.GetByte(index);
        }

        ProcessorVariant variant = M6502Isa.VariantOf(set);
        int? clear = Run(bytes, instruction.Address, variant, StatusRegister.Unused);
        StatusRegister flags = StatusRegister.Negative | StatusRegister.Overflow | StatusRegister.Zero | StatusRegister.Carry;
        int? flagged = Run(bytes, instruction.Address, variant, flags);
        if (clear is not { } first || flagged is not { } second) { return null; }
        return (Math.Min(first, second), Math.Max(first, second));
    }

    // Runs the instruction once at its address, giving its cycles, or null where it does not finish, as STP does not.
    private static int? Run(byte[] bytes, ushort address, ProcessorVariant variant, StatusRegister status)
    {
        FlatBus bus = new(new byte[0x10000]);
        for (int index = 0; index < bytes.Length; index++)
        {
            bus.Memory[(ushort)(address + index)] = bytes[index];
        }

        Processor<FlatBus> processor = new(bus, variant);
        ProcessorRegisters registers = processor.Registers;
        registers.ProgramCounter = address;
        registers.Status = status | StatusRegister.IRQBDisable;
        processor.Registers = registers;
        ProcessorExecutionResult result = processor.StepInstruction(MostCycles);
        return result.Status == ProcessorExecutionStatus.InstructionComplete ? (int)result.Cycles : null;
    }
}
