// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Cpu.Z80;

namespace Retrocore.Tests;

/// <summary>
///  The Z80 core's interrupts, HALT, WAIT, reset and snapshots, which the per-opcode references do not cover.
/// </summary>
[TestClass]
public class Z80CoreTests
{
    /// <summary>
    ///  Mode 1 restarts at <c>$38</c> in 13 T-states, after the instruction that follows EI.
    /// </summary>
    [TestMethod]
    public void ModeOneInterruptWaitsForTheInstructionAfterEnable()
    {
        // IM 1 / EI / NOP / NOP
        Z80Processor<Z80TestBus> cpu = Create(0xED, 0x56, 0xFB, 0x00, 0x00);
        cpu.StepInstruction();
        cpu.Signals = Z80Signals.InterruptRequest;
        cpu.StepInstruction().Cycles.Should().Be(4, "EI");
        cpu.StepInstruction().Cycles.Should().Be(4, "the NOP after EI runs before the interrupt");
        cpu.Registers.PC.Should().Be(0x0004);

        ProcessorExecutionResult interrupt = cpu.StepInstruction();
        interrupt.Cycles.Should().Be(13);
        cpu.Registers.PC.Should().Be(0x0038);
        cpu.Registers.Iff1.Should().BeFalse();
        cpu.Registers.Iff2.Should().BeFalse();
        cpu.Registers.SP.Should().Be(0xFFFD);
        cpu.Bus.Memory[0xFFFD].Should().Be(0x04);
        cpu.Bus.Memory[0xFFFE].Should().Be(0x00);
    }

    /// <summary>
    ///  Mode 2 jumps through the vector at I and the device's byte, in 19 T-states.
    /// </summary>
    [TestMethod]
    public void ModeTwoReadsTheVector()
    {
        // LD A,$80 / LD I,A / IM 2 / EI / NOP
        Z80Processor<Z80TestBus> cpu = Create(0x3E, 0x80, 0xED, 0x47, 0xED, 0x5E, 0xFB, 0x00);
        cpu.Bus.Memory[0x8010] = 0x34;
        cpu.Bus.Memory[0x8011] = 0x12;
        for (int index = 0; index < 5; index++) { cpu.StepInstruction(); }
        cpu.InterruptData = 0x10;
        cpu.Signals = Z80Signals.InterruptRequest;
        List<ProcessorCycle> cycles = Cycles(cpu);
        cycles.Should().HaveCount(19);
        cycles.Should().ContainSingle(cycle => cycle.Operation == BusOperation.InterruptAcknowledge);
        cpu.Registers.PC.Should().Be(0x1234);
        cpu.Registers.WZ.Should().Be(0x1234);
    }

    /// <summary>
    ///  Mode 0 executes the byte the device supplies, normally an RST, in 13 T-states.
    /// </summary>
    [TestMethod]
    public void ModeZeroExecutesTheDeviceOpcode()
    {
        // EI / NOP
        Z80Processor<Z80TestBus> cpu = Create(0xFB, 0x00);
        cpu.StepInstruction();
        cpu.StepInstruction();
        cpu.InterruptData = 0xEF;
        cpu.Signals = Z80Signals.InterruptRequest;
        Cycles(cpu).Should().HaveCount(13);
        cpu.Registers.PC.Should().Be(0x0028);
        cpu.Bus.Memory[0xFFFD].Should().Be(0x02);
    }

    /// <summary>
    ///  NMI is taken once per edge, in 11 T-states, keeping IFF1 in IFF2 for RETN.
    /// </summary>
    [TestMethod]
    public void NonMaskableInterruptKeepsTheEnableForRetn()
    {
        // EI / NOP / NOP, and RETN at $66. EI does not hold off an NMI.
        Z80Processor<Z80TestBus> cpu = Create(0xFB, 0x00, 0x00);
        cpu.Bus.Memory[0x0066] = 0xED;
        cpu.Bus.Memory[0x0067] = 0x45;
        cpu.StepInstruction();
        cpu.Signals = Z80Signals.NonMaskableInterrupt;
        Cycles(cpu).Should().HaveCount(11);
        cpu.Registers.PC.Should().Be(0x0066);
        cpu.Registers.Iff1.Should().BeFalse();
        cpu.Registers.Iff2.Should().BeTrue();

        cpu.StepInstruction().Cycles.Should().Be(14, "RETN, while NMI is still held");
        cpu.Registers.PC.Should().Be(0x0001);
        cpu.Registers.Iff1.Should().BeTrue();
        cpu.StepInstruction();
        cpu.Registers.PC.Should().Be(0x0002, "a held NMI is not taken again");
    }

    /// <summary>
    ///  HALT refreshes at the next address without running it, until an interrupt returns past it.
    /// </summary>
    [TestMethod]
    public void HaltWaitsForAnInterrupt()
    {
        // IM 1 / EI / HALT / NOP
        Z80Processor<Z80TestBus> cpu = Create(0xED, 0x56, 0xFB, 0x76, 0x00);
        for (int index = 0; index < 3; index++) { cpu.StepInstruction(); }
        cpu.IsHalted.Should().BeTrue();
        cpu.Status.Should().Be(ProcessorExecutionStatus.Waiting);
        cpu.StepInstruction().Status.Should().Be(ProcessorExecutionStatus.Waiting);

        byte refresh = cpu.Registers.R;
        List<ProcessorCycle> halted = [cpu.NextCycle(), cpu.NextCycle(), cpu.NextCycle(), cpu.NextCycle()];
        halted[1].Operation.Should().Be(BusOperation.Read);
        halted[1].Address.Should().Be(0x0004);
        cpu.Registers.PC.Should().Be(0x0004);
        cpu.Registers.R.Should().Be((byte)(refresh + 1));

        cpu.Signals = Z80Signals.InterruptRequest;
        cpu.StepInstruction().Cycles.Should().Be(13);
        cpu.IsHalted.Should().BeFalse();
        cpu.Registers.PC.Should().Be(0x0038);
        cpu.Bus.Memory[0xFFFD].Should().Be(0x04, "the interrupt returns after the HALT");
    }

    /// <summary>
    ///  An interrupt right after LD A,I clears the parity flag it copied from IFF2.
    /// </summary>
    [TestMethod]
    public void InterruptAfterLoadInterruptClearsParity()
    {
        // IM 1 / EI / NOP / LD A,I
        Z80Processor<Z80TestBus> cpu = Create(0xED, 0x56, 0xFB, 0x00, 0xED, 0x57);
        for (int index = 0; index < 4; index++) { cpu.StepInstruction(); }
        (cpu.Registers.F & 0x04).Should().NotBe(0, "IFF2 is set");
        cpu.Signals = Z80Signals.InterruptRequest;
        cpu.StepInstruction();
        cpu.Registers.PC.Should().Be(0x0038);
        (cpu.Registers.F & 0x04).Should().Be(0);
    }

    /// <summary>
    ///  WAIT holds a memory access for as long as it is asserted.
    /// </summary>
    [TestMethod]
    public void WaitStretchesAnAccess()
    {
        // LD A,[$1234]
        Z80Processor<Z80TestBus> cpu = Create(0x3A, 0x34, 0x12);
        cpu.Bus.Memory[0x1234] = 0x5A;
        List<ProcessorCycle> cycles = [];
        for (int index = 0; index < 4; index++) { cycles.Add(cpu.NextCycle()); }
        cpu.Signals = Z80Signals.Wait;
        cycles.Add(cpu.NextCycle());
        cycles.Add(cpu.NextCycle());
        cycles[^1].IsStalled.Should().BeTrue("the operand read waits");
        cpu.Signals = Z80Signals.None;
        while (!cpu.IsInstructionBoundary) { cycles.Add(cpu.NextCycle()); }
        cycles.Should().HaveCount(14, "13 T-states and one wait state");
        cpu.Registers.A.Should().Be(0x5A);
    }

    /// <summary>
    ///  A snapshot taken inside an instruction resumes to the same bus activity and result.
    /// </summary>
    [TestMethod]
    public void SnapshotsResumeInsideAnInstruction()
    {
        // LD IX,$2000 / LD [IX+5],$77 / INC [IX+5]
        Z80Processor<Z80TestBus> cpu = Create(0xDD, 0x21, 0x00, 0x20, 0xDD, 0x36, 0x05, 0x77, 0xDD, 0x34, 0x05);
        cpu.StepInstruction();
        for (int index = 0; index < 9; index++) { cpu.StepCycle(); }
        Z80Snapshot middle = cpu.CaptureState();
        List<ProcessorCycle> first = [.. Enumerable.Range(0, 33).Select(_ => cpu.NextCycle())];
        cpu.Bus.Memory[0x2005] = 0;
        cpu.RestoreState(middle);
        List<ProcessorCycle> second = [.. Enumerable.Range(0, 33).Select(_ => cpu.NextCycle())];
        second.Should().Equal(first);
        cpu.Bus.Memory[0x2005].Should().Be(0x78);
        cpu.IsInstructionBoundary.Should().BeTrue();
    }

    /// <summary>
    ///  RESET clears PC, the interrupt state and I and R, and sets AF and SP.
    /// </summary>
    [TestMethod]
    public void ResetRestartsAtZero()
    {
        Z80Processor<Z80TestBus> cpu = Create(0x3E, 0x01, 0xFB);
        cpu.StepInstruction();
        cpu.StepInstruction();
        cpu.Signals = Z80Signals.Reset;
        cpu.StepCycle();
        cpu.Registers.Iff1.Should().BeFalse();
        cpu.Registers.AF.Should().Be(0xFFFF);
        cpu.Registers.SP.Should().Be(0xFFFF);
        cpu.Registers.PC.Should().Be(0x0000, "the first fetch after reset reads on its second T-state");
    }

    /// <summary>
    ///  A halted processor's <c>Run</c> spends exactly its budget, refetching the HALT every 4 T-states.
    /// </summary>
    [TestMethod]
    public void RunSpendsTheBudgetWhileHalted()
    {
        Z80Processor<Z80TestBus> cpu = Create(0x76);
        cpu.Run(4).Cycles.Should().Be(4);
        cpu.IsHalted.Should().BeTrue();

        ProcessorExecutionResult result = cpu.Run(10);
        result.Status.Should().Be(ProcessorExecutionStatus.Waiting);
        cpu.CycleCount.Should().Be(14);
        cpu.Registers.PC.Should().Be(1);
    }

    /// <summary>
    ///  The debugger reads and writes registers by their ISA names.
    /// </summary>
    [TestMethod]
    public void DebugViewNamesRegisters()
    {
        ICpuDebugView view = Create(0x00);
        view.TrySetRegister("HL", 0x1234).Should().BeTrue();
        view.TrySetRegister("AF'", 0xBEEF).Should().BeTrue();
        view.TryGetRegister("h", out int high).Should().BeTrue();
        high.Should().Be(0x12);
        view.TryGetRegister("AF'", out int alternate).Should().BeTrue();
        alternate.Should().Be(0xBEEF);
        view.TryGetRegister("X", out _).Should().BeFalse();
        view.InstructionSet.Name.Should().Be("Z80");
        Action wide = () => view.TrySetRegister("A", 0x100);
        wide.Should().Throw<ArgumentOutOfRangeException>();
    }

    private static Z80Processor<Z80TestBus> Create(params byte[] program)
    {
        Z80TestBus bus = new();
        program.CopyTo(bus.Memory, 0);
        return new(bus);
    }

    // Steps until the next instruction boundary.
    private static List<ProcessorCycle> Cycles(Z80Processor<Z80TestBus> cpu)
    {
        List<ProcessorCycle> cycles = [cpu.NextCycle()];
        while (!cpu.IsInstructionBoundary) { cycles.Add(cpu.NextCycle()); }
        return cycles;
    }
}
