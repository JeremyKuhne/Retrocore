// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Basic;

/// <summary>
///  A reserved word, line number, variable or function in BASIC text, as the interpreter reads it.
/// </summary>
/// <param name="Kind">What it is.</param>
/// <param name="Line">The zero-based line of the text.</param>
/// <param name="Start">The column it starts at.</param>
/// <param name="End">The column past its end.</param>
/// <param name="Text">The text as written.</param>
public readonly record struct BasicSite(BasicSiteKind Kind, int Line, int Start, int End, string Text)
{
    /// <summary>
    ///  Gets the token of a reserved word; for a two-byte token, such as Business BASIC's $FF and a second-list
    ///  token, the last byte.
    /// </summary>
    public byte Token { get; init; }

    /// <summary>
    ///  Gets a reserved word as the dialect spells it, such as <c>THEN</c>, or empty for other sites.
    /// </summary>
    public string Word { get; init; } = "";

    /// <summary>
    ///  Gets the line number of a line or a reference to one.
    /// </summary>
    public int Number { get; init; }

    /// <summary>
    ///  Gets the reserved word a line reference follows, such as <c>GOSUB</c>.
    /// </summary>
    public string? Via { get; init; }

    /// <summary>
    ///  Gets what identifies a variable or function to BASIC. Names with the same key are the same variable.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   In the Microsoft BASICs it is the first two characters, the type and whether it is an array, such as
    ///   <c>SC$(</c>. Integer BASIC keeps the whole name and one variable for it, so <c>A</c> and <c>A(3)</c> are one
    ///   array, and <c>A$</c> and <c>A$(2,5)</c> one string.
    ///  </para>
    /// </remarks>
    public string Key { get; init; } = "";

    /// <summary>
    ///  Gets whether a variable is followed by a parenthesis: an array element or, in Integer BASIC, a substring.
    /// </summary>
    public bool Subscripted { get; init; }

    /// <summary>
    ///  Gets the name as BASIC stores it, letters and digits uppercase, with its type suffix.
    /// </summary>
    public string Name { get; init; } = "";

    /// <summary>
    ///  Tests whether the site covers a column.
    /// </summary>
    /// <param name="column">The column.</param>
    /// <returns>Whether the column is in the site, or just past it.</returns>
    public bool Contains(int column) => column >= Start && column <= End;
}
