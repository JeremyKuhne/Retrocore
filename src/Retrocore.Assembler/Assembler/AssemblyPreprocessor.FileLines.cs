// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

internal sealed partial class AssemblyPreprocessor
{
    /// <summary>
    ///  How the passes over one file's lines took them, in expansion order.
    /// </summary>
    /// <param name="count">The file's line count.</param>
    /// <param name="opaque">
    ///  Whether a line no pass took may still have been assembled, as in MACRO-10, whose conditionals are expanded
    ///  with the rest of its text.
    /// </param>
    private sealed class FileLines(int count, bool opaque)
    {
        /// <summary>
        ///  Gets, for each line, the earliest expansion position at which a pass assembled it, or
        ///  <see cref="int.MaxValue"/>.
        /// </summary>
        internal int[] Assembled { get; } = Filled(count, int.MaxValue);

        /// <summary>
        ///  Gets, for each line, the latest expansion position at which a pass reached it, or -1.
        /// </summary>
        internal int[] Visited { get; } = Filled(count, -1);

        /// <summary>
        ///  Gets, for each line, whether a macro expansion reached it: a body line, which a later expansion could take.
        /// </summary>
        internal bool[] Expanded { get; } = new bool[count];

        /// <summary>
        ///  Gets whether a line no pass took may still have been assembled.
        /// </summary>
        internal bool Opaque { get; } = opaque;

        /// <summary>
        ///  Gets or sets whether the file was included, so that a later inclusion could take what one skipped.
        /// </summary>
        internal bool Included { get; set; }

        private static int[] Filled(int count, int value)
        {
            int[] values = new int[count];
            for (int index = 0; index < values.Length; index++) { values[index] = value; }
            return values;
        }
    }
}
