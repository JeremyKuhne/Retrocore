// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Basic;

/// <summary>
///  The bytes a tokenizer stores, each with the text unit it came from: a reserved word's first letter, or the
///  character itself.
/// </summary>
internal sealed class CrunchOutput
{
    private readonly List<byte> _bytes;
    private readonly List<int> _positions;

    /// <summary>
    ///  Creates the output.
    /// </summary>
    /// <param name="capacity">The bytes expected.</param>
    internal CrunchOutput(int capacity)
    {
        _bytes = new(capacity);
        _positions = new(capacity);
    }

    /// <summary>
    ///  Gets the text unit each byte came from.
    /// </summary>
    internal IReadOnlyList<int> Positions => _positions;

    /// <summary>
    ///  Stores a byte.
    /// </summary>
    /// <param name="value">The byte.</param>
    /// <param name="at">The text unit it came from.</param>
    internal void Add(int value, int at)
    {
        _bytes.Add((byte)value);
        _positions.Add(at);
    }

    /// <summary>
    ///  Removes the last byte, the zero that ends the line.
    /// </summary>
    internal void RemoveLast()
    {
        _bytes.RemoveAt(_bytes.Count - 1);
        _positions.RemoveAt(_positions.Count - 1);
    }

    /// <summary>
    ///  Gets the bytes.
    /// </summary>
    /// <returns>The bytes.</returns>
    internal byte[] ToArray() => [.. _bytes];
}
