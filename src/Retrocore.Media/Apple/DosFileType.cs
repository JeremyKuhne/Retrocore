// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media;

/// <summary>
///  A DOS 3.2 or 3.3 file type, as a catalog entry stores it; bit 7 of the stored byte marks a locked file.
/// </summary>
public enum DosFileType : byte
{
    /// <summary>
    ///  A text file (T): characters with bit 7 set, each line ending in a return ($8D).
    /// </summary>
    Text = 0x00,

    /// <summary>
    ///  An Integer BASIC program (I): its length, then the program.
    /// </summary>
    IntegerBasic = 0x01,

    /// <summary>
    ///  An AppleSoft program (A): its length, then the tokenized program.
    /// </summary>
    AppleSoft = 0x02,

    /// <summary>
    ///  A binary file (B): its load address and length, then the bytes.
    /// </summary>
    Binary = 0x04,

    /// <summary>
    ///  A file of type S, which DOS stores but gives no meaning.
    /// </summary>
    TypeS = 0x08,

    /// <summary>
    ///  A relocatable object file (R), as the DOS Toolkit's assembler writes.
    /// </summary>
    Relocatable = 0x10,

    /// <summary>
    ///  A file of the second type A, which DOS stores but gives no meaning.
    /// </summary>
    TypeA = 0x20,

    /// <summary>
    ///  A file of the second type B, which DOS stores but gives no meaning.
    /// </summary>
    TypeB = 0x40
}
