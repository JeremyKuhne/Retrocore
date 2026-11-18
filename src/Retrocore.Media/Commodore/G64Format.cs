// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Buffers.Binary;

namespace Retrocore.Media.Commodore;

/// <summary>
///  Reads and writes G64 images, VICE's GCR format: <c>GCR-1541</c>, a version byte, the half-track count, the
///  largest track's size, then for each half-track the offset of its data and its speed zone, and each track as a
///  length and its bytes, first cell in bit 7.
/// </summary>
/// <remarks>
///  <para>
///   A G64 image holds every cell, so a disk written back is the disk read. A speed entry over 3 points to a table of
///   zones by byte; a track whose bytes all have one zone reads at that zone, and one that mixes zones is refused,
///   since a disk keeps one zone a track and the rest of its timing would be lost.
///  </para>
/// </remarks>
public static class G64Format
{
    private const int HeaderSize = 12;
    private static ReadOnlySpan<byte> Signature => "GCR-1541"u8;

    /// <summary>
    ///  Gets whether bytes start as a G64 image does.
    /// </summary>
    /// <param name="image">The bytes.</param>
    /// <returns>Whether they have the signature.</returns>
    public static bool IsG64(ReadOnlySpan<byte> image) => image.StartsWith(Signature);

    /// <summary>
    ///  Reads an image.
    /// </summary>
    /// <param name="image">The file's bytes.</param>
    /// <returns>The disk.</returns>
    /// <exception cref="InvalidDataException">
    ///  The image is not a G64 image, is cut short, or has a track that mixes speed zones.
    /// </exception>
    public static CommodoreDisk Read(ReadOnlySpan<byte> image)
    {
        if (image.Length < HeaderSize || !IsG64(image))
        {
            throw new InvalidDataException("The file is not a G64 image: it does not start GCR-1541.");
        }

        int count = image[9];
        if (count > CommodoreDisk.Positions)
        {
            throw new InvalidDataException(
                $"The G64 image has {count} half-tracks; a 35-track disk holds at most {CommodoreDisk.Positions}.");
        }

        if (image.Length < HeaderSize + (count * 8))
        {
            throw new InvalidDataException("The G64 image's track tables are cut short.");
        }

        CommodoreDisk disk = new();
        for (int position = 0; position < count; position++)
        {
            uint offset = BinaryPrimitives.ReadUInt32LittleEndian(image[(HeaderSize + (position * 4))..]);
            uint speed = BinaryPrimitives.ReadUInt32LittleEndian(image[(HeaderSize + (image[9] * 4) + (position * 4))..]);
            // Only a zero offset is an absent track; one past the file's end is a file cut short.
            if (offset == 0) { continue; }
            if ((long)offset + 2 > image.Length)
            {
                throw new InvalidDataException($"The G64 image's half-track {position} starts past its end.");
            }

            int length = BinaryPrimitives.ReadUInt16LittleEndian(image[(int)offset..]);
            if (offset + 2 + length > image.Length)
            {
                throw new InvalidDataException($"The G64 image's half-track {position} runs past its end.");
            }

            int zone = speed <= 3 ? (int)speed : SpeedOf(image, speed, length, position);
            disk.SetTrack(position, image.Slice((int)offset + 2, length), length * 8, zone);
        }

        // Setting the tracks is reading the image, not a change to the disk.
        disk.MarkSaved();
        return disk;
    }

    /// <summary>
    ///  Writes a disk as a version 0 image of 84 half-tracks.
    /// </summary>
    /// <param name="disk">The disk.</param>
    /// <returns>The image.</returns>
    public static byte[] Write(CommodoreDisk disk)
    {
        ArgumentNullException.ThrowIfNull(disk);
        int positions = CommodoreDisk.Positions;
        int largest = 7928;
        for (int position = 0; position < positions; position++)
        {
            largest = Math.Max(largest, (disk.BitCount(position) + 7) / 8);
        }

        List<byte> tracks = [];
        byte[] header = new byte[HeaderSize + (positions * 8)];
        Signature.CopyTo(header);
        header[8] = 0;
        header[9] = (byte)positions;
        BinaryPrimitives.WriteUInt16LittleEndian(header.AsSpan(10), (ushort)largest);
        for (int position = 0; position < positions; position++)
        {
            int bits = disk.BitCount(position);
            if (bits == 0) { continue; }
            int offset = header.Length + tracks.Count;
            BinaryPrimitives.WriteUInt32LittleEndian(header.AsSpan(HeaderSize + (position * 4)), (uint)offset);
            BinaryPrimitives.WriteUInt32LittleEndian(header.AsSpan(HeaderSize + (positions * 4) + (position * 4)), (uint)disk.Zone(position));

            // A track's bytes, and its slot padded to the largest track's, as VICE writes them.
            int length = (bits + 7) / 8;
            tracks.Add((byte)length);
            tracks.Add((byte)(length >> 8));
            tracks.AddRange(disk.Track(position)[..length]);
            for (int pad = length; pad < largest; pad++) { tracks.Add(0); }
        }

        return [.. header, .. tracks];
    }

    // The zone of a track's bytes, from a speed table of a zone for each byte, four to a byte; all must share one.
    private static int SpeedOf(ReadOnlySpan<byte> image, uint offset, int length, int position)
    {
        // Checked as a long, so a table offset past the file, however large, is a file cut short.
        if (offset + (long)((length + 3) / 4) > image.Length)
        {
            throw new InvalidDataException($"The G64 image's speed table for half-track {position} runs past its end.");
        }

        int table = (int)offset;
        int zone = -1;
        for (int index = 0; index < length; index++)
        {
            int at = (image[table + (index / 4)] >> (6 - (2 * (index % 4)))) & 3;
            if (zone >= 0 && at != zone)
            {
                throw new InvalidDataException(
                    $"The G64 image's half-track {position} mixes speed zones {zone} and {at}, which Retrocore cannot keep; "
                        + "a disk holds one zone a track.");
            }

            zone = at;
        }

        return Math.Max(zone, 0);
    }
}
