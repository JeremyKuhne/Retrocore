// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal.Source;

/// <summary>
///  A file of a program, as the program reads it.
/// </summary>
/// <param name="Path">Its path.</param>
/// <param name="Text">Its text.</param>
/// <param name="Tokens">Its tokens.</param>
public sealed record PascalSourceFile(string Path, string Text, IReadOnlyList<PascalToken> Tokens)
{
    /// <summary>
    ///  Gets its lines.
    /// </summary>
    public string[] Lines { get; } = PascalLexer.Lines(Text);

    /// <summary>
    ///  Gets its documentation comment: its first <c>(** *)</c>, when a blank line or the end of the file follows it.
    /// </summary>
    public PascalDocComment? Doc { get; internal set; }
}
