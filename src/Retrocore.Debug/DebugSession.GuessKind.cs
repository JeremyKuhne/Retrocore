// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug;

internal sealed partial class DebugSession
{
    /// <summary>
    ///  What analysis guesses a byte is.
    /// </summary>
    private enum GuessKind : byte
    {
        /// <summary>
        ///  Nothing reached it.
        /// </summary>
        Unknown,

        /// <summary>
        ///  An instruction starts here.
        /// </summary>
        Start,

        /// <summary>
        ///  An instruction's operand.
        /// </summary>
        Operand,

        /// <summary>
        ///  Data, such as a vector or a table a jump reads.
        /// </summary>
        Data
    }
}
