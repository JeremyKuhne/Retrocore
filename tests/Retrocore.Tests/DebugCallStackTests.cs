// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug;
using Retrocore.Machines.Apple2;

namespace Retrocore.Tests;

/// <summary>
///  Verifies observed caller frames survive nested calls, stack data, interrupts, and wrapping.
/// </summary>
[TestClass]
public class DebugCallStackTests
{
    /// <summary>
    ///  Verifies nested caller snapshots are pushed on JSR and removed on RTS, not on data pushes.
    /// </summary>
    [TestMethod]
    public void NestedCallsRetainCallerRegistersAndUnwindOnReturn()
    {
        Apple2Machine machine = Create();
        Load(machine, address: 0x2000, [0x20,0x00,0x21,0xEA]);
        Load(machine, address: 0x2100, [0x48,0x20,0x00,0x22,0x68,0x60]);
        Load(machine, address: 0x2200, [0xE8,0x60]);
        DebugCallStack stack = new(machine.Bus);
        Advance(machine, stack);
        stack.Frames(M6502Frames.Of(machine.Processor.Registers)).Select(frame => frame.ProgramCounter)
            .Should().Equal((ushort)0x2100, (ushort)0x2000);

        Advance(machine, stack);
        Advance(machine, stack);
        stack.Frames(M6502Frames.Of(machine.Processor.Registers)).Select(frame => frame.ProgramCounter)
            .Should().Equal((ushort)0x2200, (ushort)0x2101, (ushort)0x2000);

        Advance(machine, stack);
        DebugFrame[] frames = stack.Frames(M6502Frames.Of(machine.Processor.Registers));
        DebugRegisters registers = new(M6502Isa.Description);
        registers.Value(frames[0], "X").Should().Be(1);
        registers.Value(frames[1], "X").Should().Be(0);
        stack.ReturnTarget().Should().Be(((ushort)0x2104, 0xFA));
        Advance(machine, stack);
        stack.Frames(M6502Frames.Of(machine.Processor.Registers)).Should().HaveCount(2);
        Advance(machine, stack);
        Advance(machine, stack);
        stack.Frames(M6502Frames.Of(machine.Processor.Registers)).Should().ContainSingle();
        machine.Processor.Registers.ProgramCounter.Should().Be(0x2003);
    }

    /// <summary>
    ///  Verifies recursion retains duplicate call sites and full stack rollover bounds physical frames.
    /// </summary>
    [TestMethod]
    public void RecursiveCallsWrapWithoutGuessingAdditionalFrames()
    {
        Apple2Machine machine = Create();
        Load(machine, address: 0x2000, [0x20,0x00,0x20]);
        DebugCallStack stack = new(machine.Bus);
        for (int i = 0; i < 130; i++) { Advance(machine, stack); }
        DebugFrame[] frames = stack.Frames(M6502Frames.Of(machine.Processor.Registers));
        frames.Should().HaveCount(129);
        frames.Should().OnlyContain(frame => frame.ProgramCounter == 0x2000);
        stack.Reset();
        stack.Frames(M6502Frames.Of(machine.Processor.Registers)).Should().ContainSingle();
    }

    /// <summary>
    ///  Verifies IRQ frames coexist with interrupted subroutines and calls made inside the handler.
    /// </summary>
    [TestMethod]
    public void InterruptAndHandlerCallsUnwindIndependently()
    {
        Apple2Machine machine = Create();
        Load(machine, address: 0x2000, [0x20,0x00,0x21]);
        Load(machine, address: 0x2100, [0xEA,0xEA,0x60]);
        Load(machine, address: 0x3000, [0x20,0x00,0x31,0x40]);
        Load(machine, address: 0x3100, [0xE8,0x60]);
        DebugCallStack stack = new(machine.Bus);
        Advance(machine, stack);
        machine.Processor.Signals = ProcessorSignals.InterruptRequest;
        Advance(machine, stack);
        Advance(machine, stack);
        stack.Frames(M6502Frames.Of(machine.Processor.Registers)).Select(frame => frame.ProgramCounter)
            .Should().Equal((ushort)0x3100, (ushort)0x3000, (ushort)0x2101, (ushort)0x2000);

        Advance(machine, stack);
        Advance(machine, stack);
        machine.Processor.Signals = ProcessorSignals.None;
        Advance(machine, stack);
        stack.Frames(M6502Frames.Of(machine.Processor.Registers)).Select(frame => frame.ProgramCounter)
            .Should().Equal((ushort)0x2101, (ushort)0x2000);
    }

    /// <summary>
    ///  Verifies stale frames are removed when their return bytes are overwritten.
    /// </summary>
    [TestMethod]
    public void CorruptedReturnAddressDoesNotProduceAnInventedCaller()
    {
        Apple2Machine machine = Create();
        Load(machine, address: 0x2000, [0x20,0x00,0x21]);
        DebugCallStack stack = new(machine.Bus);
        Advance(machine, stack);
        machine.Bus.SetRam(auxiliary: false, address: 0x1FC, value: 0);
        stack.Frames(M6502Frames.Of(machine.Processor.Registers)).Should().ContainSingle();
    }

    /// <summary>
    ///  Verifies RDY stalls do not push duplicate caller frames.
    /// </summary>
    [TestMethod]
    public void StalledJsrRetainsExactlyOneCaller()
    {
        Apple2Machine machine = Create();
        Load(machine, address: 0x2000, [0x20,0x00,0x21]);
        DebugCallStack stack = new(machine.Bus);
        Cycle(machine, stack);
        machine.Processor.Signals = ProcessorSignals.ReadyStall;
        for (int i = 0; i < 4; i++) { Cycle(machine, stack); }
        stack.Frames(M6502Frames.Of(machine.Processor.Registers)).Should().ContainSingle();
        machine.Processor.Signals = ProcessorSignals.None;
        Advance(machine, stack);
        stack.Frames(M6502Frames.Of(machine.Processor.Registers)).Should().HaveCount(2);
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

    private static ProcessorCycle Cycle(Apple2Machine machine, DebugCallStack stack)
    {
        ProcessorRegisters before = machine.Processor.Registers;
        bool wasBoundary = machine.Processor.IsInstructionBoundary;
        ProcessorCycle cycle = machine.NextCycle();
        stack.Observe(cycle, before, machine.Processor.Registers, wasBoundary, machine.Processor.IsInstructionBoundary);
        return cycle;
    }

    private static void Advance(Apple2Machine machine, DebugCallStack stack)
    {
        bool instruction = machine.Processor.CurrentOpCode is not null;
        for (int i = 0; i < 32; i++)
        {
            ProcessorCycle cycle = Cycle(machine, stack);
            instruction |= cycle.IsOpcodeFetch && !cycle.IsStalled;
            if (instruction && machine.Processor.IsInstructionBoundary) { return; }
        }

        throw new InvalidOperationException("Test instruction did not complete.");
    }
}
