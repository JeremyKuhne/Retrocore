// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media.Commodore;

/// <summary>
///  Writes a track's cells in order, packed eight to a byte, first in bit 7, stopping at the track's length.
/// </summary>
/// <param name="capacity">The track's cells.</param>
internal sealed class GcrBitWriter(int capacity)
{
    /// <summary>
    ///  Gets the track's bytes.
    /// </summary>
    public byte[] Buffer { get; } = new byte[(capacity + 7) / 8];

    /// <summary>
    ///  Gets the cells written.
    /// </summary>
    public int Count { get; private set; }

    /// <summary>
    ///  Writes a cell.
    /// </summary>
    /// <param name="one">Whether the flux changes there.</param>
    public void Bit(bool one)
    {
        if (Count >= capacity) { return; }
        if (one) { Buffer[Count >> 3] |= (byte)(0x80 >> (Count & 7)); }
        Count++;
    }

    /// <summary>
    ///  Writes 1s, as a sync.
    /// </summary>
    /// <param name="count">How many.</param>
    public void Ones(int count)
    {
        for (int i = 0; i < count; i++) { Bit(one: true); }
    }

    /// <summary>
    ///  Writes a byte as its ten GCR cells.
    /// </summary>
    /// <param name="value">The byte.</param>
    public void Byte(byte value)
    {
        int code = GcrLayout.Encode(value);
        for (int i = 9; i >= 0; i--) { Bit(((code >> i) & 1) != 0); }
    }

    /// <summary>
    ///  Writes bytes as GCR.
    /// </summary>
    /// <param name="values">The bytes.</param>
    public void Bytes(ReadOnlySpan<byte> values)
    {
        foreach (byte value in values) { Byte(value); }
    }

    /// <summary>
    ///  Writes zero bytes as GCR, as a gap.
    /// </summary>
    /// <param name="count">How many.</param>
    public void Zeros(int count)
    {
        for (int i = 0; i < count; i++) { Byte(0); }
    }
}
