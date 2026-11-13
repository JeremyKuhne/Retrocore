// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    /// <summary>
    ///  A packed field's address: a word's address, its width and its first bit, three words, from IXP.
    /// </summary>
    /// <param name="designator">The packed field.</param>
    private sealed class PackedAddress(Designator designator) : Expr
    {
        /// <summary>
        ///  Gets the packed field.
        /// </summary>
        public Designator Designator { get; } = designator;

        /// <inheritdoc/>
        public override int Words => 3;

        /// <inheritdoc/>
        public override TypeNode Type => Designator.Type;
    }
}
