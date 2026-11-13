// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

/// <summary>
///  A procedure running on the p-machine: the top one, or a caller waiting for the call it made to return.
/// </summary>
/// <param name="Segment">Where its segment's last word (the segment number and procedure count) is.</param>
/// <param name="SegmentNumber">Its segment's number.</param>
/// <param name="Procedure">Its procedure number.</param>
/// <param name="LexicalLevel">Its nesting.</param>
/// <param name="JumpTable">Its attributes, JTAB.</param>
/// <param name="Code">
///  Its IPC: for the top procedure the p-code about to run, and for a caller the p-code after its call.
/// </param>
/// <param name="Entry">Where its code starts.</param>
/// <param name="Offset">Its IPC's offset from its entry, as a compiler listing counts.</param>
/// <param name="Mark">Its mark stack control word (MSCW), MP; its locals follow it.</param>
/// <param name="Words">How many words of parameters and locals it has.</param>
public sealed record PascalFrame(
    PascalPointer Segment,
    int SegmentNumber,
    int Procedure,
    int LexicalLevel,
    PascalPointer JumpTable,
    PascalPointer Code,
    PascalPointer Entry,
    int Offset,
    PascalPointer Mark,
    int Words)
{
    /// <summary>
    ///  The size of a mark stack control word: the static and dynamic links, the caller's JTAB, SEG and IPC, the
    ///  6502's stack pointer and, on the Apple III, the caller's code X-byte.
    /// </summary>
    public const int MarkSize = 12;

    /// <summary>
    ///  Gets where a local or parameter is, as <c>LDL</c> numbers it from 1.
    /// </summary>
    /// <param name="number">The number.</param>
    /// <returns>Its address.</returns>
    public PascalPointer Local(int number) => Mark.Plus(MarkSize - 2 + (number * 2));
}
