// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Cpu.M6809;

/// <summary>
///  Complete internal MC6809 state, excluding the external bus, stored as a flat value type for allocation-free
///  snapshots.
/// </summary>
internal struct M6809ExecutionState
{
    /// <summary>
    ///  Current architectural registers.
    /// </summary>
    internal M6809Registers Registers;

    /// <summary>
    ///  Total elapsed clock cycles.
    /// </summary>
    internal ulong CycleCount;

    /// <summary>
    ///  Address latch for effective-address resolution, 16-bit operands or interrupt vectors.
    /// </summary>
    internal ushort Effective;

    /// <summary>
    ///  Address placed on the bus during the most recent cycle.
    /// </summary>
    internal ushort Bus;

    /// <summary>
    ///  Current and previously sampled input assertions.
    /// </summary>
    internal M6809Signals Signals;

    /// <summary>
    ///  Signals sampled on the previous cycle, for edge detection.
    /// </summary>
    internal M6809Signals PreviousSignals;

    /// <summary>
    ///  Current execution status.
    /// </summary>
    internal ProcessorExecutionStatus Status;

    /// <summary>
    ///  Bus operation performed on the most recent cycle.
    /// </summary>
    internal BusOperation Activity;

    /// <summary>
    ///  Byte transferred on the most recent bus cycle.
    /// </summary>
    internal byte Value;

    /// <summary>
    ///  Whether the most recent cycle fetched the first opcode byte of an instruction.
    /// </summary>
    internal bool OpcodeFetch;

    /// <summary>
    ///  Whether an NMI rising edge has been latched.
    /// </summary>
    internal bool PendingNmi;

    /// <summary>
    ///  Whether HALT was asserted as the previous cycle began; an instruction stops at its end only for a HALT
    ///  asserted before its last cycle.
    /// </summary>
    internal bool HaltSampled;

    /// <summary>
    ///  Whether an interrupt entry sequence already stacked registers via <c>CWAI</c>.
    /// </summary>
    internal bool InterruptPrestacked;

    /// <summary>
    ///  Whether the active indexed addressing mode requires indirection after base address computation.
    /// </summary>
    internal bool Indirect;

    /// <summary>
    ///  Active wait mode (<c>SYNC</c> or <c>CWAI</c>).
    /// </summary>
    internal M6809WaitState Wait;

    /// <summary>
    ///  Active top-level sequence (instruction, hardware interrupt, or reset).
    /// </summary>
    internal M6809Sequence Sequence;

    /// <summary>
    ///  Active effective-address resolution phase.
    /// </summary>
    internal M6809AddressPhase AddressPhase;

    /// <summary>
    ///  Active instruction family.
    /// </summary>
    internal M6809Operation Operation;

    /// <summary>
    ///  Step index within the active sequence or instruction family.
    /// </summary>
    internal byte Step;

    /// <summary>
    ///  Prefix page (<c>0</c>, <c>$10</c> or <c>$11</c>).
    /// </summary>
    internal byte Page;

    /// <summary>
    ///  Decoded opcode byte.
    /// </summary>
    internal byte Opcode;

    /// <summary>
    ///  Latched postbyte, stack mask, or interrupt kind (<c>1=NMI, 2=FIRQ, 3=IRQ</c>).
    /// </summary>
    internal byte Postbyte;

    /// <summary>
    ///  Remaining internal cycles in a delay phase, or current bit index in a stack transfer.
    /// </summary>
    internal byte Remaining;

    /// <summary>
    ///  Latched high byte of a 16-bit operand, pointer or vector.
    /// </summary>
    internal byte High;

    /// <summary>
    ///  The running instruction's group for the flags of an undocumented store immediate after it.
    /// </summary>
    internal M6809FlagGroup FlagGroup;

    /// <summary>
    ///  The running instruction's latched byte for <see cref="M6809FlagGroup.LatchedDecrement"/>.
    /// </summary>
    internal byte FlagGroupValue;

    /// <summary>
    ///  The previous instruction's <see cref="FlagGroup"/>, which an unprefixed store immediate reads.
    /// </summary>
    internal M6809FlagGroup PreviousFlagGroup;

    /// <summary>
    ///  The previous instruction's <see cref="FlagGroupValue"/>.
    /// </summary>
    internal byte PreviousFlagGroupValue;
}
