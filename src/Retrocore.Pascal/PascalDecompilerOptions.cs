// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

/// <summary>
///  What <see cref="PascalDecompiler"/> names a program's procedures and variables from, besides their offsets.
/// </summary>
/// <remarks>
///  <para>
///   Names and comments are keyed as <see cref="PcodeSourceOptions"/>'s are: <c>SEGMENT.N</c> for procedure N (1 is
///   the program, or a segment procedure), and <c>SEGMENT.N@WORD</c> for the variable or parameter at a word of its
///   frame. A name that would change what the source compiles to, as one the code's own calls use (such as
///   <c>IORESULT</c>) or one the same in its first eight letters as another in reach, is left as the decompiler names
///   it, with a warning.
///  </para>
/// </remarks>
public sealed record PascalDecompilerOptions
{
    /// <summary>
    ///  Gets the library whose units the program uses, such as <c>SYSTEM.LIBRARY</c>.
    /// </summary>
    public PascalLibrary? Library { get; init; }

    /// <summary>
    ///  Gets the compiler's listing of the program, to name its procedures and variables as its source did.
    /// </summary>
    public PascalListing? Listing { get; init; }

    /// <summary>
    ///  Gets names to give, by key: a procedure's or a variable's. They win over the listing's.
    /// </summary>
    public IReadOnlyDictionary<string, string> Names { get; init; } = new Dictionary<string, string>();

    /// <summary>
    ///  Gets comments to write above a procedure's heading, by its key.
    /// </summary>
    public IReadOnlyDictionary<string, string> Comments { get; init; } = new Dictionary<string, string>();

    /// <summary>
    ///  Gets constants to declare, by the name of the list they make: each list's names, for the values from 0, an
    ///  empty name for a value it leaves unnamed.
    /// </summary>
    public IReadOnlyDictionary<string, IReadOnlyList<string>> Constants { get; init; } =
        new Dictionary<string, IReadOnlyList<string>>();

    /// <summary>
    ///  Gets the lists of <see cref="Constants"/> whose names a variable's, field's or type's values are written by,
    ///  by its key: <c>SEGMENT.N@WORD</c> or <c>SYSTEM@WORD</c> for a variable or parameter, <c>Tn.FIELD</c> for a
    ///  field, <c>Tn</c> for a type, or a set type's elements.
    /// </summary>
    public IReadOnlyDictionary<string, string> Values { get; init; } = new Dictionary<string, string>();

    /// <summary>
    ///  Gets a value indicating whether each statement is written below the p-code it was decompiled from, in a
    ///  <c>{...}</c> comment: an IF's or a loop's test above it, and what the code has after its statements, such as a
    ///  REPEAT's test or a loop's jump back, below them.
    /// </summary>
    public bool PcodeComments { get; init; }
}
