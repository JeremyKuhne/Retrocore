// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Perf;

/// <summary>
///  An original deterministic instruction mix with a fixed emulated-cycle denominator.
/// </summary>
internal static class CpuWorkload
{
    /// <summary>
    ///  Emulated cycles in one complete workload loop for all supported CPU variants.
    /// </summary>
    internal const int CyclesPerLoop = 76;

    /// <summary>
    ///  Creates a processor executing arithmetic, indexed memory, indirect loads, stack, and branches.
    /// </summary>
    /// <param name="variant">The CPU variant.</param>
    /// <param name="bus">The caller-owned RAM bus.</param>
    /// <returns>The initialized CPU.</returns>
    internal static Processor<RamBus> Create(ProcessorVariant variant, out RamBus bus)
    {
        bus = new(new byte[65536]);
        ReadOnlySpan<byte> program =
        [
            0xA2, 0x03, 0xA0, 0x05, 0xA9, 0x19, 0x85, 0x10,
            0x18, 0x65, 0x10, 0x49, 0x5A, 0x9D, 0x00, 0x12,
            0xBD, 0x00, 0x12, 0x48, 0xB1, 0x20, 0x69, 0x01,
            0x68, 0x20, 0x50, 0x02, 0xC9, 0x68, 0xD0, 0xFE,
            0xC6, 0x10, 0xE6, 0x10, 0xC8, 0x88, 0x4C, 0x00, 0x02
        ];

        program.CopyTo(bus.Memory.AsSpan(start: 0x200));
        bus.Memory[0x250] = 0xE8;
        bus.Memory[0x251] = 0xCA;
        bus.Memory[0x252] = 0x60;
        bus.Memory[0x20] = 0xF8;
        bus.Memory[0x21] = 0x12;
        bus.Memory[0x12FD] = 0x37;
        Processor<RamBus> cpu = new(bus, variant);
        ProcessorRegisters registers = cpu.Registers;
        registers.ProgramCounter = 0x200;
        cpu.Registers = registers;
        return cpu;
    }

    /// <summary>
    ///  Checks the workload's observable state outside the measured region.
    /// </summary>
    /// <param name="cpu">The processor after one or more complete loops.</param>
    /// <param name="bus">The backing memory.</param>
    internal static void Validate(Processor<RamBus> cpu, RamBus bus)
    {
        ProcessorRegisters registers = cpu.Registers;
        if (!cpu.IsInstructionBoundary
            || registers.ProgramCounter != 0x200
            || registers.Accumulator != 0x68
            || registers.X != 3
            || registers.Y != 5
            || registers.StackPointer != 0xFD
            || bus.Memory[0x10] != 0x19
            || bus.Memory[0x1203] != 0x68)
        {
            throw new InvalidOperationException(
                $"Workload failed: PC={registers.ProgramCounter:X4} A={registers.Accumulator:X2}"
                    + $" X={registers.X} Y={registers.Y} S={registers.StackPointer:X2} RAM10={bus.Memory[0x10]:X2}.");
        }
    }
}
