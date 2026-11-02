// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Isa;

/// <summary>
///  How an instruction affects control flow.
/// </summary>
public enum InstructionFlow : byte
{
    /// <summary>
    ///  Execution continues with the next instruction.
    /// </summary>
    Next,

    /// <summary>
    ///  A conditional branch continues either at its target or with the next instruction.
    /// </summary>
    ConditionalBranch,

    /// <summary>
    ///  An unconditional jump to a target the instruction encodes.
    /// </summary>
    Jump,

    /// <summary>
    ///  A subroutine call that normally returns to the next instruction.
    /// </summary>
    Call,

    /// <summary>
    ///  A jump through a pointer or register.
    /// </summary>
    IndirectJump,

    /// <summary>
    ///  A subroutine or interrupt return.
    /// </summary>
    Return,

    /// <summary>
    ///  A software interrupt.
    /// </summary>
    Break,

    /// <summary>
    ///  Execution waits for an interrupt.
    /// </summary>
    Wait,

    /// <summary>
    ///  Execution stops until reset.
    /// </summary>
    Stop
}
