// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media.Trs80;

/// <summary>
///  One sector as a floppy controller sees it: its ID field, recording density, data address mark and data.
/// </summary>
/// <remarks>
///  <para>
///   A sector changes only through its disk's <see cref="FloppyDisk.Write"/>, which counts the change, so a disk
///   knows when it differs from its image.
///  </para>
/// </remarks>
public sealed class FloppySector
{
    private readonly byte[] _data;
    private bool _crcError;

    /// <summary>
    ///  Creates a sector.
    /// </summary>
    /// <param name="track">The track number in its ID field.</param>
    /// <param name="side">The side number in its ID field.</param>
    /// <param name="sector">The sector number in its ID field.</param>
    /// <param name="data">
    ///  The data, which the sector copies; its length, 128, 256, 512 or 1024, is the sector size.
    /// </param>
    /// <param name="doubleDensity">Whether the sector is recorded in double density (MFM).</param>
    /// <param name="dataAddressMark">The data address mark: <c>$FB</c> normal, <c>$F8</c>-<c>$FA</c> deleted.</param>
    /// <exception cref="ArgumentException">The data is not a sector size, or the mark is not a data mark.</exception>
    public FloppySector(byte track, byte side, byte sector, ReadOnlySpan<byte> data, bool doubleDensity, byte dataAddressMark = 0xFB)
    {
        if (data.Length is not (128 or 256 or 512 or 1024))
        {
            throw new ArgumentException("A sector holds 128, 256, 512 or 1024 bytes.", nameof(data));
        }

        CheckMark(dataAddressMark);
        Track = track;
        Side = side;
        Sector = sector;
        _data = data.ToArray();
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
    ///  Gets the sector data.
    /// </summary>
    public ReadOnlySpan<byte> Data => _data;

    /// <summary>
    ///  Gets the ID field's size code: 0 for 128 bytes, 1 for 256, 2 for 512, 3 for 1024.
    /// </summary>
    public byte SizeCode => (byte)(System.Numerics.BitOperations.Log2((uint)_data.Length) - 7);

    /// <summary>
    ///  Gets whether the sector is recorded in double density.
    /// </summary>
    public bool DoubleDensity { get; }

    /// <summary>
    ///  Gets the data address mark.
    /// </summary>
    public byte DataAddressMark { get; private set; }

    /// <summary>
    ///  Gets whether reading the data reports a CRC error.
    /// </summary>
    public bool CrcError
    {
        get => _crcError;
        init => _crcError = value;
    }

    /// <summary>
    ///  Writes the data field: new data and mark, recorded with a good CRC.
    /// </summary>
    /// <param name="data">The data, the sector's size.</param>
    /// <param name="dataAddressMark">The data address mark.</param>
    internal void Overwrite(ReadOnlySpan<byte> data, byte dataAddressMark)
    {
        if (data.Length != _data.Length)
        {
            throw new ArgumentException($"The sector holds {_data.Length} bytes.", nameof(data));
        }

        CheckMark(dataAddressMark);
        data.CopyTo(_data);
        DataAddressMark = dataAddressMark;
        _crcError = false;
    }

    private static void CheckMark(byte dataAddressMark)
    {
        if (dataAddressMark is < 0xF8 or > 0xFB)
        {
            throw new ArgumentException("A data address mark is $F8 to $FB.", nameof(dataAddressMark));
        }
    }
}
