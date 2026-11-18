// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media.Commodore;

/// <summary>
///  A Commodore 5¼-inch GCR disk as the drive's head sees it: up to 84 half-track positions, each a loop of bit cells,
///  a 1 where the flux changes, written at its track's speed zone.
/// </summary>
/// <remarks>
///  <para>
///   Position 0 is track 1, and data tracks lie on the even positions, as G64 images number them. A track goes round
///   once every 200 ms (300 rpm), so its length in cells says how long each cell is. The four speed zones write cells
///   of 4, 3.75, 3.5 and 3.25 µs (zone 0 to 3).
///  </para>
/// </remarks>
public sealed class CommodoreDisk : IMedium
{
    /// <summary>
    ///  The <see cref="MediumSnapshot.Kind"/> of a disk's snapshot, whose image is a G64 file.
    /// </summary>
    public const string SnapshotKind = "commodore-gcr-disk";

    /// <summary>
    ///  The half-track positions a disk holds.
    /// </summary>
    public const int Positions = 84;

    private readonly byte[]?[] _tracks = new byte[Positions][];
    private readonly int[] _bits = new int[Positions];
    private readonly byte[] _zones = new byte[Positions];
    private bool _writeProtected;

    /// <summary>
    ///  The most bytes a track holds: a G64 keeps each track's length in 16 bits.
    /// </summary>
    public const int MaximumTrackBytes = ushort.MaxValue;

    /// <inheritdoc/>
    public long Version { get; private set; }

    /// <summary>
    ///  Gets whether writes have changed the disk since it was loaded or last saved.
    /// </summary>
    public bool IsDirty { get; private set; }

    /// <inheritdoc/>
    public bool IsWriteProtected
    {
        get => _writeProtected;
        set
        {
            if (value == _writeProtected) { return; }
            _writeProtected = value;
            Version++;
        }
    }

    /// <summary>
    ///  Gets a position's length in cells, 0 for a position with nothing written.
    /// </summary>
    /// <param name="position">The half-track position, 0-83.</param>
    /// <returns>The cells.</returns>
    public int BitCount(int position) => _bits[position];

    /// <summary>
    ///  Gets a position's speed zone, 0-3.
    /// </summary>
    /// <param name="position">The half-track position, 0-83.</param>
    /// <returns>The zone.</returns>
    public int Zone(int position) => _zones[position];

    /// <summary>
    ///  Reads a cell.
    /// </summary>
    /// <param name="position">The half-track position, 0-83.</param>
    /// <param name="cell">The cell, less than <see cref="BitCount(int)"/>.</param>
    /// <returns>Whether the flux changes there.</returns>
    public bool Read(int position, int cell) => _tracks[position] is { } track && (track[cell >> 3] & (0x80 >> (cell & 7))) != 0;

    /// <summary>
    ///  Writes a cell, as the head does while it writes.
    /// </summary>
    /// <param name="position">The half-track position, 0-83.</param>
    /// <param name="cell">The cell, less than <see cref="BitCount(int)"/>.</param>
    /// <param name="value">Whether the flux changes there.</param>
    public void Write(int position, int cell, bool value)
    {
        byte[] track = _tracks[position] ?? throw new InvalidOperationException("Nothing is written at that position.");
        byte mask = (byte)(0x80 >> (cell & 7));
        byte old = track[cell >> 3];
        byte now = value ? (byte)(old | mask) : (byte)(old & ~mask);
        if (now == old) { return; }
        track[cell >> 3] = now;
        Changed();
    }

    /// <summary>
    ///  Sets a position's whole track.
    /// </summary>
    /// <param name="position">The half-track position, 0-83.</param>
    /// <param name="bits">The cells, packed eight to a byte, first in bit 7.</param>
    /// <param name="bitCount">How many cells.</param>
    /// <param name="zone">The speed zone it is written at.</param>
    /// <exception cref="ArgumentOutOfRangeException">
    ///  The count is negative, not whole bytes, more than the bits hold, or more than a G64 track's 65,535 bytes, which
    ///  the disk's snapshot could not keep.
    /// </exception>
    public void SetTrack(int position, ReadOnlySpan<byte> bits, int bitCount, int zone)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(bitCount);
        ArgumentOutOfRangeException.ThrowIfGreaterThan(bitCount, bits.Length * 8);
        ArgumentOutOfRangeException.ThrowIfGreaterThan(bitCount, MaximumTrackBytes * 8);
        if (bitCount % 8 != 0)
        {
            throw new ArgumentOutOfRangeException(nameof(bitCount), bitCount, "A track is whole bytes of cells, as a G64 keeps it.");
        }

        _tracks[position] = bitCount == 0 ? null : bits[..((bitCount + 7) / 8)].ToArray();
        _bits[position] = bitCount;
        _zones[position] = (byte)(zone & 3);
        Changed();
    }

    /// <summary>
    ///  Gets a position's cells, packed eight to a byte.
    /// </summary>
    /// <param name="position">The half-track position, 0-83.</param>
    /// <returns>The cells, or none.</returns>
    public ReadOnlySpan<byte> Track(int position) => _tracks[position];

    /// <summary>
    ///  Takes the disk with nothing written anywhere, as a new disk before formatting: each data track's position has
    ///  cells to write at its zone, all without flux changes.
    /// </summary>
    /// <returns>The disk.</returns>
    public static CommodoreDisk Blank()
    {
        CommodoreDisk disk = new();
        for (int track = 1; track <= 35; track++)
        {
            int zone = GcrLayout.Zone(track);
            int bits = GcrLayout.TrackBits(zone);
            disk.SetTrack((track - 1) * 2, new byte[(bits + 7) / 8], bits, zone);
        }

        return disk;
    }

    /// <inheritdoc/>
    public MediumSnapshot Snapshot() => new(SnapshotKind, Version, _writeProtected, G64Format.Write(this));

    /// <summary>
    ///  Records that the disk was saved to an image that holds all of it.
    /// </summary>
    public void MarkSaved() => IsDirty = false;

    /// <summary>
    ///  Records that the disk differs from its image, as after a save that could not hold all of it.
    /// </summary>
    public void MarkChanged() => IsDirty = true;

    private void Changed()
    {
        IsDirty = true;
        Version++;
    }
}
