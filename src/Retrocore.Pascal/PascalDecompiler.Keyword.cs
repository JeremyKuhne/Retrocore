// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    /// <summary>
    ///  A word a built-in takes as written, such as CLOSE's LOCK.
    /// </summary>
    /// <param name="text">The word.</param>
    private sealed class Keyword(string text) : Expr
    {
        /// <summary>
        ///  Gets the word.
        /// </summary>
        public string Text { get; } = text;
    }
}
