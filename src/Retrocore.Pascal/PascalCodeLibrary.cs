// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Media;

namespace Retrocore.Pascal;

/// <summary>
///  Code files to name the segments in memory by: a segment loaded from a file ends with the same bytes as the file's
///  segment, its procedure dictionary and the code before it, wherever the system put it.
/// </summary>
public sealed class PascalCodeLibrary
{
    private const int Compared = 64;
    private readonly List<(string File, PascalSegment Segment)> _segments = [];

    /// <summary>
    ///  Gets how many segments it has.
    /// </summary>
    public int Count => _segments.Count;

    /// <summary>
    ///  Adds a code file's segments.
    /// </summary>
    /// <param name="file">The file's name, such as <c>/PASCAL2/HELLO.CODE</c>.</param>
    /// <param name="code">The code file.</param>
    public void Add(string file, PascalCodeFile code)
    {
        ArgumentNullException.ThrowIfNull(code);
        foreach (PascalSegment segment in code.Segments)
        {
            if (segment.Code.Length >= 2) { _segments.Add((file, segment)); }
        }
    }

    /// <summary>
    ///  Forgets every segment.
    /// </summary>
    public void Clear() => _segments.Clear();

    /// <summary>
    ///  Finds the segment that is in memory with its last word at a place.
    /// </summary>
    /// <param name="memory">The memory.</param>
    /// <param name="segment">Where the segment's last word (its number and procedure count) is: SEG.</param>
    /// <returns>The file and segment, or null when no code file's segment ends with those bytes.</returns>
    public (string File, PascalSegment Segment)? Find(IPascalMemory memory, PascalPointer segment)
    {
        ArgumentNullException.ThrowIfNull(memory);
        int number = memory.Read(segment.Address, segment.Bank);
        int count = memory.Read((ushort)(segment.Address + 1), segment.Bank);
        foreach ((string file, PascalSegment candidate) in _segments)
        {
            byte[] code = candidate.Code;
            if (code[^2] != number || code[^1] != count) { continue; }

            int length = Math.Min(Compared, code.Length);
            bool same = true;
            for (int index = 1; index <= length && same; index++)
            {
                same = memory.Read((ushort)(segment.Address + 2 - index), segment.Bank) == code[^index];
            }

            if (same) { return (file, candidate); }
        }

        return null;
    }
}
