// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

internal sealed partial class AssemblyPreprocessor
{
    /// <summary>
    ///  What the passes over a line make of it, ordered so that the stronger of two passes' states is the larger.
    /// </summary>
    private enum LineState : byte
    {
        /// <summary>
        ///  No pass assembled it.
        /// </summary>
        Skipped,

        /// <summary>
        ///  Whether it is assembled can't be told.
        /// </summary>
        Undecided,

        /// <summary>
        ///  Some pass assembled it.
        /// </summary>
        Assembled
    }
}
