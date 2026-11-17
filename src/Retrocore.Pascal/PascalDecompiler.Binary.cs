// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    /// <summary>
    ///  An arithmetic or logical operator on two values, such as ADI or LAND.
    /// </summary>
    /// <param name="op">The operator.</param>
    /// <param name="left">The left value.</param>
    /// <param name="right">The right value.</param>
    private sealed class Binary(Operator op, Expr left, Expr right) : Expr
    {
        /// <summary>
        ///  Gets the operator.
        /// </summary>
        public Operator Op { get; } = op;

        /// <summary>
        ///  Gets the left value.
        /// </summary>
        public Expr Left { get; } = left;

        /// <summary>
        ///  Gets the right value.
        /// </summary>
        public Expr Right { get; } = right;

        /// <inheritdoc/>
        public override int Words => Op is Operator.RealAdd or Operator.RealSubtract or Operator.RealMultiply or Operator.RealDivide ? 2 : 1;
    }
}
