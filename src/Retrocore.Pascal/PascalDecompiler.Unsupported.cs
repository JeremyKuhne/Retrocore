// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    /// <summary>
    ///  Code the decompiler could not express, as a comment.
    /// </summary>
    /// <param name="text">The comment's text.</param>
    private sealed class Unsupported(string text) : Statement
    {
        /// <summary>
        ///  Gets the comment's text.
        /// </summary>
        public string Text { get; } = text;
    }
}
