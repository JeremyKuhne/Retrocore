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
}
