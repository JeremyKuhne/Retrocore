// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    /// <summary>
    ///  A set: its elements and ranges, and a constant's bits, with or without its size word.
    /// </summary>
    private sealed class SetValue : Expr
    {
        /// <summary>
        ///  Gets or sets a set variable's or constant's value, or null for a set built here.
        /// </summary>
        public Expr? Value { get; set; }

        /// <summary>
        ///  Gets the elements and ranges of a set built here, a range with its high bound.
        /// </summary>
        public List<(Expr Low, Expr? High)> Members { get; } = [];

        /// <summary>
        ///  Gets or sets the set operator that makes it from <see cref="Left"/> and <see cref="Right"/>, if any.
        /// </summary>
        public Operator? Op { get; set; }

        /// <summary>
        ///  Gets or sets the set operator's left set.
        /// </summary>
        public SetValue? Left { get; set; }

        /// <summary>
        ///  Gets or sets the set operator's right set.
        /// </summary>
        public SetValue? Right { get; set; }

        /// <summary>
        ///  Gets or sets its words once ADJ fixes them; 0 while it carries its size.
        /// </summary>
        public int Fixed { get; set; }

        /// <inheritdoc/>
        public override int Words => Fixed == 0 ? 1 : Fixed;

        /// <inheritdoc/>
        public override TypeNode Type { get; } = TypeNode.Of(TypeKind.Set);
    }
}
