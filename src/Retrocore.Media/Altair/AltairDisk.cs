// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media.Altair;

/// <summary>
///  An 8-inch hard-sectored disk for the Altair's 88-DCDD: 77 tracks of 32 sectors of 137 bytes, as SIMH's
///  <c>altairz80</c> and the Altair archives keep it.
/// </summary>
/// <remarks>
///  <para>
///   The image is the sectors in order, track by track, each track's in the order the disk's holes number them,
///   337,568 bytes. Many images in the archives are 96 bytes longer, a remnant of the tools that made them; the extra
///   bytes are kept as they are, so an image saves back byte for byte.
///  </para>
///  <para>
///   A sector's 137 bytes are what the controller reads, whatever the software wrote there: Altair DOS, Disk BASIC
///   and CP/M each lay their own header, data and checksum in them.
///  </para>
/// </remarks>
public sealed class AltairDisk : IMedium
{
    /// <summary>
    ///  The snapshot kind: the raw image.
    /// </summary>
    public const string SnapshotKind = "altair-dsk";

    /// <summary>
    ///  The tracks on the disk.
    /// </summary>
    public const int Tracks = 77;

    /// <summary>
    ///  The sectors on a track.
    /// </summary>
    public const int SectorsPerTrack = 32;

    /// <summary>
    ///  The bytes in a sector.
    /// </summary>
    public const int SectorBytes = 137;

    /// <summary>
    ///  The bytes of the image's sectors.
    /// </summary>
    public const int ImageBytes = Tracks * SectorsPerTrack * SectorBytes;

    /// <summary>
    ///  The bytes that follow the sectors in many images.
    /// </summary>
    public const int TrailerBytes = 96;

    private readonly byte[] _image;
    private bool _writeProtected;

    private AltairDisk(byte[] image) => _image = image;

    /// <inheritdoc/>
    public long Version { get; private set; }

    /// <inheritdoc/>
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
    ///  Gets whether the image has the 96 bytes after its sectors.
    /// </summary>
    public bool HasTrailer => _image.Length > ImageBytes;

    /// <summary>
    ///  Gets whether an image is one: 337,568 bytes, or 337,664 with the trailer.
    /// </summary>
    /// <param name="length">The image's length.</param>
    /// <returns>True for either length.</returns>
    public static bool IsImage(long length) => length is ImageBytes or ImageBytes + TrailerBytes;

    /// <summary>
    ///  Reads an image.
    /// </summary>
    /// <param name="image">The image's bytes.</param>
    /// <returns>The disk, unchanged since it was read.</returns>
    /// <exception cref="InvalidDataException">The image is not 337,568 or 337,664 bytes.</exception>
    public static AltairDisk Load(ReadOnlySpan<byte> image)
    {
        if (!IsImage(image.Length))
        {
            throw new InvalidDataException(
                $"An Altair 8-inch disk image is {ImageBytes:N0} bytes (77 tracks of 32 137-byte sectors), or "
                    + $"{ImageBytes + TrailerBytes:N0} with a trailer, not {image.Length:N0}.");
        }

        return new AltairDisk(image.ToArray());
    }

    /// <summary>
    ///  Makes a blank disk: every byte zero, as a disk no one has formatted.
    /// </summary>
    /// <returns>The disk.</returns>
    public static AltairDisk Blank() => new(new byte[ImageBytes]);

    /// <summary>
    ///  Reads a sector's bytes.
    /// </summary>
    /// <param name="track">The track, 0-76.</param>
    /// <param name="sector">The sector, 0-31.</param>
    /// <param name="bytes">Receives its 137 bytes.</param>
    public void ReadSector(int track, int sector, Span<byte> bytes) =>
        _image.AsSpan(Offset(track, sector), SectorBytes).CopyTo(bytes);

    /// <summary>
    ///  Writes a sector's bytes. Writing the bytes it already has changes nothing.
    /// </summary>
    /// <param name="track">The track, 0-76.</param>
    /// <param name="sector">The sector, 0-31.</param>
    /// <param name="bytes">Its 137 bytes.</param>
    public void WriteSector(int track, int sector, ReadOnlySpan<byte> bytes)
    {
        if (bytes.Length != SectorBytes) { throw new ArgumentException("A sector is 137 bytes.", nameof(bytes)); }
        Span<byte> target = _image.AsSpan(Offset(track, sector), SectorBytes);
        if (target.SequenceEqual(bytes)) { return; }
        bytes.CopyTo(target);
        IsDirty = true;
        Version++;
    }

    /// <summary>
    ///  Gets the image, as it would be saved.
    /// </summary>
    /// <returns>A copy of its bytes.</returns>
    public byte[] ToImage() => [.. _image];

    /// <inheritdoc/>
    public MediumSnapshot Snapshot() => new(SnapshotKind, Version, _writeProtected, ToImage());

    /// <inheritdoc/>
    public void MarkSaved() => IsDirty = false;

    /// <inheritdoc/>
    public void MarkChanged() => IsDirty = true;

    private static int Offset(int track, int sector)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(track);
        ArgumentOutOfRangeException.ThrowIfGreaterThanOrEqual(track, Tracks);
        ArgumentOutOfRangeException.ThrowIfNegative(sector);
        ArgumentOutOfRangeException.ThrowIfGreaterThanOrEqual(sector, SectorsPerTrack);
        return ((track * SectorsPerTrack) + sector) * SectorBytes;
    }
}
