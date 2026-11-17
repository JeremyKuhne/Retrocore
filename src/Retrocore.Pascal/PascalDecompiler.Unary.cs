// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    /// <summary>
    ///  An operator on one value, such as NGI or LNOT.
    /// </summary>
    /// <param name="op">The operator.</param>
    /// <param name="operand">The value.</param>
    private sealed class Unary(Operator op, Expr operand) : Expr
    {
        /// <summary>
        ///  Gets the operator.
        /// </summary>
        public Operator Op { get; } = op;

        /// <summary>
        ///  Gets the value.
        /// </summary>
        public Expr Operand { get; } = operand;

        /// <inheritdoc/>
        public override int Words => Op is Operator.RealNegate or Operator.RealAbsolute or Operator.RealSquare or Operator.Float ? 2 : 1;
    }
}
