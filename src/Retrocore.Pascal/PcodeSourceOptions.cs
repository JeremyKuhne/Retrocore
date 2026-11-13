// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

/// <summary>
///  What <see cref="PcodeSourceWriter"/> names a code file's parts from.
/// </summary>
/// <remarks>
///  <para>
///   Names and comments are keyed as <c>pascal</c> breakpoints name code: <c>SEGMENT</c> for a segment,
///   <c>SEGMENT.N</c> for its procedure N, and <c>SEGMENT.N+$OFFSET</c> for a place in it, the offset from the
///   procedure's entry (hexadecimal with <c>$</c>, or decimal). A segment is named as its dictionary names it, in any
///   case.
///  </para>
/// </remarks>
public sealed record PcodeSourceOptions
{
    /// <summary>
    ///  Gets the include that defines the p-code macros, as <c>.include</c> names it.
    /// </summary>
    public string Include { get; init; } = "<Pascal/Pcode.asm>";

    /// <summary>
    ///  Gets the library whose units the code file calls, such as <c>SYSTEM.LIBRARY</c>, to name their procedures.
    /// </summary>
    public PascalLibrary? Library { get; init; }

    /// <summary>
    ///  Gets the compiler's listing of the program, to name its segments, procedures and variables and to show each
    ///  statement's source line above its p-code.
    /// </summary>
    public PascalListing? Listing { get; init; }

    /// <summary>
    ///  Gets names to give, by key: a segment's or procedure's scope, or a label.
    /// </summary>
    public IReadOnlyDictionary<string, string> Names { get; init; } = new Dictionary<string, string>();

    /// <summary>
    ///  Gets comments to write, by key: above a segment's or procedure's scope, or above a place.
    /// </summary>
    public IReadOnlyDictionary<string, string> Comments { get; init; } = new Dictionary<string, string>();
}
