// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    /// <summary>
    ///  A CASE statement.
    /// </summary>
    /// <param name="selector">The value that selects an arm.</param>
    /// <param name="arms">The arms: each one's labels and statements.</param>
    private sealed class CaseStatement(Expr selector, List<(List<int> Labels, List<Statement> Body)> arms) : Statement
    {
        /// <summary>
        ///  Gets the value that selects an arm.
        /// </summary>
        public Expr Selector { get; } = selector;

        /// <summary>
        ///  Gets the arms: each one's labels and statements.
        /// </summary>
        public List<(List<int> Labels, List<Statement> Body)> Arms { get; } = arms;
    }
}
