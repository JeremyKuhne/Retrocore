// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug;
using Retrocore.Machines.Apple2;

namespace Retrocore.Tests;

/// <summary>
///  Verifies JSR lines record their latest call's cycles, including nested calls, and drop calls whose stack is
///  discarded.
/// </summary>
[TestClass]
public class DebugCallCyclesTests
{
    /// <summary>
    ///  Verifies each JSR line counts its JSR, the subroutine (with any calls it makes) and the RTS.
    /// </summary>
    [TestMethod]
    public void NestedCallsIncludeTheirCallees()
    {
        Apple2Machine machine = Create();
        Load(machine, address: 0x2000, [0x20, 0x00, 0x21, 0x20, 0x00, 0x21, 0xEA]);
        Load(machine, address: 0x2100, [0x20, 0x00, 0x22, 0x60]);
        Load(machine, address: 0x2200, [0xE8, 0x60]);
        DebugCallCycles calls = Run(machine, instructions: 11);

        // Inner: JSR 6 + INX 2 + RTS 6. Outer: JSR 6 + inner 14 + RTS 6.
        calls.Last[Line(0x2100)].Should().Be(14UL);
        calls.Last[Line(0x2000)].Should().Be(26UL);
        calls.Last[Line(0x2003)].Should().Be(26UL);
    }

    /// <summary>
    ///  Verifies a call abandoned by resetting the stack is not counted and does not hide later calls.
    /// </summary>
    [TestMethod]
    public void ResetStackAbandonsTheCall()
    {
        Apple2Machine machine = Create();

        // JSR $2100; NOP, where $2100 resets the stack (LDX #$FF; TXS) and jumps back to the NOP; then JSR $2200; NOP.
        Load(machine, address: 0x2000, [0x20, 0x00, 0x21, 0xEA, 0x20, 0x00, 0x22, 0xEA]);
        Load(machine, address: 0x2100, [0xA2, 0xFF, 0x9A, 0x4C, 0x03, 0x20]);
        Load(machine, address: 0x2200, [0x60]);
        DebugCallCycles calls = Run(machine, instructions: 8);

        calls.Last.ContainsKey(Line(0x2000)).Should().BeFalse();
        calls.Last[Line(0x2004)].Should().Be(12UL);
    }

    private static (string Path, int Line) Line(ushort address) => ("test", address);

    private static DebugCallCycles Run(Apple2Machine machine, int instructions)
    {
        DebugCallCycles calls = new();
        for (int i = 0; i < instructions; i++)
        {
            ProcessorRegisters registers = machine.Processor.Registers;
            ushort pc = registers.ProgramCounter;
            int? call = machine.Bus.Peek(pc) == 0x20 ? 3 : null;
            calls.Observe(pc, call, registers.StackPointer, machine.Bus.CycleCount, Line(pc));
            machine.StepInstruction();
        }

        return calls;
    }

    private static Apple2Machine Create()
    {
        byte[] rom = new byte[16384];
        rom[0x3FFE] = 0;
        rom[0x3FFF] = 0x30;
        Apple2Machine machine = new(Apple2Model.IIe, new Apple2Roms(rom, new byte[4096]));
        machine.Run(cycles: 7);
        machine.Processor.Registers = new()
        {
            ProgramCounter = 0x2000, StackPointer = 0xFD, Status = StatusRegister.Unused
        };

        return machine;
    }

    private static void Load(Apple2Machine machine, ushort address, ReadOnlySpan<byte> bytes)
    {
        for (int i = 0; i < bytes.Length; i++)
        {
            machine.Bus.SetRam(auxiliary: false, (ushort)(address + i), bytes[i]);
        }
    }
}
