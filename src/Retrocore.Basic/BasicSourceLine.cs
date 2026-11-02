// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Basic;

/// <summary>
///  A numbered line of BASIC text.
/// </summary>
/// <param name="Line">The zero-based line of the text.</param>
/// <param name="Number">The line number.</param>
/// <param name="Start">The column the number starts at.</param>
/// <param name="End">The column past the number.</param>
/// <param name="Tokens">The statements, as BASIC stores them; empty when they do not tokenize.</param>
/// <param name="Statements">Where each statement starts, in order.</param>
public sealed record BasicSourceLine(
    int Line,
    int Number,
    int Start,
    int End,
    ReadOnlyMemory<byte> Tokens,
    IReadOnlyList<BasicStatement> Statements)
{
    /// <summary>
    ///  Finds the statement a byte of the stored line is in.
    /// </summary>
    /// <param name="offset">The byte.</param>
    /// <returns>The statement's index, 0 when the line has none.</returns>
    public int StatementAt(int offset)
    {
        int found = 0;
        for (int index = 0; index < Statements.Count; index++)
        {
            if (Statements[index].Offset <= offset) { found = index; }
        }

        return found;
    }

    /// <summary>
    ///  Finds the statement at a column of the text.
    /// </summary>
    /// <param name="column">The column.</param>
    /// <returns>The statement's index, 0 when the line has none.</returns>
    public int StatementAtColumn(int column)
    {
        int found = 0;
        for (int index = 0; index < Statements.Count; index++)
        {
            if (Statements[index].Column <= column) { found = index; }
        }

        return found;
    }
}
