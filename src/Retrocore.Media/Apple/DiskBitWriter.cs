// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media;

/// <summary>
///  Packs GCR bytes and non-byte-aligned sync words into caller-owned track storage.
/// </summary>
internal ref struct DiskBitWriter
{
    private readonly Span<byte> _data;

    /// <summary>
    ///  Starts an empty track.
    /// </summary>
    /// <param name="data">Zeroed packed-bit storage.</param>
    internal DiskBitWriter(Span<byte> data)
    {
        _data = data;
        Position = 0;
    }

    /// <summary>
    ///  Gets the number of appended bits.
    /// </summary>
    internal int Position { get; private set; }

    /// <summary>
    ///  Appends one physical bit.
    /// </summary>
    /// <param name="value">The transition bit.</param>
    internal void Bit(bool value)
    {
        if (Position >= _data.Length * 8) { throw new InvalidOperationException("Track buffer is full."); }
        if (value) { _data[Position >> 3] |= (byte)(128 >> (Position & 7)); }
        Position++;
    }

    /// <summary>
    ///  Appends a GCR octet most-significant bit first.
    /// </summary>
    /// <param name="value">The byte.</param>
    internal void Byte(byte value)
    {
        for (int bit = 7; bit >= 0; bit--) { Bit((value & (1 << bit)) != 0); }
    }

    /// <summary>
    ///  Appends a ten-bit FF00 sync word used by 16-sector media.
    /// </summary>
    internal void Sync()
    {
        Byte(value: 255);
        Bit(value: false);
        Bit(value: false);
    }

    /// <summary>
    ///  Appends a nine-bit sync word used by 13-sector media, whose sequencer can't read two 0 bits in a row.
    /// </summary>
    internal void Sync9()
    {
        Byte(value: 255);
        Bit(value: false);
    }

    /// <summary>
    ///  Appends the two 4-and-4 address-field nibbles.
    /// </summary>
    /// <param name="value">The decoded address byte.</param>
    internal void Address(byte value)
    {
        Byte((byte)((value >> 1) | 0xAA));
        Byte((byte)(value | 0xAA));
    }
}
