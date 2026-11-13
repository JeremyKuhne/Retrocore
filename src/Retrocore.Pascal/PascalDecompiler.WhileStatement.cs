// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    /// <summary>
    ///  A WHILE loop.
    /// </summary>
    /// <param name="condition">The condition tested before each pass.</param>
    /// <param name="body">The loop's statements.</param>
    private sealed class WhileStatement(Expr condition, List<Statement> body) : Statement
    {
        /// <summary>
        ///  Gets the condition tested before each pass.
        /// </summary>
        public Expr Condition { get; } = condition;

        /// <summary>
        ///  Gets the loop's statements.
        /// </summary>
        public List<Statement> Body { get; } = body;
    }
}
