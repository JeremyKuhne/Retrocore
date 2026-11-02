// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Cpu.Z80;

/// <summary>
///  Everything the core needs to resume, including a machine cycle in progress, so snapshots restore exactly.
/// </summary>
internal struct Z80ExecutionState
{
    /// <summary>
    ///  The registers.
    /// </summary>
    internal Z80Registers Registers;

    /// <summary>
    ///  The input lines now.
    /// </summary>
    internal Z80Signals Signals;

    /// <summary>
    ///  The input lines at the previous cycle, for edges.
    /// </summary>
    internal Z80Signals PreviousSignals;

    /// <summary>
    ///  The byte a device puts on the data bus to acknowledge an interrupt.
    /// </summary>
    internal byte InterruptData;

    /// <summary>
    ///  Whether an NMI edge waits for the end of the instruction.
    /// </summary>
    internal bool PendingNmi;

    /// <summary>
    ///  Whether <c>HALT</c> holds the processor.
    /// </summary>
    internal bool Halted;

    /// <summary>
    ///  The execution status.
    /// </summary>
    internal ProcessorExecutionStatus Status;

    /// <summary>
    ///  The elapsed T-states.
    /// </summary>
    internal ulong CycleCount;

    /// <summary>
    ///  The machine cycle in progress.
    /// </summary>
    internal Z80MachineCycle Cycle;

    /// <summary>
    ///  The T-state within it.
    /// </summary>
    internal byte T;

    /// <summary>
    ///  The T-states of an internal cycle.
    /// </summary>
    internal byte Length;

    /// <summary>
    ///  The address or port of the machine cycle.
    /// </summary>
    internal ushort Address;

    /// <summary>
    ///  The byte read or to write.
    /// </summary>
    internal byte Value;

    /// <summary>
    ///  The address bus, which internal T-states hold.
    /// </summary>
    internal ushort Bus;

    /// <summary>
    ///  The instruction family in progress.
    /// </summary>
    internal Z80Operation Operation;

    /// <summary>
    ///  The step within it.
    /// </summary>
    internal byte Step;

    /// <summary>
    ///  The opcode, after any prefixes.
    /// </summary>
    internal byte Opcode;

    /// <summary>
    ///  0 for HL, 1 for IX after DD, 2 for IY after FD.
    /// </summary>
    internal byte Index;

    /// <summary>
    ///  A register index (B C D E H L - A) or pair index the instruction uses.
    /// </summary>
    internal byte Register;

    /// <summary>
    ///  A condition, ALU operation or variant the instruction uses.
    /// </summary>
    internal byte Variant;

    /// <summary>
    ///  A word the instruction builds, such as an address being read.
    /// </summary>
    internal ushort Word;

    /// <summary>
    ///  The effective address of a memory operand.
    /// </summary>
    internal ushort Effective;

    /// <summary>
    ///  Whether the instruction wrote the flags, for Q.
    /// </summary>
    internal bool FlagsWritten;

    /// <summary>
    ///  What the last T-state did on the bus, at <see cref="Bus"/> with <see cref="Value"/>.
    /// </summary>
    internal BusOperation Activity;
}
