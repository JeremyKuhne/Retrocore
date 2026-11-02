// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

/// <summary>
///  The control-flow effect of a decoded instruction, independent of live register state.
/// </summary>
public enum DisassemblyFlow : byte
{
    /// <summary>
    ///  Continues at the next instruction.
    /// </summary>
    Next,

    /// <summary>
    ///  May branch to a statically known target.
    /// </summary>
    ConditionalBranch,

    /// <summary>
    ///  Transfers to a statically known target without falling through.
    /// </summary>
    Jump,

    /// <summary>
    ///  Calls a statically known target and may return.
    /// </summary>
    Call,

    /// <summary>
    ///  Transfers through a pointer that is not dereferenced by the disassembler.
    /// </summary>
    IndirectJump,

    /// <summary>
    ///  Returns from a subroutine or interrupt.
    /// </summary>
    Return,

    /// <summary>
    ///  Enters the software-interrupt handler.
    /// </summary>
    Break,

    /// <summary>
    ///  Waits for an interrupt and can subsequently continue.
    /// </summary>
    Wait,

    /// <summary>
    ///  Stops until reset.
    /// </summary>
    Stop
}
