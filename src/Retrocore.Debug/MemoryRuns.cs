// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json.Nodes;

namespace Retrocore.Debug;

/// <summary>
///  Collects the runs of a memory range's offsets that have some property, such as being unreadable, as the
///  <c>[{offset, count}]</c> arrays memory requests answer with.
/// </summary>
internal sealed class MemoryRuns
{
    private readonly List<JsonNode?> _runs = [];
    private int? _start;

    /// <summary>
    ///  Notes whether an offset has the property.
    /// </summary>
    /// <param name="offset">The offset, after every offset noted before.</param>
    /// <param name="has">Whether it has the property.</param>
    internal void Add(int offset, bool has)
    {
        if (has)
        {
            _start ??= offset;
        }
        else if (_start is { } from)
        {
            _runs.Add(new JsonObject { ["offset"] = from, ["count"] = offset - from });
            _start = null;
        }
    }

    /// <summary>
    ///  Ends the range.
    /// </summary>
    /// <param name="end">The offset the range ends at, ending any run still open.</param>
    /// <returns>The runs.</returns>
    internal JsonArray End(int end)
    {
        Add(end, has: false);
        return _runs.ToJsonArray();
    }
}
