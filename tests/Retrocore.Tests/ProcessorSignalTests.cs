// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Tests;

/// <summary>
///  Directed external-input timing tests beyond the instruction-only upstream suites.
/// </summary>
[TestClass]
public class ProcessorSignalTests
{
    /// <summary>
    ///  Verifies CLI's interrupt-mask change takes effect after the following instruction.
    /// </summary>
    /// <param name="variant">The CPU variant.</param>
    [TestMethod]
    [DataRow(ProcessorVariant.Mos6502)]
    [DataRow(ProcessorVariant.Wdc65C02)]
    [DataRow(ProcessorVariant.Rockwell65C02)]
    public void CliDelaysIrqByOneInstruction(ProcessorVariant variant)
    {
        RecordingBus bus = Memory();
        bus.Memory[0x200] = 0x58;
        Processor<RecordingBus> cpu = Create(bus, variant);
        cpu.Signals = ProcessorSignals.InterruptRequest;
        cpu.StepInstruction().Cycles.Should().Be(2);
        cpu.Registers.ProgramCounter.Should().Be(0x201);
        cpu.StepInstruction().Cycles.Should().Be(2);
        cpu.Registers.ProgramCounter.Should().Be(0x202);
        cpu.Run(cycleBudget: 7);
        cpu.Registers.ProgramCounter.Should().Be(0x3000);
        bus.Memory[0x1FC].Should().Be(2);
    }

    /// <summary>
    ///  Verifies an IRQ sampled during SEI still enters despite the newly set mask.
    /// </summary>
    /// <param name="variant">The CPU variant.</param>
    [TestMethod]
    [DataRow(ProcessorVariant.Mos6502)]
    [DataRow(ProcessorVariant.Wdc65C02)]
    [DataRow(ProcessorVariant.Rockwell65C02)]
    public void SeiDoesNotCancelAlreadySampledIrq(ProcessorVariant variant)
    {
        RecordingBus bus = Memory();
        bus.Memory[0x200] = 0x78;
        Processor<RecordingBus> cpu = Create(bus, variant);
        ProcessorRegisters registers = cpu.Registers;
        registers.Status = StatusRegister.Unused;
        cpu.Registers = registers;
        cpu.StepCycle();
        cpu.Signals = ProcessorSignals.InterruptRequest;
        cpu.StepCycle();
        cpu.Registers.Status.HasFlag(StatusRegister.IRQBDisable).Should().BeTrue();
        cpu.Signals = ProcessorSignals.None;
        cpu.Run(cycleBudget: 7);
        cpu.Registers.ProgramCounter.Should().Be(0x3000);
    }

    /// <summary>
    ///  Verifies NMOS writes ignore RDY and CMOS writes hold their CPU microstate.
    /// </summary>
    /// <param name="variant">The CPU variant.</param>
    [TestMethod]
    [DataRow(ProcessorVariant.Mos6502)]
    [DataRow(ProcessorVariant.Wdc65C02)]
    [DataRow(ProcessorVariant.Rockwell65C02)]
    public void RdyWriteHandlingIsVariantSpecific(ProcessorVariant variant)
    {
        RecordingBus bus = Memory();
        bus.Memory[0x200] = 0x85;
        bus.Memory[0x201] = 0x10;
        Processor<RecordingBus> cpu = Create(bus, variant);
        ProcessorRegisters registers = cpu.Registers;
        registers.Accumulator = 0x42;
        cpu.Registers = registers;
        cpu.Run(cycleBudget: 2);
        cpu.Signals = ProcessorSignals.ReadyStall;
        ProcessorCycle write = cpu.NextCycle();
        write.Operation.Should().Be(BusOperation.Write);
        write.IsStalled.Should().Be(variant != ProcessorVariant.Mos6502);
        bus.Memory[0x10].Should().Be(0x42);
        if (variant != ProcessorVariant.Mos6502)
        {
            cpu.IsInstructionBoundary.Should().BeFalse();
            cpu.NextCycle().IsStalled.Should().BeTrue();
            cpu.Signals = ProcessorSignals.None;
            cpu.NextCycle().IsStalled.Should().BeFalse();
            cpu.CycleCount.Should().Be(5);
        }
        else
        {
            cpu.CycleCount.Should().Be(3);
        }

        cpu.IsInstructionBoundary.Should().BeTrue();
        cpu.Registers.ProgramCounter.Should().Be(0x202);
    }

    /// <summary>
    ///  Verifies RESET assertion holds vector acquisition and suppresses opcode execution until release.
    /// </summary>
    /// <param name="variant">The CPU variant.</param>
    [TestMethod]
    [DataRow(ProcessorVariant.Mos6502)]
    [DataRow(ProcessorVariant.Wdc65C02)]
    [DataRow(ProcessorVariant.Rockwell65C02)]
    public void ResetRemainsHeldUntilReleased(ProcessorVariant variant)
    {
        RecordingBus bus = Memory();
        Processor<RecordingBus> cpu = Create(bus, variant);
        cpu.Signals = ProcessorSignals.Reset;
        cpu.Run(cycleBudget: 20);
        cpu.IsInstructionBoundary.Should().BeFalse();
        cpu.Registers.ProgramCounter.Should().Be(0x200);
        cpu.Registers.StackPointer.Should().Be(0xFA);
        bus.Accesses.Should().OnlyContain(access => access.Operation == BusOperation.Read);
        bus.Accesses.Skip(5).Should().OnlyContain(access => access.Address == 0xFFFC);
        cpu.Signals = ProcessorSignals.None;
        cpu.NextCycle().Address.Should().Be(0xFFFC);
        cpu.NextCycle().Address.Should().Be(0xFFFD);
        cpu.IsInstructionBoundary.Should().BeTrue();
        cpu.Registers.ProgramCounter.Should().Be(0x4000);
        cpu.StepInstruction().Cycles.Should().Be(2);
        cpu.Registers.ProgramCounter.Should().Be(0x4001);
    }

    /// <summary>
    ///  Verifies NMI can redirect an IRQ or BRK before vector acquisition without mixing vector bytes.
    /// </summary>
    /// <param name="software">Whether the interrupted sequence is BRK.</param>
    [TestMethod]
    [DataRow(data: false)]
    [DataRow(data: true)]
    public void NmiRedirectsVectorAcquisition(bool software)
    {
        RecordingBus bus = Memory();
        bus.Memory[0x200] = software ? (byte)0x00 : (byte)0xEA;
        Processor<RecordingBus> cpu = Create(bus, ProcessorVariant.Mos6502);
        ProcessorRegisters registers = cpu.Registers;
        registers.Status = StatusRegister.Unused;
        cpu.Registers = registers;
        cpu.Signals = software ? ProcessorSignals.None : ProcessorSignals.InterruptRequest;
        cpu.Run(cycleBudget: 5);
        cpu.Signals = ProcessorSignals.NonMaskableInterrupt;
        cpu.Run(cycleBudget: 2);
        cpu.Registers.ProgramCounter.Should().Be(0x5000);
        bus.Accesses.TakeLast(2).Select(access => access.Address).Should().Equal((ushort)0xFFFA, (ushort)0xFFFB);
        ((bus.Memory[0x1FB] & 0x10) != 0).Should().Be(software);
    }

    /// <summary>
    ///  Verifies an unmasked IRQ wakes WAI into an interrupt rather than ordinary opcode execution.
    /// </summary>
    [TestMethod]
    public void UnmaskedIrqWakesWaiIntoInterrupt()
    {
        RecordingBus bus = Memory();
        bus.Memory[0x200] = 0xCB;
        Processor<RecordingBus> cpu = Create(bus, ProcessorVariant.Wdc65C02);
        ProcessorRegisters registers = cpu.Registers;
        registers.Status = StatusRegister.Unused;
        cpu.Registers = registers;
        cpu.StepInstruction().Status.Should().Be(ProcessorExecutionStatus.Waiting);
        cpu.Signals = ProcessorSignals.InterruptRequest;
        cpu.Run(cycleBudget: 7);
        cpu.Registers.ProgramCounter.Should().Be(0x3000);
        cpu.Status.Should().Be(ProcessorExecutionStatus.Running);
    }

    private static RecordingBus Memory()
    {
        RecordingBus bus = new();
        Array.Fill(bus.Memory, (byte)0xEA);
        bus.Memory[0xFFFE] = 0;
        bus.Memory[0xFFFF] = 0x30;
        bus.Memory[0xFFFC] = 0;
        bus.Memory[0xFFFD] = 0x40;
        bus.Memory[0xFFFA] = 0;
        bus.Memory[0xFFFB] = 0x50;
        return bus;
    }

    private static Processor<RecordingBus> Create(RecordingBus bus, ProcessorVariant variant)
    {
        Processor<RecordingBus> cpu = new(bus, variant);
        ProcessorRegisters registers = cpu.Registers;
        registers.ProgramCounter = 0x200;
        cpu.Registers = registers;
        return cpu;
    }
}
