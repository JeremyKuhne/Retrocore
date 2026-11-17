// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    /// <summary>
    ///  A value a range check bounds, from CHK.
    /// </summary>
    /// <param name="value">The value checked.</param>
    /// <param name="low">The range's low bound.</param>
    /// <param name="high">The range's high bound.</param>
    private sealed class Checked(Expr value, int low, int high) : Expr
    {
        /// <summary>
        ///  Gets the value checked.
        /// </summary>
        public Expr Value { get; } = value;

        /// <summary>
        ///  Gets the range's low bound.
        /// </summary>
        public int Low { get; } = low;

        /// <summary>
        ///  Gets the range's high bound.
        /// </summary>
        public int High { get; } = high;

        /// <inheritdoc/>
        public override int Words => Value.Words;

        /// <inheritdoc/>
        public override TypeNode Type => Value.Type;
    }
}
