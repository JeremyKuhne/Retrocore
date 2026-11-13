// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    /// <summary>
    ///  A FOR loop.
    /// </summary>
    /// <param name="control">The control variable.</param>
    /// <param name="from">The first value.</param>
    /// <param name="to">The last value.</param>
    /// <param name="down">Whether it counts down, DOWNTO.</param>
    /// <param name="body">The loop's statements.</param>
    private sealed class ForStatement(Designator control, Expr from, Expr to, bool down, List<Statement> body) : Statement
    {
        /// <summary>
        ///  Gets the control variable.
        /// </summary>
        public Designator Control { get; } = control;

        /// <summary>
        ///  Gets the first value.
        /// </summary>
        public Expr From { get; } = from;

        /// <summary>
        ///  Gets the last value.
        /// </summary>
        public Expr To { get; } = to;

        /// <summary>
        ///  Gets a value indicating whether it counts down, DOWNTO.
        /// </summary>
        public bool Down { get; } = down;

        /// <summary>
        ///  Gets the loop's statements.
        /// </summary>
        public List<Statement> Body { get; } = body;
    }
}
