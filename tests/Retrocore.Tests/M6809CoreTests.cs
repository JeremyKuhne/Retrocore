// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Cpu.M6809;
using Retrocore.Perf;

namespace Retrocore.Tests;

/// <summary>
///  Directed tests for the MC6809 core: cycle-exact bus activity, interrupts, wait states, reset, snapshots,
///  zero-allocation stepping and the debugger register view.
/// </summary>
[TestClass]
public class M6809CoreTests
{
    /// <summary>
    ///  Immediate arithmetic updates the signed result, condition codes and returns <see cref="ProcessorExecutionStatus.InstructionComplete"/>.
    /// </summary>
    [TestMethod]
    public void ImmediateArithmeticSetsNegativeAndOverflow()
    {
        M6809Processor<RamBus> cpu = Create(0x86, 0x7F, 0x8B, 0x01);

        ProcessorExecutionResult first = cpu.StepInstruction();
        first.Status.Should().Be(ProcessorExecutionStatus.InstructionComplete);
        first.Cycles.Should().Be(2);

        ProcessorExecutionResult second = cpu.StepInstruction();
        second.Status.Should().Be(ProcessorExecutionStatus.InstructionComplete);
        second.Cycles.Should().Be(2);

        cpu.Registers.A.Should().Be(0x80);
        cpu.Registers.Flags.Should().HaveFlag(M6809ConditionCode.Negative | M6809ConditionCode.Overflow);
        (cpu.Registers.Flags & (M6809ConditionCode.Zero | M6809ConditionCode.Carry)).Should().Be(M6809ConditionCode.None);
    }

    /// <summary>
    ///  An equal compare sets zero without changing the accumulator.
    /// </summary>
    [TestMethod]
    public void CompareSetsZeroFlag()
    {
        M6809Processor<RamBus> cpu = Create(0x86, 0x03, 0x81, 0x03);

        cpu.StepInstruction();
        cpu.StepInstruction();

        cpu.Registers.A.Should().Be(0x03);
        cpu.Registers.Flags.Should().HaveFlag(M6809ConditionCode.Zero);
    }

    /// <summary>
    ///  An indexed LEA adds a signed displacement and updates only the zero flag.
    /// </summary>
    [TestMethod]
    public void IndexedLeaUsesSignedDisplacement()
    {
        M6809Processor<RamBus> cpu = Create(0x30, 0x88, 0xFE);
        cpu.Registers = new() { X = 0x1000, CC = 0xF5 };

        cpu.StepInstruction().Status.Should().Be(ProcessorExecutionStatus.InstructionComplete);

        cpu.Registers.X.Should().Be(0x0FFE);
        cpu.Registers.CC.Should().Be((byte)(0xF5 & ~0x04));
    }

    /// <summary>
    ///  A negative five-bit offset is not an indirect postbyte.
    /// </summary>
    [TestMethod]
    public void IndexedLeaUsesSignedFiveBitDisplacement()
    {
        M6809Processor<RamBus> cpu = Create(0x30, 0x1E);
        cpu.Registers = new() { X = 0x1000 };

        cpu.StepInstruction();

        cpu.Registers.X.Should().Be(0x0FFE);
    }

    /// <summary>
    ///  Right shifts leave the overflow flag unchanged.
    /// </summary>
    [TestMethod]
    public void RightShiftsPreserveOverflow()
    {
        M6809Processor<RamBus> rotate = Create(0x46);
        rotate.Registers = new() { A = 0x01 };
        rotate.StepInstruction();
        rotate.Registers.A.Should().Be(0x00);
        (rotate.Registers.CC & 0x0F).Should().Be(0x05);

        M6809Processor<RamBus> logical = Create(0x44);
        logical.Registers = new() { A = 0x01 };
        logical.StepInstruction();
        logical.Registers.A.Should().Be(0x00);
        (logical.Registers.CC & 0x0F).Should().Be(0x05);

        M6809Processor<RamBus> arithmetic = Create(0x47);
        arithmetic.Registers = new() { A = 0x80 };
        arithmetic.StepInstruction();
        arithmetic.Registers.A.Should().Be(0xC0);
        (arithmetic.Registers.CC & 0x0F).Should().Be(0x08);
    }

    /// <summary>
    ///  Reset takes seven clocks and loads the big-endian reset vector.
    /// </summary>
    [TestMethod]
    public void ResetLoadsVector()
    {
        M6809Processor<RamBus> cpu = Create();
        cpu.Bus.Memory[0xFFFE] = 0x12;
        cpu.Bus.Memory[0xFFFF] = 0x34;

        cpu.Reset();
        List<ProcessorCycle> cycles = Cycles(cpu);

        cycles.Should().HaveCount(7);
        cycles[4].Operation.Should().Be(BusOperation.None);
        cycles[5].Operation.Should().Be(BusOperation.Read);
        cycles[5].Address.Should().Be(0xFFFE);
        cycles[6].Operation.Should().Be(BusOperation.Read);
        cycles[6].Address.Should().Be(0xFFFF);
        cpu.Registers.PC.Should().Be(0x1234);
        cpu.CycleCount.Should().Be(7);
        cpu.IsInstructionBoundary.Should().BeTrue();
    }

    /// <summary>
    ///  Holding RESET asserted holds the CPU before reading the reset vector and aborts in-flight instructions
    ///  without committing their register writes.
    /// </summary>
    [TestMethod]
    public void ResetSignalHoldsVectorFetchUntilReleasedAndAbortsInFlightInstruction()
    {
        // MUL ($3D, 11 cycles) aborted on cycle 3 must not write D = A * B.
        M6809Processor<RamBus> cpu = Create(0x3D);
        cpu.Bus.Memory[0xFFFE] = 0x20;
        cpu.Bus.Memory[0xFFFF] = 0x00;
        cpu.Bus.Memory[0x2000] = 0x12;
        cpu.Registers = new() { A = 0x07, B = 0x09 };

        cpu.StepCycle();
        cpu.StepCycle();
        cpu.Registers.D.Should().Be(0x0709, "MUL commits only on its final cycle");

        cpu.Signals = M6809Signals.Reset;
        for (int cycle = 0; cycle < 10; cycle++)
        {
            ProcessorCycle held = cpu.NextCycle();
            held.Operation.Should().Be(BusOperation.None, "held RESET must not fetch vectors or loop");
        }

        cpu.IsInstructionBoundary.Should().BeFalse();
        cpu.Signals = M6809Signals.None;
        ProcessorCycle vectorHigh = cpu.NextCycle();
        ProcessorCycle vectorLow = cpu.NextCycle();

        vectorHigh.Operation.Should().Be(BusOperation.Read);
        vectorHigh.Address.Should().Be(0xFFFE);
        vectorLow.Operation.Should().Be(BusOperation.Read);
        vectorLow.Address.Should().Be(0xFFFF);
        cpu.IsInstructionBoundary.Should().BeTrue();
        cpu.Registers.PC.Should().Be(0x2000);
        cpu.Registers.D.Should().Be(0x0709);
    }

    /// <summary>
    ///  An extended store spends its internal cycle before the final write.
    /// </summary>
    [TestMethod]
    public void ExtendedStorePlacesWriteOnFinalCycle()
    {
        M6809Processor<RamBus> cpu = Create(0xB7, 0x12, 0x34);
        cpu.Registers = new() { A = 0x5A };
        List<ProcessorCycle> cycles = Cycles(cpu);

        cycles.Should().HaveCount(5);
        cycles[0].IsOpcodeFetch.Should().BeTrue();
        cycles[0].Address.Should().Be(0);
        cycles[1].Address.Should().Be(1);
        cycles[2].Address.Should().Be(2);
        cycles[3].Operation.Should().Be(BusOperation.None);
        cycles[4].Operation.Should().Be(BusOperation.Write);
        cycles[4].Address.Should().Be(0x1234);
        cycles[4].Value.Should().Be(0x5A);
        cpu.Bus.Memory[0x1234].Should().Be(0x5A);
    }

    /// <summary>
    ///  Extended data reads and word stores place their bus transfers at the end of the sequence.
    /// </summary>
    [TestMethod]
    public void ExtendedTransfersPlaceAccessesOnFinalCycles()
    {
        M6809Processor<RamBus> load = Create(0xB6, 0x12, 0x34);
        load.Bus.Memory[0x1234] = 0xA7;
        List<ProcessorCycle> loadCycles = Cycles(load);

        loadCycles.Should().HaveCount(5);
        loadCycles[^1].Operation.Should().Be(BusOperation.Read);
        loadCycles[^1].Address.Should().Be(0x1234);
        load.Registers.A.Should().Be(0xA7);

        M6809Processor<RamBus> store = Create(0xFD, 0x12, 0x34);
        store.Registers = new() { D = 0xBEEF };
        List<ProcessorCycle> storeCycles = Cycles(store);

        storeCycles.Should().HaveCount(6);
        storeCycles[4].Operation.Should().Be(BusOperation.Write);
        storeCycles[4].Address.Should().Be(0x1234);
        storeCycles[4].Value.Should().Be(0xBE);
        storeCycles[5].Operation.Should().Be(BusOperation.Write);
        storeCycles[5].Address.Should().Be(0x1235);
        storeCycles[5].Value.Should().Be(0xEF);
    }

    /// <summary>
    ///  Direct read-modify-write and direct TST place the operand read on cycle 4, followed by two cycles.
    /// </summary>
    [TestMethod]
    public void DirectIncrementAndTestPlaceOperandReadOnCycleFour()
    {
        M6809Processor<RamBus> inc = Create(0x0C, 0x80);
        inc.Bus.Memory[0x0080] = 0x7F;
        List<ProcessorCycle> cycles = Cycles(inc);

        cycles.Should().HaveCount(6);
        cycles[0].IsOpcodeFetch.Should().BeTrue();
        cycles[1].Address.Should().Be(1);
        cycles[2].Operation.Should().Be(BusOperation.None);
        cycles[3].Operation.Should().Be(BusOperation.Read);
        cycles[3].Address.Should().Be(0x0080);
        cycles[4].Operation.Should().Be(BusOperation.None);
        cycles[5].Operation.Should().Be(BusOperation.Write);
        cycles[5].Address.Should().Be(0x0080);
        cycles[5].Value.Should().Be(0x80);

        M6809Processor<RamBus> tst = Create(0x0D, 0x80);
        tst.Bus.Memory[0x0080] = 0x80;
        List<ProcessorCycle> tstCycles = Cycles(tst);

        tstCycles.Should().HaveCount(6);
        tstCycles[3].Operation.Should().Be(BusOperation.Read);
        tstCycles[3].Address.Should().Be(0x0080);
        tstCycles[4].Operation.Should().Be(BusOperation.None);
        tstCycles[5].Operation.Should().Be(BusOperation.None);
        tst.Registers.Flags.Should().HaveFlag(M6809ConditionCode.Negative);
    }

    /// <summary>
    ///  Indexed indirect modes spend base computation cycles before reading the pointer, then one internal cycle
    ///  before accessing the target.
    /// </summary>
    [TestMethod]
    public void IndexedIndirectModesPlaceInternalCyclesAroundPointerReads()
    {
        // LDA [,X] (7 cycles): op, post, 1 internal, ptr hi, ptr lo, 1 internal, data read.
        M6809Processor<RamBus> noOffset = Create(0xA6, 0x94);
        noOffset.Registers = new() { X = 0x1000 };
        noOffset.Bus.Memory[0x1000] = 0x20;
        noOffset.Bus.Memory[0x1001] = 0x00;
        noOffset.Bus.Memory[0x2000] = 0xA5;
        List<ProcessorCycle> cycles = Cycles(noOffset);

        cycles.Should().HaveCount(7);
        cycles[2].Operation.Should().Be(BusOperation.None);
        cycles[3].Operation.Should().Be(BusOperation.Read);
        cycles[3].Address.Should().Be(0x1000);
        cycles[4].Operation.Should().Be(BusOperation.Read);
        cycles[4].Address.Should().Be(0x1001);
        cycles[5].Operation.Should().Be(BusOperation.None);
        cycles[6].Operation.Should().Be(BusOperation.Read);
        cycles[6].Address.Should().Be(0x2000);
        noOffset.Registers.A.Should().Be(0xA5);

        // LDA [$1234] (9 cycles): op, $9F, $12, $34, 1 internal, ptr hi, ptr lo, 1 internal, data read.
        M6809Processor<RamBus> extendedIndirect = Create(0xA6, 0x9F, 0x12, 0x34);
        extendedIndirect.Bus.Memory[0x1234] = 0x30;
        extendedIndirect.Bus.Memory[0x1235] = 0x00;
        extendedIndirect.Bus.Memory[0x3000] = 0x5C;
        List<ProcessorCycle> extCycles = Cycles(extendedIndirect);

        extCycles.Should().HaveCount(9);
        extCycles[4].Operation.Should().Be(BusOperation.None);
        extCycles[5].Operation.Should().Be(BusOperation.Read);
        extCycles[5].Address.Should().Be(0x1234);
        extCycles[6].Operation.Should().Be(BusOperation.Read);
        extCycles[6].Address.Should().Be(0x1235);
        extCycles[7].Operation.Should().Be(BusOperation.None);
        extCycles[8].Operation.Should().Be(BusOperation.Read);
        extCycles[8].Address.Should().Be(0x3000);
        extendedIndirect.Registers.A.Should().Be(0x5C);

        // LDA [,X++] (10 cycles): op, post, 4 internal, ptr hi, ptr lo, 1 internal, data read.
        M6809Processor<RamBus> autoInc = Create(0xA6, 0x91);
        autoInc.Registers = new() { X = 0x1000 };
        autoInc.Bus.Memory[0x1000] = 0x20;
        autoInc.Bus.Memory[0x1001] = 0x00;
        autoInc.Bus.Memory[0x2000] = 0x7E;
        List<ProcessorCycle> autoCycles = Cycles(autoInc);

        autoCycles.Should().HaveCount(10);
        autoCycles[5].Operation.Should().Be(BusOperation.None);
        autoCycles[6].Operation.Should().Be(BusOperation.Read);
        autoCycles[6].Address.Should().Be(0x1000);
        autoCycles[7].Operation.Should().Be(BusOperation.Read);
        autoCycles[7].Address.Should().Be(0x1001);
        autoCycles[8].Operation.Should().Be(BusOperation.None);
        autoCycles[9].Operation.Should().Be(BusOperation.Read);
        autoCycles[9].Address.Should().Be(0x2000);
        autoInc.Registers.X.Should().Be(0x1002);
        autoInc.Registers.A.Should().Be(0x7E);
    }

    /// <summary>
    ///  PSHS places writes at the end of the sequence; PULS and RTS end with Motorola's trailing internal cycle.
    /// </summary>
    [TestMethod]
    public void StackPushPullAndRtsMatchMotorolaBusCycles()
    {
        M6809Processor<RamBus> push = Create(0x34, 0x03);
        push.Registers = new() { A = 0x44, CC = 0x20, S = 0x2000 };
        List<ProcessorCycle> pushCycles = Cycles(push);

        pushCycles.Should().HaveCount(7);
        pushCycles[2].Operation.Should().Be(BusOperation.None);
        pushCycles[3].Operation.Should().Be(BusOperation.None);
        pushCycles[4].Operation.Should().Be(BusOperation.None);
        pushCycles[5].Operation.Should().Be(BusOperation.Write);
        pushCycles[5].Address.Should().Be(0x1FFF);
        pushCycles[5].Value.Should().Be(0x44);
        pushCycles[6].Operation.Should().Be(BusOperation.Write);
        pushCycles[6].Address.Should().Be(0x1FFE);
        pushCycles[6].Value.Should().Be(0x20);

        M6809Processor<RamBus> pull = Create(0x35, 0x03);
        pull.Registers = new() { S = 0x1FFE };
        pull.Bus.Memory[0x1FFE] = 0x20;
        pull.Bus.Memory[0x1FFF] = 0x44;
        List<ProcessorCycle> pullCycles = Cycles(pull);

        pullCycles.Should().HaveCount(7);
        pullCycles[2].Operation.Should().Be(BusOperation.None);
        pullCycles[3].Operation.Should().Be(BusOperation.None);
        pullCycles[4].Operation.Should().Be(BusOperation.Read);
        pullCycles[4].Address.Should().Be(0x1FFE);
        pullCycles[5].Operation.Should().Be(BusOperation.Read);
        pullCycles[5].Address.Should().Be(0x1FFF);
        pullCycles[6].Operation.Should().Be(BusOperation.None);
        pull.Registers.A.Should().Be(0x44);
        pull.Registers.S.Should().Be(0x2000);

        M6809Processor<RamBus> rts = Create(0x39);
        rts.Registers = new() { S = 0x1FFE };
        rts.Bus.Memory[0x1FFE] = 0x34;
        rts.Bus.Memory[0x1FFF] = 0x56;
        List<ProcessorCycle> rtsCycles = Cycles(rts);

        rtsCycles.Should().HaveCount(5);
        rtsCycles[1].Operation.Should().Be(BusOperation.None);
        rtsCycles[2].Operation.Should().Be(BusOperation.Read);
        rtsCycles[2].Address.Should().Be(0x1FFE);
        rtsCycles[3].Operation.Should().Be(BusOperation.Read);
        rtsCycles[3].Address.Should().Be(0x1FFF);
        rtsCycles[4].Operation.Should().Be(BusOperation.None);
        rts.Registers.PC.Should().Be(0x3456);
    }

    /// <summary>
    ///  SWI stacks its 12-byte frame on cycles 4-15, idles on cycle 16, reads its vector on cycles 17-18, and
    ///  completes on cycle 19.
    /// </summary>
    [TestMethod]
    public void SoftwareInterruptPlacesStackAndVectorBusCycles()
    {
        M6809Processor<RamBus> cpu = Create(0x3F);
        cpu.Registers = new() { S = 0x1000 };
        cpu.Bus.Memory[0xFFFA] = 0x30;
        cpu.Bus.Memory[0xFFFB] = 0x00;
        List<ProcessorCycle> cycles = Cycles(cpu);

        cycles.Should().HaveCount(19);
        cycles[1].Operation.Should().Be(BusOperation.None);
        cycles[2].Operation.Should().Be(BusOperation.None);
        cycles[3].Operation.Should().Be(BusOperation.Write);
        cycles[3].Address.Should().Be(0x0FFF);
        cycles[14].Operation.Should().Be(BusOperation.Write);
        cycles[14].Address.Should().Be(0x0FF4);
        cycles[15].Operation.Should().Be(BusOperation.None);
        cycles[16].Operation.Should().Be(BusOperation.Read);
        cycles[16].Address.Should().Be(0xFFFA);
        cycles[17].Operation.Should().Be(BusOperation.Read);
        cycles[17].Address.Should().Be(0xFFFB);
        cycles[18].Operation.Should().Be(BusOperation.None);
        cpu.Registers.PC.Should().Be(0x3000);
    }

    /// <summary>
    ///  IRQ and FIRQ match Motorola Figures 7 and 8 cycle-by-cycle stack and vector bus positions.
    /// </summary>
    [TestMethod]
    public void IrqAndFirqPlaceFrameAndVectorBusCycles()
    {
        M6809Processor<RamBus> irq = Create();
        irq.Bus.Memory[0x0200] = 0x12;
        irq.Bus.Memory[0xFFF8] = 0x30;
        irq.Bus.Memory[0xFFF9] = 0x00;
        irq.Registers = new() { PC = 0x0200, S = 0x1000 };
        irq.StepInstruction();
        irq.Signals = M6809Signals.InterruptRequest;
        List<ProcessorCycle> irqCycles = Cycles(irq);

        irqCycles.Should().HaveCount(19);
        irqCycles[2].Operation.Should().Be(BusOperation.None);
        irqCycles[3].Operation.Should().Be(BusOperation.Write);
        irqCycles[3].Address.Should().Be(0x0FFF);
        irqCycles[14].Operation.Should().Be(BusOperation.Write);
        irqCycles[14].Address.Should().Be(0x0FF4);
        irqCycles[15].Operation.Should().Be(BusOperation.None);
        irqCycles[16].Operation.Should().Be(BusOperation.Read);
        irqCycles[16].Address.Should().Be(0xFFF8);
        irqCycles[17].Address.Should().Be(0xFFF9);
        irqCycles[18].Operation.Should().Be(BusOperation.None);
        irq.Registers.PC.Should().Be(0x3000);
        irq.Registers.S.Should().Be(0x0FF4);
        irq.Bus.Memory[0x0FF4].Should().Be(0x80);
        irq.Bus.Memory[0x0FFE].Should().Be(0x02);
        irq.Bus.Memory[0x0FFF].Should().Be(0x01);

        M6809Processor<RamBus> firq = Create();
        firq.Bus.Memory[0x0200] = 0x12;
        firq.Bus.Memory[0xFFF6] = 0x31;
        firq.Bus.Memory[0xFFF7] = 0x00;
        firq.Registers = new() { PC = 0x0200, S = 0x1000 };
        firq.StepInstruction();
        firq.Signals = M6809Signals.FastInterruptRequest;
        List<ProcessorCycle> firqCycles = Cycles(firq);

        firqCycles.Should().HaveCount(10);
        firqCycles[2].Operation.Should().Be(BusOperation.None);
        firqCycles[3].Operation.Should().Be(BusOperation.Write);
        firqCycles[3].Address.Should().Be(0x0FFF);
        firqCycles[5].Operation.Should().Be(BusOperation.Write);
        firqCycles[5].Address.Should().Be(0x0FFD);
        firqCycles[6].Operation.Should().Be(BusOperation.None);
        firqCycles[7].Operation.Should().Be(BusOperation.Read);
        firqCycles[7].Address.Should().Be(0xFFF6);
        firqCycles[8].Address.Should().Be(0xFFF7);
        firqCycles[9].Operation.Should().Be(BusOperation.None);
        (firq.Bus.Memory[0x0FFD] & 0x80).Should().Be(0);
    }

    /// <summary>
    ///  RTI pulls CC on cycle 3, reads the remaining frame, and ends with one internal cycle.
    /// </summary>
    [TestMethod]
    public void RtiPlacesFullFrameReadsAndTrailingInternalCycle()
    {
        M6809Processor<RamBus> cpu = Create(0x3B);
        cpu.Registers = new() { S = 0x1000 };
        cpu.Bus.Memory[0x1000] = 0x80;
        cpu.Bus.Memory[0x1001] = 0x11;
        cpu.Bus.Memory[0x1002] = 0x22;
        cpu.Bus.Memory[0x1003] = 0x33;
        cpu.Bus.Memory[0x1004] = 0x44;
        cpu.Bus.Memory[0x1005] = 0x55;
        cpu.Bus.Memory[0x1006] = 0x66;
        cpu.Bus.Memory[0x1007] = 0x77;
        cpu.Bus.Memory[0x1008] = 0x88;
        cpu.Bus.Memory[0x1009] = 0x99;
        cpu.Bus.Memory[0x100A] = 0x30;
        cpu.Bus.Memory[0x100B] = 0x00;
        List<ProcessorCycle> cycles = Cycles(cpu);

        cycles.Should().HaveCount(15);
        cycles[1].Operation.Should().Be(BusOperation.None);
        cycles[2].Operation.Should().Be(BusOperation.Read);
        cycles[2].Address.Should().Be(0x1000);
        cycles[13].Operation.Should().Be(BusOperation.Read);
        cycles[13].Address.Should().Be(0x100B);
        cycles[14].Operation.Should().Be(BusOperation.None);
        cpu.Registers.PC.Should().Be(0x3000);
        cpu.Registers.S.Should().Be(0x100C);
    }

    /// <summary>
    ///  SYNC and CWAI complete all instruction cycles before waiting, and CWAI wake-up places vector reads at
    ///  cycles 5 and 6 of its 7-cycle entry.
    /// </summary>
    [TestMethod]
    public void SyncAndCwaiWaitAtInstructionBoundaryAndResumeCleanly()
    {
        // SYNC ($13, 4 cycles) followed by NOP ($12, 2 cycles) with IRQ masked.
        M6809Processor<RamBus> sync = Create(0x13, 0x12);
        ProcessorExecutionResult syncWait = sync.StepInstruction();
        syncWait.Status.Should().Be(ProcessorExecutionStatus.Waiting);
        syncWait.Cycles.Should().Be(4);
        sync.IsInstructionBoundary.Should().BeTrue();
        sync.Status.Should().Be(ProcessorExecutionStatus.Waiting);

        sync.StepInstruction().Cycles.Should().Be(0);
        sync.Run(5).Status.Should().Be(ProcessorExecutionStatus.Waiting);
        sync.CycleCount.Should().Be(9);

        // Masked IRQ wakes SYNC without vectoring and executes the following NOP.
        sync.Signals = M6809Signals.InterruptRequest;
        ProcessorExecutionResult woke = sync.StepInstruction();
        woke.Status.Should().Be(ProcessorExecutionStatus.InstructionComplete);
        woke.Cycles.Should().Be(3, "1 bus re-enable cycle plus 2-cycle NOP");
        sync.Registers.PC.Should().Be(2);

        // CWAI #$EF ($3C $EF, 20 cycles): clears I, stacks frame, waits, then vectors in 7 cycles on IRQ.
        M6809Processor<RamBus> cwai = Create(0x3C, 0xEF);
        cwai.Registers = new() { S = 0x1000, CC = 0x50 };
        cwai.Bus.Memory[0xFFF8] = 0x40;
        cwai.Bus.Memory[0xFFF9] = 0x00;

        ProcessorExecutionResult cwaiWait = cwai.StepInstruction();
        cwaiWait.Status.Should().Be(ProcessorExecutionStatus.Waiting);
        cwaiWait.Cycles.Should().Be(20);
        cwai.Registers.S.Should().Be(0x0FF4);

        cwai.Signals = M6809Signals.InterruptRequest;
        List<ProcessorCycle> wakeCycles = Cycles(cwai);
        wakeCycles.Should().HaveCount(7);
        wakeCycles[3].Operation.Should().Be(BusOperation.None);
        wakeCycles[4].Operation.Should().Be(BusOperation.Read);
        wakeCycles[4].Address.Should().Be(0xFFF8);
        wakeCycles[5].Operation.Should().Be(BusOperation.Read);
        wakeCycles[5].Address.Should().Be(0xFFF9);
        wakeCycles[6].Operation.Should().Be(BusOperation.None);
        cwai.Registers.PC.Should().Be(0x4000);
    }

    /// <summary>
    ///  Every instruction that writes S (LDS, LEAS, TFR, EXG, PULU) and <see cref="M6809Registers.NmiArmed"/>
    ///  arm non-maskable interrupt edge detection.
    /// </summary>
    /// <param name="armingInstruction">Encoded instruction that loads S with <c>$1000</c>.</param>
    [TestMethod]
    [DataRow(new byte[] { 0x10, 0xCE, 0x10, 0x00 })] // LDS #$1000
    [DataRow(new byte[] { 0x32, 0x89, 0x10, 0x00 })] // LEAS $1000,X (with X=0)
    [DataRow(new byte[] { 0x1F, 0x04 })]             // TFR D,S
    [DataRow(new byte[] { 0x1E, 0x04 })]             // EXG D,S
    [DataRow(new byte[] { 0x37, 0x40 })]             // PULU S
    public void AllSystemStackLoadsArmNonMaskableInterrupt(byte[] armingInstruction)
    {
        M6809Processor<RamBus> cpu = Create([0x12, .. armingInstruction, 0x12]);
        cpu.Bus.Memory[0x2000] = 0x10;
        cpu.Bus.Memory[0x2001] = 0x00;
        cpu.Bus.Memory[0xFFFC] = 0x30;
        cpu.Bus.Memory[0xFFFD] = 0x00;
        cpu.Registers = new() { D = 0x1000, U = 0x2000 };

        // Rising edge before S is loaded is ignored.
        cpu.Signals = M6809Signals.NonMaskableInterrupt;
        cpu.StepInstruction();
        cpu.Registers.NmiArmed.Should().BeFalse();

        // Execute the S-writing instruction.
        cpu.StepInstruction();
        cpu.Registers.NmiArmed.Should().BeTrue();
        cpu.Registers.S.Should().Be(0x1000);

        // Next NMI rising edge vectors to $3000.
        cpu.Signals = M6809Signals.None;
        cpu.StepInstruction();
        cpu.Signals = M6809Signals.NonMaskableInterrupt;
        cpu.StepInstruction().Cycles.Should().Be(19);
        cpu.Registers.PC.Should().Be(0x3000);
    }

    /// <summary>
    ///  Snapshots taken mid-instruction resume to the identical per-cycle bus trace and final state, and
    ///  neither stepping nor snapshotting allocates on the managed heap.
    /// </summary>
    [TestMethod]
    public void SnapshotsResumeMidInstructionAndSteppingDoesNotAllocate()
    {
        // LDX #$2000 / INC $05,X / PSHS D,X
        M6809Processor<RamBus> cpu = Create(0x8E, 0x20, 0x00, 0x6C, 0x05, 0x34, 0x16, 0x12);
        cpu.Registers = new() { D = 0xABCD, S = 0x3000 };
        cpu.Bus.Memory[0x2005] = 0x41;

        cpu.StepInstruction();
        cpu.StepCycle();
        cpu.StepCycle();
        cpu.StepCycle();

        M6809Snapshot middle = cpu.CaptureState();
        List<ProcessorCycle> first = [.. Enumerable.Range(0, 15).Select(_ => cpu.NextCycle())];
        M6809Registers finalRegisters = cpu.Registers;

        cpu.Bus.Memory[0x2005] = 0x41;
        cpu.RestoreState(middle);
        List<ProcessorCycle> second = [.. Enumerable.Range(0, 15).Select(_ => cpu.NextCycle())];

        second.Should().Equal(first);
        cpu.Registers.Should().Be(finalRegisters);
        cpu.Bus.Memory[0x2005].Should().Be(0x42);

        // Warmed allocation check: StepCycle and CaptureState/RestoreState allocate 0 bytes.
        void StepAndSnapshot()
        {
            cpu.RestoreState(middle);
            cpu.Bus.Memory[0x2005] = 0x41;
            for (int index = 0; index < 15; index++)
            {
                cpu.StepCycle();
            }

            _ = cpu.CaptureState();
        }

        StepAndSnapshot();
        Allocations.During(StepAndSnapshot).Should().Be(0);
    }

    /// <summary>
    ///  Reserved indirect auto-indexing postbytes and undocumented opcodes execute without throwing exceptions.
    /// </summary>
    [TestMethod]
    public void ReservedPostbytesAndUndefinedOpcodesNeverThrow()
    {
        // $A6 $90 (LDA [,X+]), $A6 $92 (LDA [,-X]), $01 $87 (NEG <$87), $10 $12 and $11 $12 (NOP after a prefix).
        M6809Processor<RamBus> cpu = Create(0xA6, 0x90, 0xA6, 0x92, 0x01, 0x87, 0x10, 0x12, 0x11, 0x12);
        cpu.Registers = new() { X = 0x1000 };

        for (int instruction = 0; instruction < 6; instruction++)
        {
            ProcessorExecutionResult result = cpu.StepInstruction();
            result.Status.Should().Be(ProcessorExecutionStatus.InstructionComplete);
        }
    }

    /// <summary>
    ///  M6809TestBus fires timer delay 0 immediately after the write cycle and delay 1 one clock later.
    /// </summary>
    [TestMethod]
    public void TestBusDistinguishesZeroAndOneCycleTimerDelays()
    {
        static ulong CyclesBeforeIrq(byte delayLow)
        {
            M6809TestBus bus = new();
            // $0000: LDA #1 / STA $FF01 / CLRA / STA $FF02 / LDA #delay / STA $FF03 / NOP / NOP / NOP
            byte[] code = [0x86, 0x01, 0xB7, 0xFF, 0x01, 0x4F, 0xB7, 0xFF, 0x02, 0x86, delayLow, 0xB7, 0xFF, 0x03, 0x12, 0x12, 0x12];
            code.CopyTo(bus.Memory, 0);
            M6809Processor<M6809TestBus> cpu = new(bus);
            bus.CycleCount = () => cpu.CycleCount;
            bus.SetSignals = signals => cpu.Signals = signals;

            while (true)
            {
                bus.AdvanceTo(cpu.CycleCount);
                if (cpu.Signals != M6809Signals.None)
                {
                    return cpu.CycleCount;
                }

                cpu.StepCycle();
            }
        }

        ulong zero = CyclesBeforeIrq(0);
        ulong one = CyclesBeforeIrq(1);
        one.Should().Be(zero + 1);
    }

    /// <summary>
    ///  <see cref="ICpuDebugView"/> reads and writes every architectural MC6809 register by ISA name.
    /// </summary>
    [TestMethod]
    public void DebugViewReadsAndWritesRegisters()
    {
        M6809Processor<RamBus> cpu = Create(0x12);
        ICpuDebugView view = cpu;

        view.InstructionSet.Name.Should().Be("M6809");
        view.TrySetRegister("D", 0x1234).Should().BeTrue();
        view.TryGetRegister("a", out int a).Should().BeTrue();
        view.TryGetRegister("b", out int b).Should().BeTrue();
        a.Should().Be(0x12);
        b.Should().Be(0x34);

        view.TrySetRegister("S", 0x2000).Should().BeTrue();
        cpu.Registers.NmiArmed.Should().BeTrue();
        view.StackAddress.Should().Be(0x2000);

        view.TryGetRegister("HL", out _).Should().BeFalse();
        Action outOfRange = () => view.TrySetRegister("DP", 0x100);
        outOfRange.Should().Throw<ArgumentOutOfRangeException>();
    }

    private static M6809Processor<RamBus> Create(params byte[] program)
    {
        byte[] memory = new byte[0x10000];
        program.CopyTo(memory, 0);
        return new(new RamBus(memory));
    }

    private static List<ProcessorCycle> Cycles(M6809Processor<RamBus> cpu)
    {
        List<ProcessorCycle> cycles = [cpu.NextCycle()];
        while (!cpu.IsInstructionBoundary)
        {
            cycles.Add(cpu.NextCycle());
        }

        return cycles;
    }
}
