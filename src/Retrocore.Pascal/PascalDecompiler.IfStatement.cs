// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    /// <summary>
    ///  An IF statement, with or without ELSE.
    /// </summary>
    /// <param name="condition">The condition.</param>
    /// <param name="then">The statements done when it is true.</param>
    /// <param name="otherwise">The statements done when it is false, or null without ELSE.</param>
    private sealed class IfStatement(Expr condition, List<Statement> then, List<Statement>? otherwise) : Statement
    {
        /// <summary>
        ///  Gets the condition.
        /// </summary>
        public Expr Condition { get; } = condition;

        /// <summary>
        ///  Gets the statements done when it is true.
        /// </summary>
        public List<Statement> Then { get; } = then;

        /// <summary>
        ///  Gets the statements done when it is false, or null without ELSE.
        /// </summary>
        public List<Statement>? Else { get; } = otherwise;
    }
}
