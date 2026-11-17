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

        /// <summary>
        ///  Gets whether LDCI loaded it though SLDC holds it: the Compiler loads a negative constant it declares, such as
        ///  <c>CONST M = -1</c>, as its magnitude by LDCI and NGI, where <c>-1</c> in an expression is SLDC 1 and NGI.
        /// </summary>
        public bool Wide { get; init; }
    }
}
