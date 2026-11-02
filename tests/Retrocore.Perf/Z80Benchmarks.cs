// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using BenchmarkDotNet.Attributes;
using Retrocore.Cpu.Z80;

namespace Retrocore.Perf;

/// <summary>
///  Measures Z80 T-state stepping with a mix of loads, indexed stores, arithmetic, the stack, calls and loops.
/// </summary>
[MemoryDiagnoser]
public class Z80Benchmarks
{
    // LD B,4 / LD HL,$1200 / LD IX,$1300, then four times LD A,[HL] / ADD A,B / LD [IX+2],A / XOR $5A /
    // PUSH AF / CALL sub / POP AF / INC HL / DJNZ, then JP back; sub is INC IX / DEC IX / RET.
    private const int TStatesPerLoop = 31 + (3 * 124) + 119 + 10;
    private const int TStatesPerBatch = TStatesPerLoop * 256;
    private Z80Processor<Z80RamBus>? _cpu;

    /// <summary>
    ///  Loads the workload and checks one loop.
    /// </summary>
    [GlobalSetup]
    public void Setup()
    {
        byte[] memory = new byte[0x10000];
        byte[] program =
        [
            0x06, 0x04, 0x21, 0x00, 0x12, 0xDD, 0x21, 0x00, 0x13,
            0x7E, 0x80, 0xDD, 0x77, 0x02, 0xEE, 0x5A, 0xF5, 0xCD, 0x50, 0x02, 0xF1, 0x23, 0x10, 0xF1,
            0xC3, 0x00, 0x02
        ];

        program.CopyTo(memory, 0x0200);
        byte[] subroutine = [0xDD, 0x23, 0xDD, 0x2B, 0xC9];
        subroutine.CopyTo(memory, 0x0250);
        _cpu = new(new Z80RamBus(memory));
        _cpu.Registers = _cpu.Registers with { PC = 0x0200 };
        _cpu.Run(TStatesPerLoop);
        Validate();
    }

    /// <summary>
    ///  Steps whole workload loops, reported per T-state.
    /// </summary>
    /// <returns>A value the instructions produced.</returns>
    [Benchmark(OperationsPerInvoke = TStatesPerBatch)]
    public byte StepCycles()
    {
        Z80Processor<Z80RamBus> cpu = _cpu ?? throw new InvalidOperationException("Benchmark setup was not run.");
        for (int index = 0; index < TStatesPerBatch; index++) { cpu.StepCycle(); }
        return cpu.Registers.A;
    }

    /// <summary>
    ///  Checks that the workload ends each loop where it began.
    /// </summary>
    [GlobalCleanup]
    public void Validate()
    {
        Z80Processor<Z80RamBus> cpu = _cpu ?? throw new InvalidOperationException("Benchmark setup was not run.");
        Z80Registers registers = cpu.Registers;
        if (!cpu.IsInstructionBoundary
            || registers.PC != 0x0200
            || registers.SP != 0xFFFF
            || registers.B != 0
            || registers.HL != 0x1204
            || registers.IX != 0x1300)
        {
            throw new InvalidOperationException("The Z80 workload did not complete a loop.");
        }
    }
}
