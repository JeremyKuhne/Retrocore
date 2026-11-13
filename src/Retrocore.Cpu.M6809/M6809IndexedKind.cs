// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Cpu.M6809;

/// <summary>
///  How an MC6809 indexed operand computes its postbyte and trailing bytes.
/// </summary>
internal enum M6809IndexedKind : byte
{
    /// <summary>
    ///  A fixed single-byte postbyte with no expression: <c>,R</c>, <c>,R+</c>, <c>,R++</c>, <c>,-R</c>,
    ///  <c>,--R</c>, <c>A,R</c>, <c>B,R</c>, <c>D,R</c>, and their indirect forms.
    /// </summary>
    Fixed,

    /// <summary>
    ///  A constant offset from <c>X</c>, <c>Y</c>, <c>U</c> or <c>S</c>: 5-bit, 8-bit or 16-bit.
    /// </summary>
    RegisterOffset,

    /// <summary>
    ///  A PC-relative target (<c>,PCR</c> or <c>,PC</c>): 8-bit or 16-bit signed displacement.
    /// </summary>
    ProgramCounterRelative,

    /// <summary>
    ///  Extended indirect (<c>[expr]</c>): postbyte <c>$9F</c> followed by a 16-bit big-endian address.
    /// </summary>
    ExtendedIndirect
}
