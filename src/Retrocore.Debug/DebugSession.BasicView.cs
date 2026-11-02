// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Basic;

namespace Retrocore.Debug;

internal sealed partial class DebugSession
{
    /// <summary>
    ///  The program in memory as the machine-program document shows it: one text line per program line, with each
    ///  line's address and statements.
    /// </summary>
    /// <param name="Version">The program's version, for knowing when it changes.</param>
    /// <param name="Source">The listing, analyzed.</param>
    /// <param name="Addresses">Each line's address, by line number.</param>
    private sealed record BasicView(string Version, BasicSource Source, Dictionary<int, int> Addresses)
    {
        /// <summary>
        ///  Finds the line with a number.
        /// </summary>
        /// <param name="number">The line number.</param>
        /// <returns>The line, or null.</returns>
        internal BasicSourceLine? Line(int number) => Source.LineNumbered(number);

        /// <summary>
        ///  Gets the text of a statement, from its first character to the next statement's colon.
        /// </summary>
        /// <param name="line">The line.</param>
        /// <param name="statement">The statement's index.</param>
        /// <returns>The text.</returns>
        internal string Text(BasicSourceLine line, int statement)
        {
            string text = Source.Lines[line.Line];
            int start = Math.Min(line.Statements[statement].Column, text.Length);
            int end = statement + 1 < line.Statements.Count ? line.Statements[statement + 1].Column : text.Length;
            end = Math.Max(Math.Min(end, text.Length), start);
            return text[start..end].TrimEnd().TrimEnd(':').Trim();
        }
    }
}
