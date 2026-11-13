// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using BenchmarkDotNet.Attributes;
using Retrocore.Cpu.M6809;

namespace Retrocore.Perf;

/// <summary>
///  Measures MC6809 clock-cycle stepping across indexed auto-increment loads, 5-bit indexed stores, stack
///  register lists, subroutine calls and conditional branches.
/// </summary>
[MemoryDiagnoser]
public class M6809Benchmarks
{
    // LDB #4 (2) / LDX #$1200 (3) / LDY #$1300 (4) / LDS #$3000 (4) = 13 cycles;
    // four iterations of LDA ,X+ (6) / ADDA 0,Y (5) / STA 2,Y (5) / EORA #$5A (2) / PSHS D,X (9) /
    // BSR Sub (7) + Sub [LEAY 1,Y (5) / LEAY -1,Y (5) / RTS (5)] (15) / PULS D,X (9) / DECB (2) / BNE (3) = 63;
    // then JMP $0200 (4).
    private const int CyclesPerLoop = 13 + (4 * 63) + 4;
    private const int CyclesPerBatch = CyclesPerLoop * 256;
    private M6809Processor<RamBus>? _cpu;

    /// <summary>
    ///  Loads the workload and verifies one complete loop.
    /// </summary>
    [GlobalSetup]
    public void Setup()
    {
        byte[] memory = new byte[0x10000];
        byte[] program =
        [
            0xC6, 0x04, 0x8E, 0x12, 0x00, 0x10, 0x8E, 0x13, 0x00, 0x10, 0xCE, 0x30, 0x00,
            0xA6, 0x80, 0xAB, 0x20, 0xA7, 0x22, 0x88, 0x5A, 0x34, 0x16, 0x8D, 0x37, 0x35, 0x16, 0x5A, 0x26, 0xEF,
            0x7E, 0x02, 0x00
        ];

        program.CopyTo(memory, 0x0200);
        // $0250: LEAY 1,Y ($31 $21) / LEAY -1,Y ($31 $3F) / RTS ($39)
        byte[] subroutine = [0x31, 0x21, 0x31, 0x3F, 0x39];
        subroutine.CopyTo(memory, 0x0250);

        _cpu = new(new RamBus(memory));
        _cpu.Registers = _cpu.Registers with { PC = 0x0200 };
        _cpu.Run(CyclesPerLoop);
        Validate();
    }

    /// <summary>
    ///  Steps whole workload loops, reported per CPU clock cycle.
    /// </summary>
    /// <returns>Accumulator A after the batch.</returns>
    [Benchmark(OperationsPerInvoke = CyclesPerBatch)]
    public byte StepCycles()
    {
        M6809Processor<RamBus> cpu = _cpu ?? throw new InvalidOperationException("Benchmark setup was not run.");
        for (int index = 0; index < CyclesPerBatch; index++)
        {
            cpu.StepCycle();
        }

        return cpu.Registers.A;
    }

    /// <summary>
    ///  Checks that the workload ends each loop at the starting boundary with expected registers.
    /// </summary>
    [GlobalCleanup]
    public void Validate()
    {
        M6809Processor<RamBus> cpu = _cpu ?? throw new InvalidOperationException("Benchmark setup was not run.");
        M6809Registers registers = cpu.Registers;
        if (!cpu.IsInstructionBoundary
            || registers.PC != 0x0200
            || registers.S != 0x3000
            || registers.B != 0
            || registers.X != 0x1204
            || registers.Y != 0x1300)
        {
            throw new InvalidOperationException("The M6809 workload did not complete a loop.");
        }
    }
}
