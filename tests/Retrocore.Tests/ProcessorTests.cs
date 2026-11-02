// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Tests;

/// <summary>
///  Directed tests for the cycle-stepping execution foundation.
///  These do not substitute for the full upstream conformance and performance gates.
/// </summary>
[TestClass]
public class ProcessorTests
{
    /// <summary>
    ///  Tests every supported non-halting encoding's instruction length in cycles.
    /// </summary>
    /// <param name="variant">The CPU variant.</param>
    [TestMethod]
    [DataRow(ProcessorVariant.Mos6502)]
    [DataRow(ProcessorVariant.Wdc65C02)]
    [DataRow(ProcessorVariant.Rockwell65C02)]
    public void SupportedEncodingsCompleteInExpectedCycles(ProcessorVariant variant)
    {
        (byte Opcode, int Cycles)[] encodings =
        [
            (0x00, 7), (0x20, 6), (0x40, 6), (0x60, 6), (0x4C, 3),
            (0xA9, 2), (0xA2, 2), (0xA0, 2), (0x48, 3), (0x08, 3),
            (0x68, 4), (0x28, 4), (0xEA, 2), (0x18, 2), (0x38, 2),
            (0x58, 2), (0x78, 2), (0xB8, 2), (0xD8, 2), (0xF8, 2),
            (0xAA, 2), (0xA8, 2), (0x8A, 2), (0x98, 2), (0xBA, 2),
            (0x9A, 2), (0xCA, 2), (0x88, 2), (0xE8, 2), (0xC8, 2)
        ];

        if (variant != ProcessorVariant.Mos6502)
        {
            encodings = [.. encodings, (0xDA, 3), (0x5A, 3), (0xFA, 4), (0x7A, 4), (0x1A, 2), (0x3A, 2)];
        }

        foreach ((byte opcode, int cycles) in encodings)
        {
            RecordingBus bus = new();
            bus.Memory[0x200] = opcode;
            Processor<RecordingBus> cpu = Create(bus, variant);
            ProcessorExecutionResult result = cpu.StepInstruction();
            result.Status.Should().Be(ProcessorExecutionStatus.InstructionComplete, $"opcode ${opcode:X2}");
            result.Cycles.Should().Be((ulong)cycles, $"opcode ${opcode:X2}");
            bus.Accesses.Should().HaveCount(cycles);
            cpu.IsInstructionBoundary.Should().BeTrue();
        }
    }

    /// <summary>
    ///  Verifies that opcode fetch and operand read are separate observable cycles.
    /// </summary>
    /// <param name="variant">The CPU variant.</param>
    [TestMethod]
    [DataRow(ProcessorVariant.Mos6502)]
    [DataRow(ProcessorVariant.Wdc65C02)]
    [DataRow(ProcessorVariant.Rockwell65C02)]
    public void ImmediateLoadsExposeExactCyclesAndFlags(ProcessorVariant variant)
    {
        byte[] opcodes = [0xA9, 0xA2, 0xA0];
        byte[] operands = [0, 0x7F, 0x80, 0xFF];
        foreach (byte opcode in opcodes)
        {
            foreach (byte operand in operands)
            {
                RecordingBus bus = new();
                bus.Memory[0x200] = opcode;
                bus.Memory[0x201] = operand;
                Processor<RecordingBus> cpu = Create(bus, variant);
                ProcessorCycle fetch = cpu.NextCycle();
                fetch.Number.Should().Be(1);
                fetch.IsOpcodeFetch.Should().BeTrue();
                fetch.Address.Should().Be(0x200);
                fetch.Value.Should().Be(opcode);
                cpu.IsInstructionBoundary.Should().BeFalse();
                cpu.CurrentOpCode.Should().NotBeNull();
                cpu.CurrentOpCode.GetValueOrDefault().AddressMode.Should().Be(AddressMode.Immediate);

                ProcessorCycle read = cpu.NextCycle();
                read.Number.Should().Be(2);
                read.IsOpcodeFetch.Should().BeFalse();
                read.Address.Should().Be(0x201);
                read.Value.Should().Be(operand);
                read.Operation.Should().Be(BusOperation.Read);
                cpu.IsInstructionBoundary.Should().BeTrue();
                cpu.Registers.ProgramCounter.Should().Be(0x202);
                byte actual = opcode switch
                {
                    0xA9 => cpu.Registers.Accumulator,
                    0xA2 => cpu.Registers.X,
                    _ => cpu.Registers.Y
                };

                actual.Should().Be(operand);
                ((cpu.Registers.Status & StatusRegister.Zero) != 0).Should().Be(operand == 0);
                ((cpu.Registers.Status & StatusRegister.Negative) != 0).Should().Be((operand & 0x80) != 0);
                bus.Accesses.Should().HaveCount(2);
            }
        }
    }

    /// <summary>
    ///  Verifies implied and accumulator operations update only their specified registers and flags.
    /// </summary>
    /// <param name="variant">The CPU variant.</param>
    [TestMethod]
    [DataRow(ProcessorVariant.Mos6502)]
    [DataRow(ProcessorVariant.Wdc65C02)]
    [DataRow(ProcessorVariant.Rockwell65C02)]
    public void ImpliedOperationsPreserveUnrelatedRegistersAndFlags(ProcessorVariant variant)
    {
        (byte Opcode, byte A, byte X, byte Y, byte S, byte P)[] cases =
        [
            (0xEA, 0x80, 1, 0, 0xFD, 0xEF),
            (0x18, 0x80, 1, 0, 0xFD, 0xEE),
            (0x38, 0x80, 1, 0, 0xFD, 0xEF),
            (0x58, 0x80, 1, 0, 0xFD, 0xEB),
            (0x78, 0x80, 1, 0, 0xFD, 0xEF),
            (0xB8, 0x80, 1, 0, 0xFD, 0xAF),
            (0xD8, 0x80, 1, 0, 0xFD, 0xE7),
            (0xF8, 0x80, 1, 0, 0xFD, 0xEF),
            (0xAA, 0x80, 0x80, 0, 0xFD, 0xED),
            (0xA8, 0x80, 1, 0x80, 0xFD, 0xED),
            (0x8A, 1, 1, 0, 0xFD, 0x6D),
            (0x98, 0, 1, 0, 0xFD, 0x6F),
            (0xBA, 0x80, 0xFD, 0, 0xFD, 0xED),
            (0x9A, 0x80, 1, 0, 1, 0xEF),
            (0xCA, 0x80, 0, 0, 0xFD, 0x6F),
            (0x88, 0x80, 1, 0xFF, 0xFD, 0xED),
            (0xE8, 0x80, 2, 0, 0xFD, 0x6D),
            (0xC8, 0x80, 1, 1, 0xFD, 0x6D)
        ];

        if (variant != ProcessorVariant.Mos6502)
        {
            cases = [.. cases, (0x1A, 0x81, 1, 0, 0xFD, 0xED), (0x3A, 0x7F, 1, 0, 0xFD, 0x6D)];
        }

        foreach ((byte opcode, byte a, byte x, byte y, byte s, byte p) in cases)
        {
            RecordingBus bus = new();
            bus.Memory[0x200] = opcode;
            Processor<RecordingBus> cpu = Create(bus, variant);
            cpu.Registers = new()
            {
                Accumulator = 0x80,
                X = 1,
                StackPointer = 0xFD,
                Status = (StatusRegister)0xEF,
                ProgramCounter = 0x200
            };

            cpu.StepInstruction().Cycles.Should().Be(2);
            cpu.Registers.Should().BeEquivalentTo(new ProcessorRegisters
            {
                Accumulator = a,
                X = x,
                Y = y,
                StackPointer = s,
                Status = (StatusRegister)p,
                ProgramCounter = 0x201
            }, $"opcode ${opcode:X2}");
        }
    }

    /// <summary>
    ///  Verifies data pushes and pulls wrap within page one and restore the selected register.
    /// </summary>
    /// <param name="variant">The CPU variant.</param>
    [TestMethod]
    [DataRow(ProcessorVariant.Mos6502)]
    [DataRow(ProcessorVariant.Wdc65C02)]
    [DataRow(ProcessorVariant.Rockwell65C02)]
    public void StackDataRoundTripsWrapWithinPageOne(ProcessorVariant variant)
    {
        (byte Push, byte Pull)[] encodings = variant == ProcessorVariant.Mos6502
            ? [(0x48, 0x68)]
            : [(0x48, 0x68), (0xDA, 0xFA), (0x5A, 0x7A)];

        foreach ((byte push, byte pull) in encodings)
        {
            RecordingBus bus = new();
            bus.Memory[0x200] = push;
            bus.Memory[0x201] = pull;
            Processor<RecordingBus> cpu = Create(bus, variant);
            cpu.Registers = new()
            {
                Accumulator = 0x80,
                X = 0x80,
                Y = 0x80,
                StackPointer = 0,
                Status = StatusRegister.Carry,
                ProgramCounter = 0x200
            };

            cpu.StepInstruction().Cycles.Should().Be(3);
            bus.Memory[0x100].Should().Be(0x80);
            cpu.Registers.StackPointer.Should().Be(0xFF);
            ProcessorRegisters registers = cpu.Registers;
            registers.Accumulator = 1;
            registers.X = 1;
            registers.Y = 1;
            cpu.Registers = registers;
            cpu.StepInstruction().Cycles.Should().Be(4);
            cpu.Registers.StackPointer.Should().Be(0);
            byte restored = pull switch
            {
                0x68 => cpu.Registers.Accumulator,
                0xFA => cpu.Registers.X,
                _ => cpu.Registers.Y
            };

            restored.Should().Be(0x80);
            cpu.Registers.Status.Should().Be(StatusRegister.Carry | StatusRegister.Unused | StatusRegister.Negative);
            bus.Accesses.Select(access => access.Address).Should().Equal(
                (ushort)0x200,
                (ushort)0x201,
                (ushort)0x100,
                (ushort)0x201,
                (ushort)0x202,
                (ushort)0x1FF,
                (ushort)0x100);
        }
    }

    /// <summary>
    ///  Verifies reset reads, stack wrapping, vector loading, and variant-specific decimal clearing.
    /// </summary>
    /// <param name="variant">The CPU variant.</param>
    [TestMethod]
    [DataRow(ProcessorVariant.Mos6502)]
    [DataRow(ProcessorVariant.Wdc65C02)]
    [DataRow(ProcessorVariant.Rockwell65C02)]
    public void ResetPerformsSevenReadsWithoutWritingStack(ProcessorVariant variant)
    {
        RecordingBus bus = new();
        bus.Memory[0xFFFC] = 0x34;
        bus.Memory[0xFFFD] = 0x12;
        Processor<RecordingBus> cpu = Create(bus, variant);
        ProcessorRegisters registers = cpu.Registers;
        registers.StackPointer = 0;
        registers.Status = StatusRegister.DecimalMode;
        cpu.Registers = registers;
        cpu.Reset();
        bus.Accesses.Should().BeEmpty();
        cpu.IsInstructionBoundary.Should().BeFalse();
        cpu.Run(cycleBudget: 7).Cycles.Should().Be(7);
        bus.Accesses.Select(access => access.Address).Should().Equal(
            (ushort)0x200,
            (ushort)0x200,
            (ushort)0x100,
            (ushort)0x1FF,
            (ushort)0x1FE,
            (ushort)0xFFFC,
            (ushort)0xFFFD);

        bus.Accesses.Should().OnlyContain(access => access.Operation == BusOperation.Read);
        cpu.Registers.StackPointer.Should().Be(0xFD);
        cpu.Registers.ProgramCounter.Should().Be(0x1234);
        cpu.Registers.Status.HasFlag(StatusRegister.IRQBDisable).Should().BeTrue();
        cpu.Registers.Status.HasFlag(StatusRegister.DecimalMode).Should().Be(variant == ProcessorVariant.Mos6502);
        cpu.CycleCount.Should().Be(7);
        cpu.IsInstructionBoundary.Should().BeTrue();
    }

    /// <summary>
    ///  Verifies JSR and RTS stack values and all dummy reads.
    /// </summary>
    /// <param name="variant">The CPU variant.</param>
    [TestMethod]
    [DataRow(ProcessorVariant.Mos6502)]
    [DataRow(ProcessorVariant.Wdc65C02)]
    [DataRow(ProcessorVariant.Rockwell65C02)]
    public void SubroutineRoundTripHasExactBusTrace(ProcessorVariant variant)
    {
        RecordingBus bus = new();
        bus.Memory[0x200] = 0x20;
        bus.Memory[0x201] = 0x00;
        bus.Memory[0x202] = 0x30;
        bus.Memory[0x3000] = 0x60;
        Processor<RecordingBus> cpu = Create(bus, variant);
        cpu.StepInstruction().Cycles.Should().Be(6);
        cpu.Registers.ProgramCounter.Should().Be(0x3000);
        cpu.StepInstruction().Cycles.Should().Be(6);
        cpu.Registers.ProgramCounter.Should().Be(0x203);
        cpu.Registers.StackPointer.Should().Be(0xFD);
        (ushort Address, byte Value, BusOperation Operation)[] expected =
        [
            (0x200, 0x20, BusOperation.Read),
            (0x201, 0x00, BusOperation.Read),
            (0x1FD, 0x00, BusOperation.Read),
            (0x1FD, 0x02, BusOperation.Write),
            (0x1FC, 0x02, BusOperation.Write),
            (0x202, 0x30, BusOperation.Read),
            (0x3000, 0x60, BusOperation.Read),
            (0x3001, 0x00, BusOperation.Read),
            (0x1FB, 0x00, BusOperation.Read),
            (0x1FC, 0x02, BusOperation.Read),
            (0x1FD, 0x02, BusOperation.Read),
            (0x202, 0x30, BusOperation.Read)
        ];

        bus.Accesses.Should().Equal(expected);
    }

    /// <summary>
    ///  Verifies that BRK pushes PC plus two and RTI restores status without storing a break flag.
    /// </summary>
    /// <param name="variant">The CPU variant.</param>
    [TestMethod]
    [DataRow(ProcessorVariant.Mos6502)]
    [DataRow(ProcessorVariant.Wdc65C02)]
    [DataRow(ProcessorVariant.Rockwell65C02)]
    public void BrkAndRtiRestoreRegistersAndStatus(ProcessorVariant variant)
    {
        RecordingBus bus = new();
        bus.Memory[0xFFFE] = 0x00;
        bus.Memory[0xFFFF] = 0x30;
        bus.Memory[0x3000] = 0x40;
        Processor<RecordingBus> cpu = Create(bus, variant);
        ProcessorRegisters registers = cpu.Registers;
        registers.Status = StatusRegister.DecimalMode | StatusRegister.Carry;
        cpu.Registers = registers;
        cpu.StepInstruction().Cycles.Should().Be(7);
        bus.Memory[0x1FD].Should().Be(2);
        bus.Memory[0x1FC].Should().Be(2);
        bus.Memory[0x1FB].Should().Be(0x39);
        cpu.Registers.ProgramCounter.Should().Be(0x3000);
        cpu.Registers.Status.HasFlag(StatusRegister.DecimalMode).Should().Be(variant == ProcessorVariant.Mos6502);
        cpu.StepInstruction().Cycles.Should().Be(6);
        cpu.Registers.ProgramCounter.Should().Be(0x202);
        cpu.Registers.StackPointer.Should().Be(0xFD);
        cpu.Registers.Status.Should().Be(StatusRegister.DecimalMode | StatusRegister.Carry | StatusRegister.Unused);
        bus.Accesses.Should().HaveCount(13);
    }

    /// <summary>
    ///  Verifies unmasked IRQ and edge-latched NMI entry and return addresses.
    /// </summary>
    /// <param name="variant">The CPU variant.</param>
    [TestMethod]
    [DataRow(ProcessorVariant.Mos6502)]
    [DataRow(ProcessorVariant.Wdc65C02)]
    [DataRow(ProcessorVariant.Rockwell65C02)]
    public void HardwareInterruptEntryUsesSevenCycles(ProcessorVariant variant)
    {
        foreach (bool nmi in new[] { false, true })
        {
            RecordingBus bus = new();
            ushort vector = nmi ? (ushort)0xFFFA : (ushort)0xFFFE;
            bus.Memory[vector] = 0x00;
            bus.Memory[vector + 1] = 0x30;
            bus.Memory[0x3000] = 0xEA;
            Processor<RecordingBus> cpu = Create(bus, variant);
            ProcessorRegisters registers = cpu.Registers;
            registers.Status = StatusRegister.Carry | StatusRegister.DecimalMode;
            cpu.Registers = registers;
            cpu.Signals = nmi ? ProcessorSignals.NonMaskableInterrupt : ProcessorSignals.InterruptRequest;
            cpu.Run(cycleBudget: 7);
            cpu.Registers.ProgramCounter.Should().Be(0x3000);
            bus.Accesses.Select(access => access.Address).Should().Equal(
                (ushort)0x200,
                (ushort)0x200,
                (ushort)0x1FD,
                (ushort)0x1FC,
                (ushort)0x1FB,
                vector,
                (ushort)(vector + 1));

            bus.Memory[0x1FD].Should().Be(2);
            bus.Memory[0x1FC].Should().Be(0);
            bus.Memory[0x1FB].Should().Be(0x29);
            cpu.StepInstruction().Status.Should().Be(ProcessorExecutionStatus.InstructionComplete);
            cpu.Registers.ProgramCounter.Should().Be(0x3001);
        }
    }

    /// <summary>
    ///  Verifies a mid-JSR snapshot replays CPU state and bus accesses exactly when memory is also restored.
    /// </summary>
    [TestMethod]
    public void MidInstructionSnapshotRestoresLatchesAndCycleMetadata()
    {
        RecordingBus bus = new();
        bus.Memory[0x200] = 0x20;
        bus.Memory[0x201] = 0x34;
        bus.Memory[0x202] = 0x12;
        Processor<RecordingBus> cpu = Create(bus);
        cpu.Run(cycleBudget: 3);
        ProcessorSnapshot snapshot = cpu.CaptureState();
        byte[] memory = (byte[])bus.Memory.Clone();
        bus.Accesses.Clear();
        cpu.Run(cycleBudget: 3);
        ProcessorSnapshot completed = cpu.CaptureState();
        (ushort Address, byte Value, BusOperation Operation)[] trace = [.. bus.Accesses];
        bus.Accesses.Clear();
        memory.CopyTo(bus.Memory, index: 0);
        cpu.RestoreState(snapshot);
        bus.Accesses.Should().BeEmpty();
        cpu.CycleCount.Should().Be(3);
        cpu.IsInstructionBoundary.Should().BeFalse();
        cpu.Run(cycleBudget: 3);
        bus.Accesses.Should().Equal(trace);
        cpu.CaptureState().Should().BeEquivalentTo(completed);
        cpu.Registers.ProgramCounter.Should().Be(0x1234);
    }

    /// <summary>
    ///  Verifies held reads retain microstate while bus side effects and cycle counting remain observable.
    /// </summary>
    [TestMethod]
    public void ReadStallRepeatsOperandWithoutAdvancingRegisters()
    {
        RecordingBus bus = new();
        bus.Memory[0x200] = 0xA9;
        bus.Memory[0x201] = 0x80;
        Processor<RecordingBus> cpu = Create(bus);
        cpu.StepCycle();
        cpu.Signals = ProcessorSignals.ReadStall;
        cpu.StepInstruction(maximumCycles: 3).Status.Should().Be(ProcessorExecutionStatus.CycleBudgetExhausted);
        cpu.Registers.ProgramCounter.Should().Be(0x201);
        cpu.Registers.Accumulator.Should().Be(0);
        cpu.CycleCount.Should().Be(4);
        bus.Accesses.Select(access => access.Address).Should().Equal(
            (ushort)0x200,
            (ushort)0x201,
            (ushort)0x201,
            (ushort)0x201);

        cpu.NextCycle().IsStalled.Should().BeTrue();
        cpu.Signals = ProcessorSignals.None;
        cpu.StepInstruction().Cycles.Should().Be(1);
        cpu.Registers.Accumulator.Should().Be(0x80);
        cpu.Registers.ProgramCounter.Should().Be(0x202);
    }

    /// <summary>
    ///  Verifies a device's input changes survive a held read and take effect on the following cycle.
    /// </summary>
    [TestMethod]
    public void DeviceInputChangesDuringStallAreNotRolledBack()
    {
        RecordingBus bus = new();
        bus.Memory[0x200] = 0xA9;
        bus.Memory[0x201] = 0x80;
        Processor<RecordingBus> cpu = Create(bus);
        cpu.StepCycle();
        cpu.Signals = ProcessorSignals.ReadStall;
        bus.ReadCallback = address =>
        {
            if (address == 0x201)
            {
                cpu.Signals = ProcessorSignals.InterruptRequest;
            }

        };

        cpu.NextCycle().IsStalled.Should().BeTrue();
        cpu.Signals.Should().Be(ProcessorSignals.InterruptRequest);
        cpu.Registers.Accumulator.Should().Be(0);
        cpu.NextCycle().IsStalled.Should().BeFalse();
        cpu.Registers.Accumulator.Should().Be(0x80);
        cpu.CycleCount.Should().Be(3);
        bus.Accesses.Should().HaveCount(3);
    }

    /// <summary>
    ///  Verifies snapshots preserve both pending NMI and the already sampled edge.
    /// </summary>
    [TestMethod]
    public void SnapshotsPreservePendingInterruptsAndSampledEdges()
    {
        RecordingBus bus = new();
        bus.Memory[0x200] = 0xA9;
        bus.Memory[0x201] = 0x80;
        bus.Memory[0xFFFA] = 0x00;
        bus.Memory[0xFFFB] = 0x30;
        bus.Memory[0x3000] = 0xEA;
        Processor<RecordingBus> cpu = Create(bus);
        cpu.StepCycle();
        cpu.Signals = ProcessorSignals.NonMaskableInterrupt;
        cpu.StepCycle();
        ProcessorSnapshot pending = cpu.CaptureState();
        cpu.Run(cycleBudget: 7);
        cpu.Registers.ProgramCounter.Should().Be(0x3000);
        cpu.Signals = ProcessorSignals.None;
        cpu.RestoreState(pending);
        cpu.Signals.Should().Be(ProcessorSignals.NonMaskableInterrupt);
        cpu.Run(cycleBudget: 7);
        cpu.Registers.ProgramCounter.Should().Be(0x3000);
        ProcessorSnapshot serviced = cpu.CaptureState();
        cpu.Signals = ProcessorSignals.None;
        cpu.RestoreState(serviced);
        cpu.StepInstruction().Cycles.Should().Be(2);
        cpu.Registers.ProgramCounter.Should().Be(0x3001);
    }

    /// <summary>
    ///  Verifies stalled opcode fetches do not consume an opcode.
    /// </summary>
    [TestMethod]
    public void StalledFetchDoesNotConsumeOpcode()
    {
        RecordingBus bus = new();
        bus.Memory[0x200] = 0x03;
        Processor<RecordingBus> cpu = Create(bus);
        cpu.Signals = ProcessorSignals.ReadStall;
        cpu.NextCycle().IsStalled.Should().BeTrue();
        cpu.IsInstructionBoundary.Should().BeTrue();
        cpu.Registers.ProgramCounter.Should().Be(0x200);
        cpu.Signals = ProcessorSignals.None;
        cpu.NextCycle().IsOpcodeFetch.Should().BeTrue();
        cpu.CurrentOpCode.GetValueOrDefault().Instruction.Should().Be(Instruction.SLO);
        cpu.Registers.ProgramCounter.Should().Be(0x201);
    }

    /// <summary>
    ///  Verifies SO assertions are edge-sensitive and do not continuously override CLV.
    /// </summary>
    [TestMethod]
    public void OverflowInputIsEdgeSensitive()
    {
        RecordingBus bus = new();
        Array.Fill(bus.Memory, (byte)0xEA);
        bus.Memory[0x200] = 0xB8;
        Processor<RecordingBus> cpu = Create(bus);
        cpu.Signals = ProcessorSignals.SetOverflow;
        cpu.StepCycle();
        cpu.Registers.Status.HasFlag(StatusRegister.Overflow).Should().BeTrue();
        cpu.StepCycle();
        cpu.Registers.Status.HasFlag(StatusRegister.Overflow).Should().BeFalse();
        cpu.StepInstruction();
        cpu.Registers.Status.HasFlag(StatusRegister.Overflow).Should().BeFalse();
        cpu.Signals = ProcessorSignals.None;
        cpu.StepCycle();
        cpu.Signals = ProcessorSignals.SetOverflow;
        cpu.StepCycle();
        cpu.Registers.Status.HasFlag(StatusRegister.Overflow).Should().BeTrue();
    }

    /// <summary>
    ///  Verifies waiting returns promptly and a masked IRQ wakes WAI without entering its vector.
    /// </summary>
    [TestMethod]
    public void WdcWaitReturnsAndMaskedIrqResumesExecution()
    {
        RecordingBus bus = new();
        bus.Memory[0x200] = 0xCB;
        bus.Memory[0x201] = 0xEA;
        Processor<RecordingBus> cpu = Create(bus, ProcessorVariant.Wdc65C02);
        cpu.StepInstruction().Status.Should().Be(ProcessorExecutionStatus.Waiting);
        cpu.CycleCount.Should().Be(3);
        cpu.StepInstruction().Cycles.Should().Be(0);
        cpu.Run(cycleBudget: 5).Status.Should().Be(ProcessorExecutionStatus.Waiting);
        cpu.CycleCount.Should().Be(8);
        cpu.Signals = ProcessorSignals.InterruptRequest;
        cpu.StepInstruction().Status.Should().Be(ProcessorExecutionStatus.InstructionComplete);
        cpu.Registers.ProgramCounter.Should().Be(0x202);
        cpu.Registers.StackPointer.Should().Be(0xFD);
    }

    /// <summary>
    ///  Verifies stopped and jammed execution cannot hang instruction helpers and can be reset.
    /// </summary>
    /// <param name="variant">The CPU variant.</param>
    /// <param name="opcode">The halting opcode.</param>
    /// <param name="status">The expected halt status.</param>
    [TestMethod]
    [DataRow(ProcessorVariant.Mos6502, (byte)0x02, ProcessorExecutionStatus.Jammed)]
    [DataRow(ProcessorVariant.Wdc65C02, (byte)0xDB, ProcessorExecutionStatus.Stopped)]
    public void HaltedExecutionReturnsExplicitStatusAndResetRecovers(
        ProcessorVariant variant,
        byte opcode,
        ProcessorExecutionStatus status)
    {
        RecordingBus bus = new();
        bus.Memory[0x200] = opcode;
        bus.Memory[0xFFFC] = 0x00;
        bus.Memory[0xFFFD] = 0x30;
        bus.Memory[0x3000] = 0xEA;
        Processor<RecordingBus> cpu = Create(bus, variant);
        cpu.StepInstruction().Status.Should().Be(status);
        ProcessorSnapshot snapshot = cpu.CaptureState();
        cpu.StepInstruction().Cycles.Should().Be(0);
        bus.Accesses.Clear();
        cpu.Signals = ProcessorSignals.InterruptRequest | ProcessorSignals.NonMaskableInterrupt;
        cpu.Run(cycleBudget: 10).Status.Should().Be(status);
        if (status == ProcessorExecutionStatus.Jammed)
        {
            bus.Accesses.Select(access => access.Address).Should().Equal(
                (ushort)0xFFFF,
                (ushort)0xFFFE,
                (ushort)0xFFFE,
                (ushort)0xFFFF,
                (ushort)0xFFFF,
                (ushort)0xFFFF,
                (ushort)0xFFFF,
                (ushort)0xFFFF,
                (ushort)0xFFFF,
                (ushort)0xFFFF);
        }
        else
        {
            bus.Accesses.Should().BeEmpty();
        }

        cpu.RestoreState(snapshot);
        cpu.Status.Should().Be(status);
        cpu.Signals = ProcessorSignals.Reset;
        cpu.StepCycle();
        cpu.Signals = ProcessorSignals.None;
        cpu.StepInstruction(maximumCycles: 8).Status.Should().Be(ProcessorExecutionStatus.InstructionComplete);
        cpu.Registers.ProgramCounter.Should().Be(0x3001);
        cpu.Status.Should().Be(ProcessorExecutionStatus.Running);
    }

    /// <summary>
    ///  Verifies exact budgets can end mid-instruction and zero budgets do not touch the bus.
    /// </summary>
    [TestMethod]
    public void RunHonorsExactCycleBudgets()
    {
        RecordingBus bus = new();
        Array.Fill(bus.Memory, (byte)0xEA);
        Processor<RecordingBus> cpu = Create(bus);
        cpu.Run(cycleBudget: 0).Cycles.Should().Be(0);
        bus.Accesses.Should().BeEmpty();
        cpu.Run(cycleBudget: 3).Cycles.Should().Be(3);
        cpu.CycleCount.Should().Be(3);
        cpu.IsInstructionBoundary.Should().BeFalse();
        cpu.StepInstruction().Cycles.Should().Be(1);
        cpu.CycleCount.Should().Be(4);
        bus.Accesses.Should().HaveCount(4);
    }

    /// <summary>
    ///  Verifies 16-bit program-counter wrap and the implied instruction's dummy read.
    /// </summary>
    [TestMethod]
    public void ProgramCounterWrapsAtEndOfAddressSpace()
    {
        RecordingBus bus = new();
        bus.Memory[0xFFFF] = 0xA9;
        bus.Memory[0] = 0xEA;
        Processor<RecordingBus> cpu = Create(bus);
        ProcessorRegisters registers = cpu.Registers;
        registers.ProgramCounter = 0xFFFF;
        cpu.Registers = registers;
        cpu.StepInstruction().Cycles.Should().Be(2);
        cpu.Registers.ProgramCounter.Should().Be(1);
        cpu.Registers.Accumulator.Should().Be(0xEA);
        bus.Accesses.Select(access => access.Address).Should().Equal((ushort)0xFFFF, (ushort)0);
    }

    /// <summary>
    ///  Verifies mutable struct buses are not defensively copied on each access.
    /// </summary>
    [TestMethod]
    public void StructBusRetainsMutableStateBetweenCycles()
    {
        List<int> reads = [];
        Processor<StatefulBus> cpu = new(new StatefulBus(reads));
        cpu.Run(cycleBudget: 4);
        reads.Should().Equal(1, 2, 3, 4);
    }

    /// <summary>
    ///  Verifies callers can restore live struct-bus state alongside a mid-instruction CPU snapshot.
    /// </summary>
    [TestMethod]
    public void CallerCanRestoreMutableBusAndCpuTogether()
    {
        List<int> reads = [];
        Processor<StatefulBus> cpu = new(new StatefulBus(reads));
        cpu.Run(cycleBudget: 3);
        ProcessorSnapshot snapshot = cpu.CaptureState();
        StatefulBus bus = cpu.Bus;
        cpu.Run(cycleBudget: 3);
        cpu.RestoreState(snapshot);
        cpu.Bus = bus;
        cpu.Run(cycleBudget: 3);
        reads.Should().Equal(1, 2, 3, 4, 5, 6, 4, 5, 6);
        cpu.CycleCount.Should().Be(6);
        cpu.IsInstructionBoundary.Should().BeTrue();
    }

    /// <summary>
    ///  Verifies invalid construction, snapshot restoration, and mid-instruction mutation fail explicitly.
    /// </summary>
    [TestMethod]
    public void InvalidStateOperationsThrow()
    {
        RecordingBus bus = new();
        bus.Memory[0x200] = 0xEA;
#pragma warning disable CS8625 // Exercise the public constructor's null guard.
        Action invalidBus = () => new Processor<RecordingBus>(bus: null);
#pragma warning restore CS8625
        invalidBus.Should().Throw<ArgumentNullException>();
        Action invalidVariant = () => new Processor<RecordingBus>(bus, (ProcessorVariant)99);
        invalidVariant.Should().Throw<ArgumentOutOfRangeException>();
        Processor<RecordingBus> cpu = Create(bus);
        Action invalidSignals = () => cpu.Signals = (ProcessorSignals)0x80;
        invalidSignals.Should().Throw<ArgumentOutOfRangeException>();
        Action invalidLimit = () => cpu.StepInstruction(maximumCycles: 0);
        invalidLimit.Should().Throw<ArgumentOutOfRangeException>();
        Action defaultSnapshot = () => cpu.RestoreState(snapshot: default);
        defaultSnapshot.Should().Throw<ArgumentException>();
        ProcessorSnapshot otherVariant = new Processor<RecordingBus>(bus, ProcessorVariant.Wdc65C02).CaptureState();
        Action mismatchedSnapshot = () => cpu.RestoreState(otherVariant);
        mismatchedSnapshot.Should().Throw<ArgumentException>();
        cpu.StepCycle();
        Action overwrite = () => cpu.Registers = new();
        overwrite.Should().Throw<InvalidOperationException>();
    }

    private static Processor<RecordingBus> Create(
        RecordingBus bus,
        ProcessorVariant variant = ProcessorVariant.Mos6502)
    {
        Processor<RecordingBus> cpu = new(bus, variant);
        ProcessorRegisters registers = cpu.Registers;
        registers.ProgramCounter = 0x200;
        cpu.Registers = registers;
        return cpu;
    }
}
