// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media;

/// <summary>
///  Reads a 16-sector disk's sectors back from its bits, the reverse of <see cref="SectorDiskConverter.Convert"/>, so
///  the files on a disk the machine has written can be read.
/// </summary>
/// <remarks>
///  <para>
///   Each track is read as the Disk II's sequencer reads it: bits shift in until the top bit is set, which makes a
///   nibble. An address field (<c>D5 AA 96</c>) gives the sector's number in 4-and-4, and the data field after it
///   (<c>D5 AA AD</c>) its 342 6-and-2 nibbles and a checksum. The track is read twice around, so a sector across the
///   index is read whole.
///  </para>
/// </remarks>
public static class SectorDiskReader
{
    private const int Tracks = 35;
    private const int TrackSize = 16 * 256;

    /// <summary>
    ///  Reads a disk's 35 tracks into a sector image.
    /// </summary>
    /// <param name="disk">The disk.</param>
    /// <param name="proDosOrder">
    ///  Whether to write the image in ProDOS's sector order (<c>.po</c>) rather than DOS's.
    /// </param>
    /// <returns>The 143,360-byte image.</returns>
    /// <exception cref="InvalidDataException">A track is missing a sector, or a sector's checksum is wrong.</exception>
    public static byte[] Read(WozDisk disk, bool proDosOrder)
    {
        ArgumentNullException.ThrowIfNull(disk);
        Span<sbyte> values = stackalloc sbyte[256];
        values.Fill(-1);
        ReadOnlySpan<byte> gcr = SectorDiskConverter.Gcr;
        for (int value = 0; value < gcr.Length; value++) { values[gcr[value]] = (sbyte)value; }

        byte[] image = new byte[Tracks * TrackSize];
        for (int track = 0; track < Tracks; track++)
        {
            DiskTrack bits = disk.Track(track * 4) ?? throw new InvalidDataException($"Track {track} is not formatted.");
            ReadTrack(Nibbles(bits), track, values, image.AsSpan(track * TrackSize, TrackSize), proDosOrder);
        }

        return image;
    }

    // The track's nibbles, twice around.
    private static List<byte> Nibbles(DiskTrack track)
    {
        List<byte> nibbles = new(track.BitCount / 4);
        int shift = 0;
        for (int bit = 0; bit < track.BitCount * 2; bit++)
        {
            shift = (shift << 1) | (track.ReadBit(bit % track.BitCount) ? 1 : 0);
            if ((shift & 0x80) != 0)
            {
                nibbles.Add((byte)shift);
                shift = 0;
            }
        }

        return nibbles;
    }

    private static void ReadTrack(List<byte> nibbles, int track, ReadOnlySpan<sbyte> values, Span<byte> output, bool proDosOrder)
    {
        int found = 0;
        Span<byte> sector = stackalloc byte[256];
        for (int index = 0; index + 14 < nibbles.Count && found != 0xFFFF; index++)
        {
            if (nibbles[index] != 0xD5 || nibbles[index + 1] != 0xAA || nibbles[index + 2] != 0x96) { continue; }

            int volume = FourAndFour(nibbles, index + 3);
            int number = FourAndFour(nibbles, index + 5);
            int physical = FourAndFour(nibbles, index + 7);
            int check = FourAndFour(nibbles, index + 9);
            if ((volume ^ number ^ physical ^ check) != 0 || number != track || physical > 15) { continue; }

            int data = index + 11;
            while (data + 3 < nibbles.Count
                && data < index + 60
                && (nibbles[data] != 0xD5 || nibbles[data + 1] != 0xAA || nibbles[data + 2] != 0xAD))
            {
                data++;
            }

            if (data + 3 + 343 > nibbles.Count || nibbles[data + 2] != 0xAD) { continue; }

            if (!DecodeSector(nibbles, data + 3, values, sector))
            {
                throw new InvalidDataException($"Track {track}, sector {physical} has a bad checksum.");
            }

            int logical = physical == 15 ? 15 : physical * (proDosOrder ? 8 : 7) % 15;
            sector.CopyTo(output.Slice(logical * 256, 256));
            found |= 1 << physical;
            index = data + 3 + 343;
        }

        if (found != 0xFFFF)
        {
            int missing = System.Numerics.BitOperations.TrailingZeroCount(~found);
            throw new InvalidDataException($"Track {track} has no readable sector {missing}.");
        }
    }

    private static int FourAndFour(List<byte> nibbles, int index) => ((nibbles[index] << 1) | 1) & nibbles[index + 1];

    // The reverse of SectorDiskConverter.EncodeSector: 342 values, each the XOR of its nibble with the one before.
    private static bool DecodeSector(List<byte> nibbles, int start, ReadOnlySpan<sbyte> values, Span<byte> sector)
    {
        Span<byte> decoded = stackalloc byte[342];
        int previous = 0;
        for (int index = 0; index < 342; index++)
        {
            int value = values[nibbles[start + index]];
            if (value < 0) { return false; }
            previous ^= value;
            decoded[index] = (byte)previous;
        }

        if (values[nibbles[start + 342]] != previous) { return false; }

        for (int index = 0; index < 256; index++)
        {
            int pair = (decoded[index % 86] >> (index / 86 * 2)) & 3;
            sector[index] = (byte)((decoded[86 + index] << 2) | ((pair & 1) << 1) | (pair >> 1));
        }

        return true;
    }
}
