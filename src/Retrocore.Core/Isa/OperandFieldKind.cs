// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Isa;

/// <summary>
///  How an operand field is encoded.
/// </summary>
public enum OperandFieldKind : byte
{
    /// <summary>
    ///  One byte: an unsigned or signed 8-bit value.
    /// </summary>
    Byte,

    /// <summary>
    ///  A 16-bit value in the CPU's byte order.
    /// </summary>
    Word,

    /// <summary>
    ///  An 8-bit signed displacement from the end of the instruction to a target address.
    /// </summary>
    Relative8,

    /// <summary>
    ///  A 16-bit signed displacement from the end of the instruction to a target address.
    /// </summary>
    Relative16,

    /// <summary>
    ///  An 8-bit signed displacement added to an index register, such as the Z80's <c>[IX+d]</c>. Its operand
    ///  text is empty (zero) or starts with <c>+</c> or <c>-</c>, and it is formatted with its sign.
    /// </summary>
    Displacement8,

    /// <summary>
    ///  A bit number, 0-7, held in bits 3-5 of the last opcode byte, as the Z80's <c>BIT</c>, <c>SET</c> and
    ///  <c>RES</c> hold it; it takes no operand byte.
    /// </summary>
    BitNumber,

    /// <summary>
    ///  A restart address, a multiple of 8 from 0 to <c>$38</c>, held in bits 3-5 of the last opcode byte, as the
    ///  Z80's <c>RST</c> holds it; it takes no operand byte.
    /// </summary>
    Restart
}
