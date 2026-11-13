// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    /// <summary>
    ///  A string's character, from IXS, or its length, at byte 0.
    /// </summary>
    /// <param name="text">The string.</param>
    /// <param name="index">The character's index.</param>
    private sealed class StringIndexDesignator(Designator text, Expr index) : Designator
    {
        /// <summary>
        ///  Gets the string.
        /// </summary>
        public Designator Text { get; } = text;

        /// <summary>
        ///  Gets the character's index.
        /// </summary>
        public Expr Index { get; } = index;

        /// <inheritdoc/>
        public override TypeNode Type { get; } = TypeNode.Scalar(ScalarKind.Char);
    }
}
