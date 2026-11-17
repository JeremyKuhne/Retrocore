// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    /// <summary>
    ///  A call of a function: a user's, a unit's, or a built-in one.
    /// </summary>
    /// <param name="callee">The function.</param>
    /// <param name="arguments">Its arguments.</param>
    /// <param name="words">The words of its result.</param>
    private sealed class Call(Callee callee, List<Expr> arguments, int words) : Expr
    {
        /// <summary>
        ///  Gets the function.
        /// </summary>
        public Callee Callee { get; } = callee;

        /// <summary>
        ///  Gets its arguments.
        /// </summary>
        public List<Expr> Arguments { get; } = arguments;

        /// <inheritdoc/>
        public override int Words { get; } = words;

        /// <inheritdoc/>
        public override TypeNode Type { get; } = callee.ResultType ?? new TypeNode();
    }
}
