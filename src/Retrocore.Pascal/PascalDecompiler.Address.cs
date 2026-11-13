// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    /// <summary>
    ///  A designator's address.
    /// </summary>
    /// <param name="designator">What the address is of.</param>
    private sealed class Address(Designator designator) : Expr
    {
        /// <summary>
        ///  Gets what the address is of.
        /// </summary>
        public Designator Designator { get; } = designator;

        /// <inheritdoc/>
        public override TypeNode Type => Designator.Type;
    }
}
