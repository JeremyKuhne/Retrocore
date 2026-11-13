// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    /// <summary>
    ///  A byte's address: a base and an index, two words, from IXS or a packed array of bytes.
    /// </summary>
    /// <param name="designator">The byte.</param>
    private sealed class ByteAddress(Designator designator) : Expr
    {
        /// <summary>
        ///  Gets the byte.
        /// </summary>
        public Designator Designator { get; } = designator;

        /// <inheritdoc/>
        public override int Words => 2;

        /// <inheritdoc/>
        public override TypeNode Type => Designator.Type;
    }
}
