// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json.Nodes;

namespace Retrocore.Debug;

/// <summary>
///  Retains an ordered prefix of accepted terminal bytes with their guest cycles.
/// </summary>
/// <param name="capacity">The maximum number of undrained bytes.</param>
internal sealed class ConsoleCapture(int capacity)
{
    private readonly Queue<(byte Code, ulong Cycle)> _bytes = new(capacity);
    private long _offset;

    /// <summary>
    ///  Gets whether at least one byte could not be retained.
    /// </summary>
    internal bool Overflowed { get; private set; }

    /// <summary>
    ///  Records a byte unless the stream has overflowed.
    /// </summary>
    /// <param name="code">The seven bits accepted by the terminal.</param>
    /// <param name="cycle">The current guest cycle.</param>
    /// <returns>Whether the stream retained the byte.</returns>
    internal bool Add(byte code, ulong cycle)
    {
        if (_bytes.Count == capacity) { Overflowed = true; }
        if (Overflowed) { return false; }
        _bytes.Enqueue((code, cycle));
        return true;
    }

    /// <summary>
    ///  Drains a batch in source order without clearing overflow status.
    /// </summary>
    /// <param name="maximum">The maximum number of bytes to drain.</param>
    /// <returns>The owned batch and its position in the stream.</returns>
    internal JsonObject Read(int maximum)
    {
        byte[] bytes = new byte[Math.Min(maximum, _bytes.Count)];
        ulong? first = null;
        ulong? last = null;
        for (int index = 0; index < bytes.Length; index++)
        {
            (bytes[index], ulong cycle) = _bytes.Dequeue();
            first ??= cycle;
            last = cycle;
        }

        long offset = _offset;
        _offset += bytes.Length;
        return new JsonObject
        {
            ["sink"] = "apple1Terminal",
            ["encoding"] = "ascii7",
            ["offset"] = offset,
            ["count"] = bytes.Length,
            ["data"] = Convert.ToBase64String(bytes),
            ["firstCycle"] = first,
            ["lastCycle"] = last,
            ["remaining"] = _bytes.Count,
            ["overflow"] = Overflowed
        };
    }
}
