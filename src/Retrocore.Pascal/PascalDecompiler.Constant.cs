// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    /// <summary>
    ///  A one-word constant: an integer, a character, a boolean, or an enumerated value.
    /// </summary>
    /// <param name="value">The constant's word.</param>
    private sealed class Constant(int value) : Expr
    {
        /// <summary>
        ///  Gets the constant's word.
        /// </summary>
        public int Value { get; } = value;
    }
}
