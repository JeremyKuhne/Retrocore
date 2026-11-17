// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    /// <summary>
    ///  A label a GOTO jumps to.
    /// </summary>
    /// <param name="target">The offset it marks.</param>
    private sealed class LabelStatement(int target) : Statement
    {
        /// <summary>
        ///  Gets the offset it marks.
        /// </summary>
        public int Target { get; } = target;
    }
}
