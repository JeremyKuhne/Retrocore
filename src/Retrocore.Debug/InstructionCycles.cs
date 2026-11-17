// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Cpu.M6809;
using Retrocore.Isa;

namespace Retrocore.Debug;

/// <summary>
///  An instruction's nominal clock cycles, for Retrocore Memory's inspector.
/// </summary>
/// <remarks>
///  <para>
///   The Z80's and 8080's instruction sets list their cycles. The 6502 family's describe no timing, and the 6809's
///   only a base that indexed operands and register lists add to, so the instruction is run once on a processor of
///   its own, over memory of zeros with the index registers zero, so no index crosses a page: once with the flags
///   clear and once with them set (the 6809's also with N alone, for a condition that compares N with V), so a branch
///   is taken in one and not the other; for the 65C02's bit branches, BBR
///   and BBS, the byte they test is zero in one run and $FF in the other.
///  </para>
/// </remarks>
internal static class InstructionCycles
{
    // More than any instruction takes, a 6809 PSHS of every register included.
    private const int MostCycles = 64;

    // The 6809's CC: E F H I N Z V C; interrupts masked.
    private const byte M6809Masked = 0x50;

    // N, Z, V and C all clear, all set, and N alone, so every condition, LBGE's N = V included, is both true and false.
    private static readonly byte[] s_m6809Flags = [0x00, 0x0F, 0x08];

    // The 6502's flags a branch tests.
    private const StatusRegister Flags6502 =
        StatusRegister.Negative | StatusRegister.Overflow | StatusRegister.Zero | StatusRegister.Carry;

    /// <summary>
    ///  Gets an instruction's cycles: when a branch is not taken, and when it is.
    /// </summary>
    /// <param name="instruction">The instruction.</param>
    /// <returns>The cycles, or null where the instruction set gives none or the instruction does not finish.</returns>
    public static (int Cycles, int Taken)? Of(in DisassembledInstruction instruction)
    {
        InstructionSet set = instruction.InstructionSet;
        bool m6502 = ReferenceEquals(set.Description, M6502Isa.Description);
        bool m6809 = ReferenceEquals(set.Description, M6809Isa.Description);
        if (!m6502 && !m6809)
        {
            IsaEncoding encoding = instruction.Encoding;
            return encoding.Cycles == 0 ? null : (encoding.Cycles, encoding.CyclesTaken);
        }

        byte[] bytes = new byte[instruction.Size];
        for (int index = 0; index < bytes.Length; index++)
        {
            bytes[index] = instruction.GetByte(index);
        }

        int? first;
        int? second;
        if (m6809)
        {
            // RTI pulls every register or only CC and PC as the stacked CC's E flag says, which the instruction
            // does not show.
            if (string.Equals(instruction.Mnemonic, "RTI", StringComparison.OrdinalIgnoreCase)) { return null; }
            int? fewest = null;
            int? most = null;
            foreach (byte flags in s_m6809Flags)
            {
                if (Run6809(bytes, instruction.Address, flags) is not { } cycles) { return null; }
                fewest = Math.Min(fewest ?? cycles, cycles);
                most = Math.Max(most ?? cycles, cycles);
            }

            first = fewest;
            second = most;
        }
        else
        {
            // A bit branch's zero-page byte, unless it is one of the instruction's own.
            int? tested = null;
            if (instruction.Mnemonic.StartsWith("BB", StringComparison.OrdinalIgnoreCase) && bytes.Length == 3)
            {
                int zeroPage = bytes[1];
                if ((ushort)(zeroPage - instruction.Address) >= bytes.Length) { tested = zeroPage; }
            }

            ProcessorVariant variant = M6502Isa.VariantOf(set);
            first = Run6502(bytes, instruction.Address, variant, flags: false, tested: null);
            second = Run6502(bytes, instruction.Address, variant, flags: true, tested);
        }

        if (first is not { } clear || second is not { } flagged) { return null; }
        return (Math.Min(clear, flagged), Math.Max(clear, flagged));
    }

    // Memory of zeros holding the instruction at its address.
    private static FlatBus Holding(byte[] bytes, ushort address)
    {
        FlatBus bus = new(new byte[0x10000]);
        for (int index = 0; index < bytes.Length; index++)
        {
            bus.Memory[(ushort)(address + index)] = bytes[index];
        }

        return bus;
    }

    // Runs a 6502 instruction once, giving its cycles, or null where it does not finish, as STP does not.
    private static int? Run6502(byte[] bytes, ushort address, ProcessorVariant variant, bool flags, int? tested)
    {
        FlatBus bus = Holding(bytes, address);
        if (tested is { } zeroPage) { bus.Memory[zeroPage] = 0xFF; }
        Processor<FlatBus> processor = new(bus, variant);
        ProcessorRegisters registers = processor.Registers;
        registers.ProgramCounter = address;
        StatusRegister status = StatusRegister.Unused | StatusRegister.IRQBDisable;
        if (flags) { status |= Flags6502; }
        registers.Status = status;
        processor.Registers = registers;
        ProcessorExecutionResult result = processor.StepInstruction(MostCycles);
        return result.Status == ProcessorExecutionStatus.InstructionComplete ? (int)result.Cycles : null;
    }

    // Runs a 6809 instruction once, with its stacks well away from it, giving its cycles, or null where it does not
    // finish, as SYNC and CWAI do not.
    private static int? Run6809(byte[] bytes, ushort address, byte flags)
    {
        M6809Processor<FlatBus> processor = new(Holding(bytes, address));
        M6809Registers registers = processor.Registers;
        registers.PC = address;
        registers.CC = (byte)(M6809Masked | flags);
        registers.S = (ushort)(address + 0x8000);
        registers.U = (ushort)(address + 0xC000);
        processor.Registers = registers;
        ProcessorExecutionResult result = processor.StepInstruction(MostCycles);
        return result.Status == ProcessorExecutionStatus.InstructionComplete ? (int)result.Cycles : null;
    }
}
