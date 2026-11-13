// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Pascal;

namespace Retrocore.Debug;

internal sealed partial class DebugSession
{
    /// <summary>
    ///  Where a Pascal breakpoint stops: a procedure of a segment, named or numbered, at an offset from its entry.
    /// </summary>
    /// <param name="Segment">The segment's name, or null when numbered.</param>
    /// <param name="Number">The segment's number, or null when named.</param>
    /// <param name="Procedure">The procedure's number.</param>
    /// <param name="Offset">The offset from the procedure's entry, as a compiler listing counts.</param>
    private sealed record PascalBreakpoint(string? Segment, int? Number, int Procedure, int Offset)
    {
        /// <summary>
        ///  Tests whether the procedure about to run a p-code is here.
        /// </summary>
        /// <param name="top">The procedure.</param>
        /// <param name="pascal">The p-machine, which names segments.</param>
        /// <returns>Whether it matches.</returns>
        internal bool Matches(PascalFrame top, PascalRuntime pascal) =>
            top.Procedure == Procedure
                && top.Offset == Offset
                && (Number is not { } number || number == top.SegmentNumber)
                && (Segment is null || string.Equals(pascal.Segment(top)?.Segment.Name, Segment, StringComparison.OrdinalIgnoreCase));
    }
}
