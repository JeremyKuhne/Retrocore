// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

internal sealed partial class AssemblyPreprocessor
{
    /// <summary>
    ///  One ca65 token with its span in the scanned text.
    /// </summary>
    /// <param name="start">The first character.</param>
    /// <param name="end">The exclusive end.</param>
    /// <param name="type">The token type compared by .match.</param>
    /// <param name="value">The value also compared by .xmatch.</param>
    private readonly struct Ca65Token(int start, int end, string type, string value)
    {
        /// <summary>
        ///  Gets the first character's index.
        /// </summary>
        internal int Start { get; } = start;

        /// <summary>
        ///  Gets the exclusive end index.
        /// </summary>
        internal int End { get; } = end;

        /// <summary>
        ///  Gets the token type.
        /// </summary>
        internal string Type { get; } = type;

        /// <summary>
        ///  Gets the token value.
        /// </summary>
        internal string Value { get; } = value;
    }
}
