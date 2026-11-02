// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information


namespace Retrocore.Cpu.M6502;

/// <summary>
///  Complete CPU execution state, including in-flight latches but excluding the bus.
/// </summary>
internal struct ProcessorExecutionState
{
    /// <summary>
    ///  Architectural registers.
    /// </summary>
    internal ProcessorRegisters Registers;

    /// <summary>
    ///  Current input assertions.
    /// </summary>
    internal ProcessorSignals Signals;

    /// <summary>
    ///  Inputs sampled on the preceding cycle.
    /// </summary>
    internal ProcessorSignals PreviousSignals;

    /// <summary>
    ///  Whether an NMI edge is pending.
    /// </summary>
    internal bool PendingNmi;

    /// <summary>
    ///  Whether the active hardware interrupt uses the NMI vector.
    /// </summary>
    internal bool InterruptNmi;

    /// <summary>
    ///  Current microsequence.
    /// </summary>
    internal ProcessorSequence Sequence;

    /// <summary>
    ///  Current sequence phase; zero denotes an instruction boundary.
    /// </summary>
    internal byte Phase;

    /// <summary>
    ///  The decoded instruction.
    /// </summary>
    internal OpCode Instruction;

    /// <summary>
    ///  Address latch.
    /// </summary>
    internal ushort Address;

    /// <summary>
    ///  Unindexed address latch.
    /// </summary>
    internal ushort BaseAddress;

    /// <summary>
    ///  Zero-page pointer latch.
    /// </summary>
    internal byte Pointer;

    /// <summary>
    ///  Interrupt eligibility sampled before the final cycle of an instruction.
    /// </summary>
    internal bool IrqPending;

    /// <summary>
    ///  Whether interrupt polling has occurred since registers were replaced.
    /// </summary>
    internal bool IrqPolled;

    /// <summary>
    ///  The interrupt mask before executing the current instruction.
    /// </summary>
    internal bool InterruptMasked;

    /// <summary>
    ///  Data latch.
    /// </summary>
    internal byte Data;

    /// <summary>
    ///  Current execution or halt status.
    /// </summary>
    internal ProcessorExecutionStatus Status;

    /// <summary>
    ///  Total elapsed CPU cycles.
    /// </summary>
    internal ulong CycleCount;

    /// <summary>
    ///  Metadata for the most recent cycle.
    /// </summary>
    internal ProcessorCycle LastCycle;
}
