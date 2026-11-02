// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Basic;

/// <summary>
///  Where an interpreter keeps the pointers that lay out its memory, each the address of a two-byte word, low byte
///  first. The names in parentheses are the ROM sources'.
/// </summary>
public sealed record BasicPointers
{
    /// <summary>
    ///  Gets the pointer to the program's first line (TXTTAB).
    /// </summary>
    public required int ProgramStart { get; init; }

    /// <summary>
    ///  Gets the pointer to the simple variables, just past the program (VARTAB).
    /// </summary>
    public required int Variables { get; init; }

    /// <summary>
    ///  Gets the pointer to the arrays, just past the simple variables (ARYTAB).
    /// </summary>
    public required int Arrays { get; init; }

    /// <summary>
    ///  Gets the pointer to the first free byte, just past the arrays (STREND).
    /// </summary>
    public required int FreeStart { get; init; }

    /// <summary>
    ///  Gets the pointer to the lowest string in string space (FRETOP).
    /// </summary>
    public required int StringBottom { get; init; }

    /// <summary>
    ///  Gets the pointer to the top of the memory BASIC uses (MEMSIZ).
    /// </summary>
    public required int MemoryTop { get; init; }

    /// <summary>
    ///  Gets the current line number, with $FFFF (Level II) or a high byte of $FF (AppleSoft) in direct mode (CURLIN).
    /// </summary>
    public required int CurrentLine { get; init; }

    /// <summary>
    ///  Gets the text pointer CONT continues from; zero when it cannot (OLDTXT).
    /// </summary>
    public required int ContinueText { get; init; }

    /// <summary>
    ///  Gets the pointer to the next DATA item (DATPTR).
    /// </summary>
    public required int DataPointer { get; init; }

    /// <summary>
    ///  Gets AppleSoft's copy of the program's end, which DOS reads (PRGEND); null elsewhere.
    /// </summary>
    public int? ProgramEnd { get; init; }

    /// <summary>
    ///  Gets Level II's pointer to the bottom of string space, below which its stack grows down (STKTOP); null
    ///  elsewhere.
    /// </summary>
    public int? StackTop { get; init; }
}
