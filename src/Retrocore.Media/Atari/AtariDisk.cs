// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Buffers.Binary;

namespace Retrocore.Media.Atari;

/// <summary>
///  An Atari 8-bit floppy disk as its sectors: 128-byte single or enhanced density, or 256-byte double density with
///  the three boot sectors of 128 bytes, as <c>.atr</c> and <c>.xfd</c> images hold them.
/// </summary>
/// <remarks>
///  <para>
///   An ATR file is a 16-byte header (<c>$96 $02</c>, the image's size in 16-byte paragraphs, the sector size) and
///   then the sectors in order from sector 1. In double density the first three sectors are 128 bytes, or 256 bytes
///   padded in some older images; either reads. An XFD file is single-density sectors with no header. The image
///   is saved as an ATR with the three boot sectors at 128 bytes.
///  </para>
/// </remarks>
public sealed class AtariDisk : IMedium
{
    /// <summary>
    ///  The snapshot kind: the disk as an ATR image.
    /// </summary>
    public const string SnapshotKind = "atari-disk";

    private const int HeaderSize = 16;

    private readonly byte[] _data;
    private bool _writeProtected;

    private AtariDisk(int sectorSize, int sectorCount, byte[] data, bool writeProtected)
    {
        SectorSize = sectorSize;
        SectorCount = sectorCount;
        _data = data;
        _writeProtected = writeProtected;
    }

    /// <summary>
    ///  Gets the sector size: 128, or 256 for double density.
    /// </summary>
    public int SectorSize { get; }

    /// <summary>
    ///  Gets the number of sectors: 720 single density, 1,040 enhanced density.
    /// </summary>
    public int SectorCount { get; }

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
    ///  Creates a blank, formatted disk: all sectors zero.
    /// </summary>
    /// <param name="sectorCount">The sectors: 720 for single or double density, 1,040 for enhanced density.</param>
    /// <param name="sectorSize">128, or 256 for double density.</param>
    /// <returns>The disk.</returns>
    public static AtariDisk Create(int sectorCount = 720, int sectorSize = 128)
    {
        if (sectorSize is not (128 or 256)) { throw new ArgumentOutOfRangeException(nameof(sectorSize)); }
        ArgumentOutOfRangeException.ThrowIfLessThan(sectorCount, 3);
        return new(sectorSize, sectorCount, new byte[DataSize(sectorSize, sectorCount)], writeProtected: false);
    }

    /// <summary>
    ///  Reads an ATR or XFD image.
    /// </summary>
    /// <param name="image">The image.</param>
    /// <param name="writeProtected">Whether to protect the disk from writes.</param>
    /// <returns>The disk.</returns>
    /// <exception cref="InvalidDataException">The image isn't an ATR, or whole 128-byte sectors.</exception>
    public static AtariDisk Load(ReadOnlySpan<byte> image, bool writeProtected = false)
    {
        if (IsAtr(image))
        {
            int sectorSize = BinaryPrimitives.ReadUInt16LittleEndian(image[4..]);
            if (sectorSize is not (128 or 256))
            {
                throw new InvalidDataException($"ATR sectors of {sectorSize} bytes aren't supported.");
            }

            int bytes = (BinaryPrimitives.ReadUInt16LittleEndian(image[2..]) | (image[6] << 16)) * 16;
            ReadOnlySpan<byte> body = image[HeaderSize..];
            if (bytes > body.Length) { bytes = body.Length; }
            body = body[..bytes];
            if (sectorSize == 128)
            {
                if (body.Length % 128 != 0) { throw new InvalidDataException("The ATR's sectors aren't whole."); }
                return new(128, body.Length / 128, body.ToArray(), writeProtected);
            }

            // Double density: the boot sectors are 128 bytes, or 256 padded.
            if (body.Length >= 768 && body.Length % 256 == 0 && (body.Length - 384) % 256 != 0)
            {
                int count = body.Length / 256;
                byte[] data = new byte[DataSize(256, count)];
                for (int sector = 0; sector < 3; sector++)
                {
                    body.Slice(sector * 256, 128).CopyTo(data.AsSpan(sector * 128));
                }

                body[768..].CopyTo(data.AsSpan(384));
                return new(256, count, data, writeProtected);
            }

            if (body.Length < 384 || (body.Length - 384) % 256 != 0)
            {
                throw new InvalidDataException("The ATR's sectors aren't whole.");
            }

            return new(256, 3 + ((body.Length - 384) / 256), body.ToArray(), writeProtected);
        }

        if (image.Length == 0 || image.Length % 128 != 0)
        {
            throw new InvalidDataException("An XFD image is whole 128-byte sectors.");
        }

        return new(128, image.Length / 128, image.ToArray(), writeProtected);
    }

    /// <summary>
    ///  Gets whether an image starts with an ATR header.
    /// </summary>
    /// <param name="image">The image.</param>
    /// <returns>Whether it is an ATR.</returns>
    public static bool IsAtr(ReadOnlySpan<byte> image) => image.Length >= HeaderSize && image[0] == 0x96 && image[1] == 0x02;

    /// <summary>
    ///  Gets a sector's size: 128 for the three boot sectors, else <see cref="SectorSize"/>.
    /// </summary>
    /// <param name="sector">The sector, from 1.</param>
    /// <returns>The size in bytes.</returns>
    public int SizeOf(int sector) => sector <= 3 ? 128 : SectorSize;

    /// <summary>
    ///  Reads a sector.
    /// </summary>
    /// <param name="sector">The sector, from 1.</param>
    /// <param name="destination">At least <see cref="SizeOf"/> bytes.</param>
    public void ReadSector(int sector, Span<byte> destination)
    {
        (int offset, int size) = Locate(sector);
        _data.AsSpan(offset, size).CopyTo(destination);
    }

    /// <summary>
    ///  Writes a sector.
    /// </summary>
    /// <param name="sector">The sector, from 1.</param>
    /// <param name="source">The sector's bytes, <see cref="SizeOf"/> of them.</param>
    /// <exception cref="InvalidOperationException">The disk is write-protected.</exception>
    public void WriteSector(int sector, ReadOnlySpan<byte> source)
    {
        if (_writeProtected) { throw new InvalidOperationException("The disk is write-protected."); }
        (int offset, int size) = Locate(sector);
        source[..size].CopyTo(_data.AsSpan(offset, size));
        IsDirty = true;
        Version++;
    }

    /// <summary>
    ///  Clears every sector, as formatting does.
    /// </summary>
    public void Format()
    {
        if (_writeProtected) { throw new InvalidOperationException("The disk is write-protected."); }
        Array.Clear(_data);
        IsDirty = true;
        Version++;
    }

    /// <summary>
    ///  Writes the disk as an ATR image.
    /// </summary>
    /// <returns>The image.</returns>
    public byte[] ToAtr()
    {
        byte[] image = new byte[HeaderSize + _data.Length];
        image[0] = 0x96;
        image[1] = 0x02;
        int paragraphs = _data.Length / 16;
        BinaryPrimitives.WriteUInt16LittleEndian(image.AsSpan(2), (ushort)paragraphs);
        BinaryPrimitives.WriteUInt16LittleEndian(image.AsSpan(4), (ushort)SectorSize);
        image[6] = (byte)(paragraphs >> 16);
        _data.CopyTo(image, HeaderSize);
        return image;
    }

    /// <summary>
    ///  Writes the disk as an XFD image: the sectors with no header, for single and enhanced density only.
    /// </summary>
    /// <returns>The image.</returns>
    /// <exception cref="InvalidOperationException">The disk is double density.</exception>
    public byte[] ToXfd() => SectorSize == 128
        ? (byte[])_data.Clone()
        : throw new InvalidOperationException("An XFD image holds only 128-byte sectors.");

    /// <inheritdoc/>
    public MediumSnapshot Snapshot() => new(SnapshotKind, Version, _writeProtected, ToAtr());

    /// <summary>
    ///  Records that the disk was saved to an image that holds it.
    /// </summary>
    public void MarkSaved() => IsDirty = false;

    /// <summary>
    ///  Records that the disk differs from its image, as after a save that could not hold all of it.
    /// </summary>
    public void MarkChanged() => IsDirty = true;

    private static int DataSize(int sectorSize, int sectorCount) =>
        sectorSize == 128 ? sectorCount * 128 : 384 + ((sectorCount - 3) * 256);

    private (int Offset, int Size) Locate(int sector)
    {
        if (sector < 1 || sector > SectorCount) { throw new ArgumentOutOfRangeException(nameof(sector)); }
        int offset = SectorSize == 128 || sector <= 3 ? (sector - 1) * 128 : 384 + ((sector - 4) * 256);
        return (offset, SizeOf(sector));
    }
}
