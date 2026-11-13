// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Pascal;

namespace Retrocore.Debug;

internal sealed partial class DebugSession
{
    /// <summary>
    ///  A step on the Pascal thread.
    /// </summary>
    /// <param name="Step">How it ends.</param>
    /// <param name="Mark">The MSCW of the procedure it started in; callers' are above it.</param>
    /// <param name="Deadline">When a pause gives up waiting for a p-code.</param>
    /// <param name="Listing">The listing of the line it started on, to step by line; null to step by p-code.</param>
    /// <param name="Line">The line it started on.</param>
    /// <param name="LineStart">Where the line's first p-code is, from the procedure's entry.</param>
    private sealed record PascalGoal(
        PascalStep Step,
        ushort Mark,
        ulong Deadline,
        PascalListing? Listing = null,
        PascalListingLine? Line = null,
        int LineStart = 0)
    {
        /// <summary>
        ///  Gets or sets whether a p-code past the line's first has run, so coming back to its first starts it again.
        /// </summary>
        internal bool Moved { get; set; }

        /// <summary>
        ///  Tests whether a p-code about to run ends a step by line: one on another line or in another procedure, or
        ///  the line's first again, as a loop comes back to it.
        /// </summary>
        /// <param name="top">The procedure about to run it.</param>
        /// <returns>Whether the step ends there.</returns>
        internal bool LeftLine(PascalFrame top)
        {
            if (Listing is null || Line is null) { return true; }
            if (top.SegmentNumber != Line.Segment || top.Procedure != Line.Procedure) { return true; }
            if (Listing.LineAt(top.SegmentNumber, top.Procedure, top.Offset) is not { } now || now.Line != Line.Line)
            {
                return true;
            }

            if (top.Offset == LineStart) { return Moved; }
            Moved = true;
            return false;
        }
    }
}
