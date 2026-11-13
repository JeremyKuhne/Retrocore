// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    /// <summary>
    ///  A value WRITE writes, with the system procedure that writes it: 13 an integer, 17 a character, 19 a string,
    ///  20 a packed array of characters, 0 a real.
    /// </summary>
    /// <param name="value">The value.</param>
    /// <param name="procedure">The system procedure that writes it, or 0 for a real.</param>
    private sealed class Written(Expr value, int procedure) : Expr
    {
        /// <summary>
        ///  Gets the value.
        /// </summary>
        public Expr Value { get; } = value;

        /// <summary>
        ///  Gets the system procedure that writes it, or 0 for a real.
        /// </summary>
        public int Procedure { get; } = procedure;

        /// <inheritdoc/>
        public override int Words => Value.Words;

        /// <inheritdoc/>
        public override TypeNode Type => Value.Type;
    }
}
