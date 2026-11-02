// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

/// <summary>
///  The layout behavior of an emitting statement, classified once before layout passes begin.
/// </summary>
/// <remarks>
///  <para>
///   Unlike <see cref="AssemblyStatementKind"/>, this separates .byte from .word and omits metadata
///   directives, which are consumed before layout and never reach the layout array.
///  </para>
/// </remarks>
internal enum LayoutOperation : byte
{
    /// <summary>
    ///  A label-only statement.
    /// </summary>
    Label,

    /// <summary>
    ///  A named .equ constant.
    /// </summary>
    Constant,

    /// <summary>
    ///  An .org location-counter advance.
    /// </summary>
    Origin,

    /// <summary>
    ///  A .byte data list.
    /// </summary>
    Byte,

    /// <summary>
    ///  A .word data list.
    /// </summary>
    Word,

    /// <summary>
    ///  A .res reservation.
    /// </summary>
    Reserve,

    /// <summary>
    ///  An .assert check.
    /// </summary>
    Assertion,

    /// <summary>
    ///  A CPU instruction.
    /// </summary>
    Instruction,

    /// <summary>
    ///  A .hiascii data list, emitting each byte with bit 7 set as Apple II text expects.
    /// </summary>
    HighAscii,

    /// <summary>
    ///  A .section start, moving the location counter to a new fixed-size output section.
    /// </summary>
    Section,

    /// <summary>
    ///  A .dword list of 32-bit values.
    /// </summary>
    Dword,

    /// <summary>
    ///  A power-of-two alignment.
    /// </summary>
    Align,

    /// <summary>
    ///  A logical location-counter change without output padding.
    /// </summary>
    LogicalOrigin,

    /// <summary>
    ///  The start of a no-output region.
    /// </summary>
    DummyStart,

    /// <summary>
    ///  The end of a no-output region.
    /// </summary>
    DummyEnd,

    /// <summary>
    ///  An XOR checksum of preceding output bytes.
    /// </summary>
    Checksum,

    /// <summary>
    ///  A big-endian 16-bit data list.
    /// </summary>
    BigEndianWord,

    /// <summary>
    ///  A little-endian 24-bit data list.
    /// </summary>
    FarAddress
}
