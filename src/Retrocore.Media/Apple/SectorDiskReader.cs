// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media;

/// <summary>
///  Reads a 16-sector disk's sectors back from its bits, the reverse of <see cref="SectorDiskConverter.Convert"/>, so
///  the files on a disk the machine has written can be read, and the disk saved as a sector image.
/// </summary>
/// <remarks>
///  <para>
///   Each track is read as the Disk II's sequencer reads it: bits shift in until the top bit is set, which makes a
///   nibble. An address field (<c>D5 AA 96</c>) gives the sector's volume and number in 4-and-4, and the data field
///   after it (<c>D5 AA AD</c>) its 342 6-and-2 nibbles and a checksum. The track is read twice around, so a sector
///   across the index is read whole.
///  </para>
///  <para>
///   A sector image holds 35 to 40 whole tracks of 16 sectors and nothing else, so <see cref="Decode"/> says what of
///   the disk it could not hold: a track that does not read as 16 sectors, data on a quarter or half track the whole
///   tracks do not cover, and a volume other than the 254 a sector image is read back as. A WOZ disk has no track past
///   the 40th.
///  </para>
/// </remarks>
public static class SectorDiskReader
{
    private const int StandardTracks = 35;
    private const int MostTracks = 40;
    private const int TrackSize = 16 * 256;
    private const int StandardVolume = 254;

    /// <summary>
    ///  Reads a disk's tracks into a sector image, failing on anything that does not read.
    /// </summary>
    /// <param name="disk">The disk.</param>
    /// <param name="proDosOrder">
    ///  Whether to write the image in ProDOS's sector order (<c>.po</c>) rather than DOS's.
    /// </param>
    /// <returns>The image: 35 tracks, 143,360 bytes, or up to 40 when the disk has them.</returns>
    /// <exception cref="InvalidDataException">A track is missing a sector, or a sector's checksum is wrong.</exception>
    public static byte[] Read(WozDisk disk, bool proDosOrder)
    {
        SectorImage image = Decode(disk, proDosOrder);
        return image.Unreadable.Count == 0 ? image.Bytes : throw new InvalidDataException(image.Unreadable[0]);
    }

    /// <summary>
    ///  Reads a disk's tracks into a sector image, saying what of the disk the image cannot hold. A sector that does not
    ///  read is left as zeros.
    /// </summary>
    /// <param name="disk">The disk.</param>
    /// <param name="proDosOrder">
    ///  Whether to write the image in ProDOS's sector order (<c>.po</c>) rather than DOS's.
    /// </param>
    /// <returns>The image, its track count, and its losses.</returns>
    public static SectorImage Decode(WozDisk disk, bool proDosOrder)
    {
        ArgumentNullException.ThrowIfNull(disk);
        Span<sbyte> values = stackalloc sbyte[256];
        values.Fill(-1);
        ReadOnlySpan<byte> gcr = SectorDiskConverter.Gcr;
        for (int value = 0; value < gcr.Length; value++) { values[gcr[value]] = (sbyte)value; }

        // The whole tracks a sector image can hold: 35, or up to the last the disk has, to 40.
        int tracks = StandardTracks;
        for (int track = StandardTracks; track < MostTracks; track++)
        {
            if (disk.Track(track * 4) is not null) { tracks = track + 1; }
        }

        List<string> unreadable = [];
        List<string> losses = [];
        SortedSet<int> volumes = [];
        byte[] image = new byte[tracks * TrackSize];
        for (int track = 0; track < tracks; track++)
        {
            if (disk.Track(track * 4) is not { } bits)
            {
                unreadable.Add($"Track {track} is not formatted.");
                continue;
            }

            ReadTrack(bits, track, values, image.AsSpan(track * TrackSize, TrackSize), proDosOrder, volumes, unreadable, losses);
        }

        losses.InsertRange(0, unreadable);

        // A sector image's disk maps each whole track's quarter track below it and the one above it to it, and leaves
        // the half tracks unformatted, so any other quarter or half track is a loss: one with data of its own, a half
        // track with any, or a quarter track mapped to the other whole track beside it.
        for (int quarter = 0; quarter < 160; quarter++)
        {
            if (quarter % 4 == 0 || disk.Track(quarter) is not { } extra) { continue; }
            DiskTrack? expected = (quarter % 4) switch
            {
                1 => disk.Track(quarter - 1),
                3 when (quarter + 1) / 4 < tracks => disk.Track(quarter + 1),
                _ => null,
            };

            if (!ReferenceEquals(extra, expected))
            {
                losses.Add($"Track {quarter / 4}.{quarter % 4 * 25} holds data a sector image cannot put back there.");
            }
        }

        volumes.Remove(StandardVolume);
        if (volumes.Count != 0)
        {
            losses.Add($"The disk's volume is {string.Join(", ", volumes)}; a sector image is read back as volume {StandardVolume}.");
        }

        return new(image, tracks, losses, unreadable);
    }

    // The track's nibbles three times around, and the ones that start in the second time around: the first only
    // brings the reader into step with the nibbles, as the sequencer does, and the third finishes a sector across the
    // index.
    private static List<byte> Nibbles(DiskTrack track, out int windowStart, out int windowEnd)
    {
        List<byte> nibbles = [with(track.BitCount * 3 / 8)];
        windowStart = -1;
        windowEnd = 0;
        int shift = 0;
        int start = 0;
        for (int bit = 0; bit < track.BitCount * 3; bit++)
        {
            if (shift == 0) { start = bit; }
            shift = (shift << 1) | (track.ReadBit(bit % track.BitCount) ? 1 : 0);
            if ((shift & 0x80) != 0)
            {
                if (start >= track.BitCount && start < track.BitCount * 2)
                {
                    if (windowStart < 0) { windowStart = nibbles.Count; }
                    windowEnd = nibbles.Count + 1;
                }

                nibbles.Add((byte)shift);
                shift = 0;
            }
        }

        if (windowStart < 0) { windowStart = 0; }
        return nibbles;
    }

    // Reads a track's 16 sectors into the image. Every address field that starts in one revolution, once the reader is
    // in step, is read, so a sector found twice with other data, a sector with an ID no sector image holds, or a volume
    // on any sector, is not missed. Notes each sector's volume, the sectors that did not read, and the duplicates.
    private static void ReadTrack(
        DiskTrack bits,
        int track,
        ReadOnlySpan<sbyte> values,
        Span<byte> output,
        bool proDosOrder,
        SortedSet<int> volumes,
        List<string> unreadable,
        List<string> losses)
    {
        List<byte> nibbles = Nibbles(bits, out int windowStart, out int windowEnd);
        int found = 0;
        int bad = 0;
        int duplicated = 0;
        Span<byte> sector = stackalloc byte[256];
        for (int index = windowStart; index < windowEnd && index + 14 < nibbles.Count; index++)
        {
            if (nibbles[index] != 0xD5 || nibbles[index + 1] != 0xAA || nibbles[index + 2] != 0x96) { continue; }

            int volume = FourAndFour(nibbles, index + 3);
            int number = FourAndFour(nibbles, index + 5);
            int physical = FourAndFour(nibbles, index + 7);
            int check = FourAndFour(nibbles, index + 9);
            if ((volume ^ number ^ physical ^ check) != 0) { continue; }

            // Every whole address field's volume counts, whether or not its sector reads.
            volumes.Add(volume);

            // A sector whose address field is whole but names another track, or a sector past 15, has no place in a
            // sector image.
            if (number != track || physical > 15)
            {
                losses.Add($"Track {track} has a sector that calls itself track {number}, sector {physical}, which a sector image cannot hold.");
                index += 10;
                continue;
            }

            int data = index + 11;
            while (data + 3 < nibbles.Count
                && data < index + 60
                && (nibbles[data] != 0xD5 || nibbles[data + 1] != 0xAA || nibbles[data + 2] != 0xAD))
            {
                data++;
            }

            if (data + 3 + 343 > nibbles.Count || nibbles[data + 2] != 0xAD) { continue; }

            // A bad checksum leaves the sector to another copy of it, and the scan goes on to the sectors after it.
            index = data + 3 + 343 - 1;
            if (!DecodeSector(nibbles, data + 3, values, sector))
            {
                bad |= 1 << physical;
                continue;
            }

            int logical = physical == 15 ? 15 : physical * (proDosOrder ? 8 : 7) % 15;
            Span<byte> place = output.Slice(logical * 256, 256);
            if ((found & (1 << physical)) == 0)
            {
                sector.CopyTo(place);
                found |= 1 << physical;
            }
            else if (!sector.SequenceEqual(place))
            {
                duplicated |= 1 << physical;
            }
        }

        // One line for each track: the sectors that never read, and those whose only copies had bad checksums.
        List<int> missing = [.. Enumerable.Range(0, 16).Where(physical => (found & (1 << physical)) == 0 && (bad & (1 << physical)) == 0)];
        List<int> failed = [.. Enumerable.Range(0, 16).Where(physical => (found & (1 << physical)) == 0 && (bad & (1 << physical)) != 0)];
        if (missing.Count == 16)
        {
            unreadable.Add($"Track {track} has no readable sectors.");
        }
        else if (missing.Count + failed.Count != 0)
        {
            List<string> parts = [];
            if (missing.Count != 0) { parts.Add($"no readable sector {string.Join(", ", missing)}"); }
            if (failed.Count != 0) { parts.Add($"a bad checksum in sector {string.Join(", ", failed)}"); }
            unreadable.Add($"Track {track} has {string.Join(" and ", parts)}.");
        }

        for (int physical = 0; physical < 16; physical++)
        {
            if ((duplicated & (1 << physical)) != 0)
            {
                losses.Add($"Track {track} has more than one sector {physical}, with other data; a sector image keeps the first.");
            }
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
