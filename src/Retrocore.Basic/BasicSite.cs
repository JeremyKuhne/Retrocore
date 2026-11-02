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
    ///  Gets the token of a reserved word.
    /// </summary>
    public byte Token { get; init; }

    /// <summary>
    ///  Gets the line number of a line or a reference to one.
    /// </summary>
    public int Number { get; init; }

    /// <summary>
    ///  Gets the reserved word a line reference follows, such as <c>GOSUB</c>.
    /// </summary>
    public string? Via { get; init; }

    /// <summary>
    ///  Gets what identifies a variable or function to BASIC: its first two characters, its type and whether it is
    ///  an array, such as <c>SC$(</c>. Names with the same key are the same variable.
    /// </summary>
    public string Key { get; init; } = "";

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
