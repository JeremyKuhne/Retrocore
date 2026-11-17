// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    /// <summary>
    ///  A REPEAT loop.
    /// </summary>
    /// <param name="body">The loop's statements.</param>
    /// <param name="condition">The UNTIL condition tested after each pass.</param>
    private sealed class RepeatStatement(List<Statement> body, Expr condition) : Statement
    {
        /// <summary>
        ///  Gets the loop's statements.
        /// </summary>
        public List<Statement> Body { get; } = body;

        /// <summary>
        ///  Gets the UNTIL condition tested after each pass.
        /// </summary>
        public Expr Condition { get; } = condition;
    }
}
