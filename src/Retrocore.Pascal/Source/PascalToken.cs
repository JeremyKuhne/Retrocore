// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal.Source;

/// <summary>
///  A token of Apple Pascal source, where it is in its file.
/// </summary>
/// <param name="Kind">What it is.</param>
/// <param name="Text">Its text, as written.</param>
/// <param name="File">The file it is in.</param>
/// <param name="Line">Its first line, from 0.</param>
/// <param name="Column">Its first column, from 0.</param>
/// <param name="EndLine">Its last line, from 0.</param>
/// <param name="EndColumn">The column after its last character.</param>
public sealed record PascalToken(
    PascalTokenKind Kind,
    string Text,
    string File,
    int Line,
    int Column,
    int EndLine,
    int EndColumn)
{
    /// <summary>
    ///  Gets whether it is a comment of any kind, an option included.
    /// </summary>
    public bool IsComment => Kind is PascalTokenKind.Comment
        or PascalTokenKind.DocComment
        or PascalTokenKind.Option
        or PascalTokenKind.BraceComment;

    /// <summary>
    ///  Gets whether it is the given reserved word.
    /// </summary>
    /// <param name="word">The word, in upper case.</param>
    /// <returns>Whether it is.</returns>
    public bool Is(string word) => Kind == PascalTokenKind.Keyword && PascalNames.Key(Text) == PascalNames.Key(word);

    /// <summary>
    ///  Gets whether it is the given symbol.
    /// </summary>
    /// <param name="symbol">The symbol.</param>
    /// <returns>Whether it is.</returns>
    public bool IsSymbol(string symbol) => Kind == PascalTokenKind.Symbol && Text == symbol;

    /// <summary>
    ///  Gets whether a position, zero-based, is inside it.
    /// </summary>
    /// <param name="line">The line.</param>
    /// <param name="column">The column.</param>
    /// <returns>Whether it is.</returns>
    public bool Contains(int line, int column) =>
        (line > Line || (line == Line && column >= Column))
            && (line < EndLine || (line == EndLine && column <= EndColumn));
}
