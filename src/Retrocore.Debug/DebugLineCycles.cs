// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Runtime.InteropServices;

namespace Retrocore.Debug;

/// <summary>
///  Records source-line cycle counts and their changes since the last event.
/// </summary>
internal sealed class DebugLineCycles
{
    private readonly Dictionary<(string Path, int Line), ulong> _last = [];
    // Null means the line was absent from the last event, rather than present with a zero count.
    private readonly Dictionary<(string Path, int Line), ulong?> _before = [];

    /// <summary>
    ///  Gets each line's latest count.
    /// </summary>
    internal IReadOnlyDictionary<(string Path, int Line), ulong> Last => _last;

    /// <summary>
    ///  Gets whether any tracked line differs from its value at the last event.
    /// </summary>
    internal bool Changed => _before.Count != 0;

    /// <summary>
    ///  Adds cycles to a line or starts a new count for it.
    /// </summary>
    /// <param name="source">The source line.</param>
    /// <param name="cycles">The cycles since its last update.</param>
    /// <param name="entered">Whether the line was entered since its last update.</param>
    /// <param name="track">Whether to track changes for the next event.</param>
    internal void Update((string Path, int Line) source, ulong cycles, bool entered, bool track)
    {
        ref ulong count = ref CollectionsMarshal.GetValueRefOrAddDefault(_last, source, out bool exists);
        ulong updated = entered ? cycles : count + cycles;
        if (!exists || count != updated)
        {
            if (track)
            {
                if (_before.TryGetValue(source, out ulong? original))
                {
                    if (original == updated) { _before.Remove(source); }
                }
                else
                {
                    _before.Add(source, exists ? count : null);
                }
            }

            count = updated;
        }
    }

    /// <summary>
    ///  Records that the current counts were sent.
    /// </summary>
    internal void Sent() => _before.Clear();

    /// <summary>
    ///  Forgets the counts and their changes.
    /// </summary>
    internal void Clear()
    {
        _last.Clear();
        _before.Clear();
    }
}
