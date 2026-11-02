// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

/// <summary>
///  Enumerates source lines without normalizing or splitting the source string.
/// </summary>
/// <remarks>
///  <para>
///   Slices borrow the original memory. A terminating newline leaves an empty final line, matching the
///   parser's physical-line accounting without allocating a normalized copy or a line array.
///  </para>
/// </remarks>
internal ref struct AssemblyLines
{
    private ReadOnlyMemory<char> _remaining;
    private bool _finished;

    /// <summary>
    ///  Creates a line cursor supporting CR, LF and CRLF.
    /// </summary>
    /// <param name="text">The original source.</param>
    internal AssemblyLines(ReadOnlyMemory<char> text)
    {
        _remaining = text;
        _finished = false;
        Current = default;
    }

    /// <summary>
    ///  Gets the current line without its terminator.
    /// </summary>
    public ReadOnlyMemory<char> Current { get; private set; }

    /// <summary>
    ///  Gets a value-copy cursor.
    /// </summary>
    /// <returns>The cursor.</returns>
    public readonly AssemblyLines GetEnumerator() => this;

    /// <summary>
    ///  Advances to the next physical line, including an empty final line.
    /// </summary>
    /// <returns>Whether a line remains.</returns>
    public bool MoveNext()
    {
        if (_finished) { return false; }
        ReadOnlySpan<char> span = _remaining.Span;
        int end = span.IndexOfAny('\r', '\n');
        if (end < 0)
        {
            Current = _remaining;
            _finished = true;
            return true;
        }

        Current = _remaining[..end];
        int next = end + 1;

        // Treat CRLF as one terminator while still accepting lone CR and lone LF.
        if (span[end] == '\r' && next < span.Length && span[next] == '\n') { next++; }
        _remaining = _remaining[next..];
        return true;
    }
}
