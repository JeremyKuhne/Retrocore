// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    /// <summary>
    ///  A constant of several words, from LDC: a real, or a set's words.
    /// </summary>
    /// <param name="values">The constant's words.</param>
    private sealed class WordsConstant(ushort[] values) : Expr
    {
        /// <summary>
        ///  Gets the constant's words.
        /// </summary>
        public ushort[] Values { get; } = values;

        /// <inheritdoc/>
        public override int Words => Values.Length;
    }
}
