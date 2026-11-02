// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Isa;

/// <summary>
///  What an operand form's first field means to the instruction.
/// </summary>
public enum OperandRole : byte
{
    /// <summary>
    ///  A value, a branch target, or nothing.
    /// </summary>
    None,

    /// <summary>
    ///  An address the instruction accesses.
    /// </summary>
    Memory,

    /// <summary>
    ///  The address of a pointer the instruction reads.
    /// </summary>
    Pointer
}
