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
    private sealed record MemoryView(string Reference)
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
        ///  Gets or sets the first offset from <see cref="Address"/> the view has read.
        /// </summary>
        internal long First { get; set; }

        /// <summary>
        ///  Gets or sets the offset past the last byte the view has read.
        /// </summary>
        internal long End { get; set; }

        /// <summary>
        ///  Gets or sets a hash of the bytes the view saw last, as of its last read or memory event.
        /// </summary>
        internal ulong Seen { get; set; }
    }
}
