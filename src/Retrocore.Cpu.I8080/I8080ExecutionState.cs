// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Cpu.I8080;

/// <summary>
///  Everything the core needs to resume, including a machine cycle in progress, so snapshots restore exactly.
/// </summary>
internal struct I8080ExecutionState
{
    /// <summary>
    ///  The registers.
    /// </summary>
    internal I8080Registers Registers;

    /// <summary>
    ///  The CPU.
    /// </summary>
    internal I8080Variant Variant;

    /// <summary>
    ///  The input lines now.
    /// </summary>
    internal I8080Signals Signals;

    /// <summary>
    ///  The input lines at the previous state, for edges.
    /// </summary>
    internal I8080Signals PreviousSignals;

    /// <summary>
    ///  The opcode a device puts on the data bus to acknowledge an interrupt.
    /// </summary>
    internal byte InterruptData;

    /// <summary>
    ///  Whether a TRAP edge waits for the end of the instruction (8085).
    /// </summary>
    internal bool PendingTrap;

    /// <summary>
    ///  The RST 7.5 latch (8085).
    /// </summary>
    internal bool PendingRestart75;

    /// <summary>
    ///  IE as TRAP found it, which <c>RIM</c> reads once after a TRAP (8085).
    /// </summary>
    internal bool TrapEnable;

    /// <summary>
    ///  Whether a TRAP was taken since the last <c>RIM</c> (8085).
    /// </summary>
    internal bool AfterTrap;

    /// <summary>
    ///  Whether <c>HLT</c> holds the processor.
    /// </summary>
    internal bool Halted;

    /// <summary>
    ///  The execution status.
    /// </summary>
    internal ProcessorExecutionStatus Status;

    /// <summary>
    ///  The elapsed states.
    /// </summary>
    internal ulong CycleCount;

    /// <summary>
    ///  The machine cycle in progress.
    /// </summary>
    internal I8080MachineCycle Cycle;

    /// <summary>
    ///  The state within it.
    /// </summary>
    internal byte T;

    /// <summary>
    ///  The states of an internal cycle.
    /// </summary>
    internal byte Length;

    /// <summary>
    ///  The address or port of the machine cycle.
    /// </summary>
    internal ushort Address;

    /// <summary>
    ///  The byte the machine cycle read, or will write.
    /// </summary>
    internal byte Value;

    /// <summary>
    ///  The address bus, which idle states hold.
    /// </summary>
    internal ushort Bus;

    /// <summary>
    ///  The byte the last bus transfer moved.
    /// </summary>
    internal byte Data;

    /// <summary>
    ///  Whether the last bus transfer read an opcode.
    /// </summary>
    internal bool OpcodeTransfer;

    /// <summary>
    ///  The instruction family in progress.
    /// </summary>
    internal I8080Operation Operation;

    /// <summary>
    ///  The step within it.
    /// </summary>
    internal byte Step;

    /// <summary>
    ///  The opcode.
    /// </summary>
    internal byte Opcode;

    /// <summary>
    ///  A register index (B C D E H L - A) or pair index the instruction uses.
    /// </summary>
    internal byte Register;

    /// <summary>
    ///  A condition or ALU operation the instruction uses.
    /// </summary>
    internal byte Selector;

    /// <summary>
    ///  A word the instruction builds, such as an address being read.
    /// </summary>
    internal ushort Word;

    /// <summary>
    ///  What the last state did on the bus, at <see cref="Bus"/> with <see cref="Data"/>.
    /// </summary>
    internal BusOperation Activity;
}
