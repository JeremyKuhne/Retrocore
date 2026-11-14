// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    /// <summary>
    ///  The test <c>SCAN</c> makes of each character, written as <c>= ch</c> or <c>&lt;&gt; ch</c>.
    /// </summary>
    /// <param name="unequal">Whether it scans for a character that is not the one given.</param>
    /// <param name="character">The character.</param>
    private sealed class ScanTest(bool unequal, Expr character) : Expr
    {
        /// <summary>
        ///  Gets whether it scans for a character that is not the one given.
        /// </summary>
        public bool Unequal { get; } = unequal;

        /// <summary>
        ///  Gets the character.
        /// </summary>
        public Expr Character { get; } = character;
    }
}
