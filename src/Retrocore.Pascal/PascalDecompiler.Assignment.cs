// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    /// <summary>
    ///  An assignment of a value to a designator.
    /// </summary>
    /// <param name="target">What is assigned.</param>
    /// <param name="value">The value.</param>
    /// <param name="block">Whether it copies a block, as <see cref="Block"/> says.</param>
    private sealed class Assignment(Designator target, Expr value, bool block = false) : Statement
    {
        /// <summary>
        ///  Gets what is assigned.
        /// </summary>
        public Designator Target { get; } = target;

        /// <summary>
        ///  Gets the value.
        /// </summary>
        public Expr Value { get; } = value;

        /// <summary>
        ///  Gets a value indicating whether it copies a block, a string's (SAS) or a record's or array's (MOV), as a
        ///  value parameter's copy does.
        /// </summary>
        public bool Block { get; } = block;
    }
}
