// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media;

/// <summary>
///  One circular, MSB-first WOZ track. Shared TMAP entries reference the same physical bit storage.
/// </summary>
public sealed class DiskTrack
{
    private readonly byte[] _bits;

    /// <summary>
    ///  Copies a track, retaining its exact non-byte-aligned length.
    /// </summary>
    /// <param name="bits">Packed, most-significant-bit-first bits.</param>
    /// <param name="bitCount">The number of meaningful bits.</param>
    public DiskTrack(ReadOnlySpan<byte> bits, int bitCount)
    {
        if (bitCount <= 0 || (long)bitCount > (long)bits.Length * 8)
        {
            throw new ArgumentOutOfRangeException(nameof(bitCount));
        }

        BitCount = bitCount;
        _bits = bits[..(int)(((long)bitCount + 7) / 8)].ToArray();
    }

    /// <summary>
    ///  Gets the exact track length, including sync slip bits.
    /// </summary>
    public int BitCount { get; }

    /// <summary>
    ///  Gets packed track data.
    /// </summary>
    public ReadOnlySpan<byte> Bits => _bits;

    /// <summary>
    ///  Reads a bit at a validated position.
    /// </summary>
    /// <param name="position">A position within the track.</param>
    /// <returns>The physical flux-transition bit.</returns>
    public bool ReadBit(int position)
    {
        return (uint)position >= BitCount
            ? throw new ArgumentOutOfRangeException(nameof(position))
            : (_bits[position >> 3] & (128 >> (position & 7))) != 0;
    }

    /// <summary>
    ///  Changes one physical bit without altering the track length.
    /// </summary>
    /// <param name="position">A position within the track.</param>
    /// <param name="value">Whether a flux transition is present.</param>
    internal void WriteBit(int position, bool value)
    {
        if ((uint)position >= BitCount) { throw new ArgumentOutOfRangeException(nameof(position)); }
        byte mask = (byte)(128 >> (position & 7));
        _bits[position >> 3] = value ? (byte)(_bits[position >> 3] | mask) : (byte)(_bits[position >> 3] & ~mask);
    }
}
