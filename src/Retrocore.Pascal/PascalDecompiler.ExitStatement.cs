// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    /// <summary>
    ///  EXIT(procedure), naming a procedure by its segment and number.
    /// </summary>
    /// <param name="segment">The procedure's segment number.</param>
    /// <param name="procedure">The procedure's number.</param>
    private sealed class ExitStatement(int segment, int procedure) : Statement
    {
        /// <summary>
        ///  Gets the procedure's segment number.
        /// </summary>
        public int Segment { get; } = segment;

        /// <summary>
        ///  Gets the procedure's number.
        /// </summary>
        public int Procedure { get; } = procedure;
    }
}
