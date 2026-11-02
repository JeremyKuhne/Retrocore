// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media.Trs80;

/// <summary>
///  One sector as a floppy controller sees it: its ID field, recording density, data address mark and data.
/// </summary>
public sealed class FloppySector
{
    /// <summary>
    ///  Creates a sector.
    /// </summary>
    /// <param name="track">The track number in its ID field.</param>
    /// <param name="side">The side number in its ID field.</param>
    /// <param name="sector">The sector number in its ID field.</param>
    /// <param name="data">The data; its length, 128, 256, 512 or 1024, is the sector size.</param>
    /// <param name="doubleDensity">Whether the sector is recorded in double density (MFM).</param>
    /// <param name="dataAddressMark">The data address mark: <c>$FB</c> normal, <c>$F8</c>-<c>$FA</c> deleted.</param>
    /// <exception cref="ArgumentException">The data is not a sector size, or the mark is not a data mark.</exception>
    public FloppySector(byte track, byte side, byte sector, byte[] data, bool doubleDensity, byte dataAddressMark = 0xFB)
    {
        ArgumentNullException.ThrowIfNull(data);
        if (data.Length is not (128 or 256 or 512 or 1024))
        {
            throw new ArgumentException("A sector holds 128, 256, 512 or 1024 bytes.", nameof(data));
        }

        if (dataAddressMark is < 0xF8 or > 0xFB)
        {
            throw new ArgumentException("A data address mark is $F8 to $FB.", nameof(dataAddressMark));
        }

        Track = track;
        Side = side;
        Sector = sector;
        Data = data;
        DoubleDensity = doubleDensity;
        DataAddressMark = dataAddressMark;
    }

    /// <summary>
    ///  Gets the track number in the ID field.
    /// </summary>
    public byte Track { get; }

    /// <summary>
    ///  Gets the side number in the ID field.
    /// </summary>
    public byte Side { get; }

    /// <summary>
    ///  Gets the sector number in the ID field.
    /// </summary>
    public byte Sector { get; }

    /// <summary>
    ///  Gets the sector data, which writes change in place.
    /// </summary>
    public byte[] Data { get; }

    /// <summary>
    ///  Gets the ID field's size code: 0 for 128 bytes, 1 for 256, 2 for 512, 3 for 1024.
    /// </summary>
    public byte SizeCode => (byte)(System.Numerics.BitOperations.Log2((uint)Data.Length) - 7);

    /// <summary>
    ///  Gets whether the sector is recorded in double density.
    /// </summary>
    public bool DoubleDensity { get; }

    /// <summary>
    ///  Gets or sets the data address mark; a controller's write sets it.
    /// </summary>
    public byte DataAddressMark { get; set; }

    /// <summary>
    ///  Gets or sets whether reading the data reports a CRC error.
    /// </summary>
    public bool CrcError { get; set; }
}
