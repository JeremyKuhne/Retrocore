// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug;

internal sealed partial class DebugSession
{
    /// <summary>
    ///  A memory view's reference and the bytes it has read, to tell it to read again only when they change.
    /// </summary>
    /// <param name="Reference">The memory reference, exactly as the view gave it.</param>
    /// <param name="Subscriber">The Retrocore Memory editor, or null for a reader without a subscriber.</param>
    private sealed record MemoryView(string Reference, string? Subscriber)
    {
        /// <summary>
        ///  Gets or sets the bank the reference named when the view last read, or null for the CPU's memory.
        /// </summary>
        internal DebugMemoryBank? Bank { get; set; }

        /// <summary>
        ///  Gets or sets the address the reference resolved to when the view last read.
        /// </summary>
        internal long Address { get; set; }

        /// <summary>
        ///  Gets the sorted, disjoint ranges of offsets the view has read.
        /// </summary>
        internal List<(long First, long End)> Ranges { get; } = [];

        /// <summary>
        ///  Adds a read range, merging overlapping or adjacent ranges.
        /// </summary>
        /// <param name="first">The first offset read.</param>
        /// <param name="end">The offset past the last byte read.</param>
        internal void Add(long first, long end)
        {
            if (first >= end) { return; }
            int index = 0;
            while (index < Ranges.Count && Ranges[index].End < first) { index++; }
            while (index < Ranges.Count && Ranges[index].First <= end)
            {
                (long start, long stop) = Ranges[index];
                first = Math.Min(first, start);
                end = Math.Max(end, stop);
                Ranges.RemoveAt(index);
            }

            Ranges.Insert(index, (first, end));
        }

        /// <summary>
        ///  Gets or sets a hash of the bytes the view saw last, as of its last read or memory event.
        /// </summary>
        internal ulong Seen { get; set; }
    }
}
