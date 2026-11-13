// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

/// <summary>
///  The operands that follow a p-code's opcode.
/// </summary>
/// <remarks>
///  <para>
///   A "big" number (B) is one byte when below 128, otherwise two: the first with bit 7 set holds the high bits, and
///   the second the low byte. A word (W) is least significant byte first. "DB" is a lexical level difference, a
///   byte.
///  </para>
/// </remarks>
public enum PcodeOperands
{
    /// <summary>
    ///  None.
    /// </summary>
    None,

    /// <summary>
    ///  An unsigned byte.
    /// </summary>
    Byte,

    /// <summary>
    ///  A signed byte, a jump: forward from the next p-code, or when negative an entry in the procedure's jump table.
    /// </summary>
    Jump,

    /// <summary>
    ///  A big number.
    /// </summary>
    Big,

    /// <summary>
    ///  A lexical level difference and a big number: an intermediate variable's level and offset.
    /// </summary>
    LevelBig,

    /// <summary>
    ///  A segment number byte and a big number: an intrinsic unit's variable.
    /// </summary>
    SegmentBig,

    /// <summary>
    ///  Two unsigned bytes.
    /// </summary>
    TwoBytes,

    /// <summary>
    ///  A word.
    /// </summary>
    Word,

    /// <summary>
    ///  A string constant: its length, then its characters.
    /// </summary>
    String,

    /// <summary>
    ///  A packed array constant: its length, then its bytes.
    /// </summary>
    Bytes,

    /// <summary>
    ///  A multiple-word constant: a count, then that many words from the next word boundary.
    /// </summary>
    Words,

    /// <summary>
    ///  A case jump: from the next word boundary the lowest and highest index, a two-byte <c>UJP</c> taken when the
    ///  index is outside them, then a self-relative word for each index.
    /// </summary>
    CaseJump,

    /// <summary>
    ///  A comparison's operand type: 2 real, 4 string, 6 boolean, 8 set, or 10 and 12 for byte and word arrays,
    ///  which a big number of bytes or words follows.
    /// </summary>
    Comparison,

    /// <summary>
    ///  A standard procedure's number.
    /// </summary>
    StandardProcedure
}
