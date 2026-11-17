// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    /// <summary>
    ///  A designator's value.
    /// </summary>
    /// <param name="designator">What is loaded.</param>
    /// <param name="words">The words loaded.</param>
    private sealed class Load(Designator designator, int words) : Expr
    {
        /// <summary>
        ///  Gets what is loaded.
        /// </summary>
        public Designator Designator { get; } = designator;

        /// <inheritdoc/>
        public override int Words { get; } = words;

        /// <inheritdoc/>
        public override TypeNode Type => Designator.Type;
    }
}
