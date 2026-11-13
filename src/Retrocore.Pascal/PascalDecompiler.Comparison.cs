// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    /// <summary>
    ///  A comparison of two values, or a set membership test, which leaves a boolean.
    /// </summary>
    /// <param name="op">The comparison's operator.</param>
    /// <param name="comparand">What it compares.</param>
    /// <param name="left">The left value.</param>
    /// <param name="right">The right value.</param>
    /// <param name="size">An array comparison's size: bytes for a packed array of characters, words otherwise.</param>
    private sealed class Comparison(Operator op, Comparand comparand, Expr left, Expr right, int size) : Expr
    {
        /// <summary>
        ///  Gets the comparison's operator.
        /// </summary>
        public Operator Op { get; } = op;

        /// <summary>
        ///  Gets what it compares.
        /// </summary>
        public Comparand Comparand { get; } = comparand;

        /// <summary>
        ///  Gets the left value.
        /// </summary>
        public Expr Left { get; } = left;

        /// <summary>
        ///  Gets the right value.
        /// </summary>
        public Expr Right { get; } = right;

        /// <summary>
        ///  Gets an array comparison's size: bytes for a packed array of characters, words otherwise.
        /// </summary>
        public int Size { get; } = size;
    }
}
