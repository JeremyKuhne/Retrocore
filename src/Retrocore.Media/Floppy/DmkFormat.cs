// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media.Floppy;

/// <summary>
///  DMK, David Keil's format: a 16-byte header, then each track's raw bytes as the controller reads them, led by a
///  table of the offsets of its ID address marks.
/// </summary>
/// <remarks>
///  <para>
///   The header is the write protect byte (<c>$FF</c> protected), the tracks, the track length (with its 128-byte
///   table) and options: bit 4 single-sided, bit 6 single density only, bit 7 ignore density. Each of a track's 64
///   table entries is an offset into the track, bit 15 set for a double-density ID mark, ending at 0. Unless the
///   image is single density only, a single-density byte is stored twice. Sides alternate within a cylinder.
///   A sector whose data field's stored CRC does not match its bytes reads with a CRC error, as on the disk.
///  </para>
///  <para>
///   DMK holds everything a <see cref="FloppyDisk"/> does, so it is the floppies' snapshot. The writer lays each
///   track out as a controller formats it, with IBM gaps, or with no gaps for a track too full for them, and makes
///   every track as long as the longest, at least <c>$1900</c> bytes, a 5¼-inch double-density track's.
///  </para>
/// </remarks>
public static class DmkFormat
{
    /// <summary>
    ///  The kind of a floppy disk's <see cref="MediumSnapshot"/>: a DMK image.
    /// </summary>
    public const string SnapshotKind = "dmk";

    /// <summary>
    ///  The most sectors a track holds: the entries in its table of ID marks.
    /// </summary>
    public const int MaximumSectors = TableEntries;

    private const int HeaderSize = 16;
    private const int TableEntries = 64;
    private const int TableSize = TableEntries * 2;
    private const byte IdMark = 0xFE;
    private const int StandardTrackLength = 0x1900;

    // An ID mark's offset is 14 bits, and MAME takes a track of at most $3FFF bytes.
    private const int MaximumTrackLength = 0x3FFF;

    // The largest sector a DMK reader elsewhere sizes right: they take a size code's low two bits.
    private const int LargestPortableSector = 1024;

    /// <summary>
    ///  Gets whether an image looks like DMK: a write protect byte of 0 or <c>$FF</c>, a track length that divides
    ///  the rest of the image, and no undefined option bits.
    /// </summary>
    /// <param name="image">The file's bytes.</param>
    /// <returns>Whether it is DMK.</returns>
    public static bool IsDmk(ReadOnlySpan<byte> image)
    {
        if (image.Length < HeaderSize || image[0] is not (0 or 0xFF) || (image[4] & 0x2F) != 0) { return false; }
        int length = image[2] | (image[3] << 8);
        int tracks = image[1] * ((image[4] & 0x10) != 0 ? 1 : 2);
        return length > TableEntries * 2 && tracks > 0 && image.Length >= HeaderSize + (length * tracks);
    }

    /// <summary>
    ///  Gets the length a DMK image's header gives it: the header and its tracks.
    /// </summary>
    /// <param name="image">The file's bytes, at least the header.</param>
    /// <returns>The length.</returns>
    public static int ImageLength(ReadOnlySpan<byte> image) =>
        HeaderSize + ((image[2] | (image[3] << 8)) * image[1] * ((image[4] & 0x10) != 0 ? 1 : 2));

    /// <summary>
    ///  Reads an image from a file, sizing sectors as a WD controller does but for the 8271's large sectors.
    /// </summary>
    /// <param name="image">The file's bytes.</param>
    /// <returns>The disk.</returns>
    /// <exception cref="InvalidDataException">The image is not DMK.</exception>
    public static FloppyDisk Read(ReadOnlySpan<byte> image) => Read(image, exactSizes: false);

    /// <summary>
    ///  Reads a snapshot, an image <see cref="Write"/> made, whose size codes are exact: 0 to 7 for 128 to 16384
    ///  bytes, so no size is guessed.
    /// </summary>
    /// <param name="image">The snapshot's bytes.</param>
    /// <returns>The disk.</returns>
    /// <exception cref="InvalidDataException">The image is not DMK.</exception>
    public static FloppyDisk ReadSnapshot(ReadOnlySpan<byte> image) => Read(image, exactSizes: true);

    /// <summary>
    ///  Writes a disk as a DMK file, listing what other DMK readers would not read back: sectors over 1024 bytes,
    ///  which they size by their size code's low two bits.
    /// </summary>
    /// <param name="disk">The disk.</param>
    /// <returns>The image and its losses.</returns>
    public static EncodedImage Encode(FloppyDisk disk)
    {
        ArgumentNullException.ThrowIfNull(disk);
        FloppyLosses losses = new();
        foreach ((int cylinder, _, IReadOnlyList<FloppySector> track) in disk.Tracks())
        {
            if (track.Any(sector => sector.Data.Length > LargestPortableSector))
            {
                losses.Add($"Sectors of more than {LargestPortableSector} bytes, which other DMK readers size wrongly", cylinder);
            }
        }

        return new(Write(disk), losses.ToList());
    }

    private static FloppyDisk Read(ReadOnlySpan<byte> image, bool exactSizes)
    {
        if (!IsDmk(image)) { throw new InvalidDataException("The image is not DMK."); }
        int length = image[2] | (image[3] << 8);
        bool singleSided = (image[4] & 0x10) != 0;
        bool singleOnly = (image[4] & 0x40) != 0;
        FloppyDisk disk = new() { IsWriteProtected = image[0] == 0xFF };
        int sides = singleSided ? 1 : 2;
        for (int cylinder = 0; cylinder < image[1]; cylinder++)
        {
            for (int side = 0; side < sides; side++)
            {
                ReadOnlySpan<byte> track = image.Slice(HeaderSize + (((cylinder * sides) + side) * length), length);
                ReadTrack(disk, cylinder, side, track, singleOnly, exactSizes);
            }
        }

        return disk;
    }

    /// <summary>
    ///  Writes a disk as DMK, which holds all of it.
    /// </summary>
    /// <param name="disk">The disk.</param>
    /// <returns>The file's bytes.</returns>
    public static byte[] Write(FloppyDisk disk)
    {
        ArgumentNullException.ThrowIfNull(disk);

        // A disk with no sectors is one empty track, as DMK has at least one.
        int cylinders = Math.Max(1, disk.Cylinders);
        int sides = disk.Sides;
        List<(byte[] Bytes, byte Gap)> tracks = [];
        for (int cylinder = 0; cylinder < cylinders; cylinder++)
        {
            for (int side = 0; side < sides; side++) { tracks.Add(Track(disk.Track(cylinder, side))); }
        }

        int length = Math.Max(StandardTrackLength, tracks.Max(track => track.Bytes.Length));
        byte[] image = new byte[HeaderSize + (length * tracks.Count)];
        image[0] = disk.IsWriteProtected ? (byte)0xFF : (byte)0;
        image[1] = (byte)cylinders;
        image[2] = (byte)length;
        image[3] = (byte)(length >> 8);
        image[4] = sides == 1 ? (byte)0x10 : (byte)0;
        for (int index = 0; index < tracks.Count; index++)
        {
            (byte[] bytes, byte gap) = tracks[index];
            Span<byte> track = image.AsSpan(HeaderSize + (index * length), length);
            bytes.CopyTo(track);

            // The rest of the track is gap, as the drive leaves it after the last sector.
            track[bytes.Length..].Fill(gap);
        }

        return image;
    }

    /// <summary>
    ///  Gets whether a track's sectors fit in a DMK track: at most 64, in at most 16 KB with no gaps.
    /// </summary>
    /// <param name="sectors">The sectors in rotational order.</param>
    /// <returns>True when they fit.</returns>
    internal static bool Fits(IReadOnlyList<FloppySector> sectors) =>
        sectors.Count <= TableEntries && Length(sectors, gaps: false) <= MaximumTrackLength;

    // A track's bytes, its table first, with IBM gaps when they fit and none otherwise, and the gap byte after them.
    private static (byte[] Bytes, byte Gap) Track(IReadOnlyList<FloppySector> sectors)
    {
        bool gaps = Length(sectors, gaps: true) <= MaximumTrackLength;
        List<byte> track = [.. new byte[TableSize]];
        bool firstDouble = sectors.Count == 0 || sectors[0].DoubleDensity;
        if (gaps)
        {
            // Gap 4a, the index mark and gap 1.
            int step = firstDouble ? 1 : 2;
            byte gap = Gap(firstDouble);
            Emit(track, gap, 40, step);
            Emit(track, 0x00, firstDouble ? 12 : 6, step);
            if (firstDouble) { Emit(track, 0xC2, 3, step); }
            Emit(track, 0xFC, 1, step);
            Emit(track, gap, firstDouble ? 32 : 26, step);
        }

        byte[] table = new byte[TableSize];
        for (int index = 0; index < sectors.Count; index++)
        {
            FloppySector sector = sectors[index];
            bool dd = sector.DoubleDensity;
            int step = dd ? 1 : 2;
            if (gaps) { Emit(track, 0x00, dd ? 12 : 6, step); }
            if (dd) { Emit(track, 0xA1, 3, step); }
            int pointer = track.Count | (dd ? 0x8000 : 0);
            table[index * 2] = (byte)pointer;
            table[(index * 2) + 1] = (byte)(pointer >> 8);
            ushort idCrc = IdCrc(sector);
            Emit(track, [IdMark, sector.Track, sector.Side, sector.Sector, sector.SizeCode, (byte)(idCrc >> 8), (byte)idCrc], step);
            if (gaps)
            {
                Emit(track, Gap(dd), dd ? 22 : 11, step);
                Emit(track, 0x00, dd ? 12 : 6, step);
            }

            if (dd) { Emit(track, 0xA1, 3, step); }
            Emit(track, [sector.DataAddressMark], step);
            Emit(track, sector.Data, step);

            // A sector that reads with a CRC error keeps a CRC that does not match.
            ushort crc = DataCrc(sector.DataAddressMark, sector.Data, dd);
            if (sector.CrcError) { crc = (ushort)~crc; }
            Emit(track, [(byte)(crc >> 8), (byte)crc], step);
            if (gaps) { Emit(track, Gap(dd), dd ? 24 : 12, step); }
        }

        byte[] bytes = [.. track];
        table.CopyTo(bytes, 0);
        return (bytes, Gap(sectors.Count == 0 || sectors[^1].DoubleDensity));
    }

    // A track's length: its table, and each field, a single-density byte twice.
    private static int Length(IReadOnlyList<FloppySector> sectors, bool gaps)
    {
        int length = TableSize;
        if (gaps)
        {
            length += sectors.Count == 0 || sectors[0].DoubleDensity ? 40 + 12 + 4 + 32 : (40 + 6 + 1 + 26) * 2;
        }

        foreach (FloppySector sector in sectors)
        {
            bool dd = sector.DoubleDensity;

            // The ID field and its CRC, the mark, the data and its CRC, and the A1 syncs of double density.
            int bytes = 7 + 1 + sector.Data.Length + 2 + (dd ? 6 : 0);
            if (gaps) { bytes += dd ? 12 + 22 + 12 + 24 : 6 + 11 + 6 + 12; }
            length += bytes * (dd ? 1 : 2);
        }

        return length;
    }

    private static void Emit(List<byte> track, byte value, int count, int step)
    {
        for (int index = 0; index < count * step; index++) { track.Add(value); }
    }

    private static void Emit(List<byte> track, ReadOnlySpan<byte> bytes, int step)
    {
        foreach (byte value in bytes) { Emit(track, value, 1, step); }
    }

    private static byte Gap(bool doubleDensity) => doubleDensity ? (byte)0x4E : (byte)0xFF;

    private static ushort IdCrc(FloppySector sector)
    {
        ushort crc = 0xFFFF;
        if (sector.DoubleDensity) { crc = Crc(crc, [0xA1, 0xA1, 0xA1]); }
        return Crc(crc, [IdMark, sector.Track, sector.Side, sector.Sector, sector.SizeCode]);
    }

    private static void ReadTrack(
        FloppyDisk disk,
        int cylinder,
        int side,
        ReadOnlySpan<byte> track,
        bool singleOnly,
        bool exactSizes)
    {
        for (int entry = 0; entry < TableEntries; entry++)
        {
            int pointer = track[entry * 2] | (track[(entry * 2) + 1] << 8);
            if (pointer == 0) { break; }
            bool doubleDensity = (pointer & 0x8000) != 0;
            int offset = pointer & 0x3FFF;

            // A single-density byte is doubled, except in a single-density-only image.
            int step = doubleDensity || singleOnly ? 1 : 2;
            if (offset + (7 * step) > track.Length || track[offset] != IdMark) { continue; }
            byte trackNumber = track[offset + step];
            byte sideNumber = track[offset + (2 * step)];
            byte sectorNumber = track[offset + (3 * step)];
            byte sizeCode = track[offset + (4 * step)];

            // The data mark follows within the gap after the ID field and its CRC.
            int data = offset + (7 * step);
            int limit = Math.Min(track.Length, data + (60 * step));
            while (data < limit && track[data] is not (>= 0xF8 and <= 0xFB)) { data += step; }
            if (data >= limit) { continue; }
            byte mark = track[data];

            // A snapshot, which this writer made, has exact size codes, 0 to 7 for 128 to 16384 bytes. In a file, a WD controller takes a size code's low two bits, as this does; codes 4 to 7 are the
            // 8271's own sizes, taken when that data field is all on the track with a good CRC. When its CRC is bad,
            // the short field is taken if its own CRC is good, as a WD sector's is (the last on a track has only
            // padding after it), and otherwise the large one, unless another ID field starts inside it.
            int size = 128 << (sizeCode & (exactSizes ? 7 : 3));
            if (!exactSizes
                && sizeCode is >= 4 and <= 7
                && ReadData(track, data, 128 << sizeCode, step, mark, doubleDensity) is { } large
                && (!large.CrcError
                    || (ReadData(track, data, size, step, mark, doubleDensity) is not { CrcError: false }
                        && !IdWithin(track, data, data + ((large.Bytes.Length + 3) * step)))))
            {
                size = large.Bytes.Length;
            }

            if (ReadData(track, data, size, step, mark, doubleDensity) is not (byte[] bytes, bool crcError))
            {
                continue;
            }

            FloppySector sector = new(trackNumber, sideNumber, sectorNumber, bytes, doubleDensity, mark)
            {
                CrcError = crcError
            };

            disk.Add(cylinder, side, sector);
        }
    }

    // Whether the track's ID table points at an ID field from start up to, not including, end.
    private static bool IdWithin(ReadOnlySpan<byte> track, int start, int end)
    {
        for (int entry = 0; entry < TableEntries; entry++)
        {
            int pointer = track[entry * 2] | (track[(entry * 2) + 1] << 8);
            if (pointer == 0) { break; }
            int offset = pointer & 0x3FFF;
            if (offset > start && offset < end) { return true; }
        }

        return false;
    }

    // A data field's bytes after its mark, and whether its CRC, which follows high byte first, is wrong; a track cut
    // short before the CRC is taken as good. Null when the bytes are not all on the track.
    private static (byte[] Bytes, bool CrcError)? ReadData(
        ReadOnlySpan<byte> track,
        int data,
        int size,
        int step,
        byte mark,
        bool doubleDensity)
    {
        if (data + ((size + 1) * step) > track.Length) { return null; }
        byte[] bytes = new byte[size];
        for (int index = 0; index < size; index++) { bytes[index] = track[data + ((index + 1) * step)]; }
        int crcAt = data + ((size + 1) * step);
        bool crcError = crcAt + step < track.Length
            && ((track[crcAt] << 8) | track[crcAt + step]) != DataCrc(mark, bytes, doubleDensity);

        return (bytes, crcError);
    }

    // CRC-CCITT of a data field: double density includes the three A1 sync bytes before the mark.
    private static ushort DataCrc(byte mark, ReadOnlySpan<byte> data, bool doubleDensity)
    {
        ushort crc = 0xFFFF;
        if (doubleDensity) { crc = Crc(crc, [0xA1, 0xA1, 0xA1]); }
        crc = Crc(crc, [mark]);
        return Crc(crc, data);
    }

    private static ushort Crc(ushort crc, ReadOnlySpan<byte> bytes)
    {
        foreach (byte value in bytes)
        {
            crc ^= (ushort)(value << 8);
            for (int bit = 0; bit < 8; bit++)
            {
                crc = (crc & 0x8000) != 0 ? (ushort)((crc << 1) ^ 0x1021) : (ushort)(crc << 1);
            }
        }

        return crc;
    }
}
