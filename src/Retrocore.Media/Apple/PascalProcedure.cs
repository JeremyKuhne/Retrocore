// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media;

/// <summary>
///  A procedure in a segment of an Apple Pascal code file, from the segment's procedure dictionary. Offsets are from
///  the start of the segment's code.
/// </summary>
/// <param name="Index">Its place in the procedure dictionary, from 1: the number calls name it by.</param>
/// <param name="Number">
///  The number its attributes give, which is its index for p-code, or 0 for an assembled (native) procedure.
/// </param>
/// <param name="LexicalLevel">Its nesting: 0 for a program's or unit's outer block, -1 for the system's.</param>
/// <param name="Attributes">Where its attributes are: the procedure number and lexical level, a word.</param>
/// <param name="Entry">Where its code starts.</param>
/// <param name="Exit">Where a p-code procedure's exit code starts; for a native procedure, its entry.</param>
/// <param name="ParameterSize">The size of a p-code procedure's parameters, in bytes.</param>
/// <param name="DataSize">The size of a p-code procedure's local variables, in bytes.</param>
/// <param name="Relocations">
///  For a native procedure, its four relocation lists, each the offsets of the words to relocate: relative to the
///  base (the interpreter's globals), to the segment, to the procedure, and to the interpreter. Empty for p-code.
/// </param>
public sealed record PascalProcedure(
    int Index,
    int Number,
    int LexicalLevel,
    int Attributes,
    int Entry,
    int Exit,
    int ParameterSize,
    int DataSize,
    IReadOnlyList<IReadOnlyList<int>> Relocations)
{
    /// <summary>
    ///  Gets whether it is assembled code for the processor rather than p-code.
    /// </summary>
    public bool IsNative => Number == 0;
}
