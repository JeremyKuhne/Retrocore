// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Cpu.M6502;

/// <summary>
///  The next CPU microstep, selected at opcode fetch and preserved across stalls and snapshots.
/// </summary>
internal enum ProcessorContinuation : byte
{
    /// <summary>
    ///  No direct instruction continuation is active.
    /// </summary>
    None,

    /// <summary>
    ///  Read the immediate operand.
    /// </summary>
    Immediate,

    /// <summary>
    ///  Read a zero-page address.
    /// </summary>
    ZeroPageAddress,

    /// <summary>
    ///  Access zero-page data.
    /// </summary>
    ZeroPageData,

    /// <summary>
    ///  Read an indexed zero-page address.
    /// </summary>
    IndexedZeroPageAddress,

    /// <summary>
    ///  Perform the indexing dummy read.
    /// </summary>
    IndexedZeroPageDummy,

    /// <summary>
    ///  Access indexed zero-page data.
    /// </summary>
    IndexedZeroPageData,

    /// <summary>
    ///  Read an absolute address's low byte.
    /// </summary>
    AbsoluteLow,

    /// <summary>
    ///  Read an absolute address's high byte and apply indexing.
    /// </summary>
    AbsoluteHigh,

    /// <summary>
    ///  Access absolute data or perform the indexed dummy read.
    /// </summary>
    AbsoluteData,

    /// <summary>
    ///  Access absolute data after an extra indexing cycle.
    /// </summary>
    AbsoluteIndexedData,

    /// <summary>
    ///  Read an indexed-indirect pointer.
    /// </summary>
    IndexedIndirectPointer,

    /// <summary>
    ///  Perform the pointer indexing dummy read.
    /// </summary>
    IndexedIndirectDummy,

    /// <summary>
    ///  Read the indexed pointer's low byte.
    /// </summary>
    IndexedIndirectLow,

    /// <summary>
    ///  Read the indexed pointer's high byte.
    /// </summary>
    IndexedIndirectHigh,

    /// <summary>
    ///  Access indexed-indirect data.
    /// </summary>
    IndexedIndirectData,

    /// <summary>
    ///  Read an indirect pointer.
    /// </summary>
    IndirectPointer,

    /// <summary>
    ///  Read the indirect pointer's low byte.
    /// </summary>
    IndirectLow,

    /// <summary>
    ///  Read the indirect pointer's high byte and apply Y indexing.
    /// </summary>
    IndirectHigh,

    /// <summary>
    ///  Access indirect data or perform the Y-indexing dummy read.
    /// </summary>
    IndirectData,

    /// <summary>
    ///  Access indirect data after an extra Y-indexing cycle.
    /// </summary>
    IndirectIndexedData,

    /// <summary>
    ///  Enter a jammed, waiting, or stopped state.
    /// </summary>
    Halt,

    /// <summary>
    ///  Advance a read-modify-write or decimal tail.
    /// </summary>
    Data,

    /// <summary>
    ///  Advance a relative branch.
    /// </summary>
    Branch,

    /// <summary>
    ///  Modify the accumulator.
    /// </summary>
    Accumulator,

    /// <summary>
    ///  Advance a jump.
    /// </summary>
    Jump,

    /// <summary>
    ///  Advance a subroutine call.
    /// </summary>
    Jsr,

    /// <summary>
    ///  Advance a subroutine or interrupt return.
    /// </summary>
    Return,

    /// <summary>
    ///  Advance a software interrupt.
    /// </summary>
    Brk,

    /// <summary>
    ///  Advance a stack push.
    /// </summary>
    Push,

    /// <summary>
    ///  Advance a stack pull.
    /// </summary>
    Pull,

    /// <summary>
    ///  Execute an implied instruction.
    /// </summary>
    Implied
}
