// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    /// <summary>
    ///  A GOTO statement.
    /// </summary>
    /// <param name="target">The offset it jumps to.</param>
    private sealed class GotoStatement(int target) : Statement
    {
        /// <summary>
        ///  Gets the offset it jumps to.
        /// </summary>
        public int Target { get; } = target;
    }
}
