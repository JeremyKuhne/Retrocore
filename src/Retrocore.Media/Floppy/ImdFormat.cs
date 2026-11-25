// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media.Floppy;

/// <summary>
///  ImageDisk (IMD), Dave Dunfield's format, in which most Model II disks and many Model III and 4 disks are kept:
///  an ASCII comment ended by <c>$1A</c>, then each track as its mode, cylinder, head, sector count and size, its
///  sector numbers, and a record per sector.
/// </summary>
/// <remarks>
///  <para>
///   Modes 0-2 are single density (FM) and 3-5 double (MFM). Head bit 7 adds a map of each sector's cylinder and
///   bit 6 one of its head. A record is 0 for a sector with no data, then odd for the data and even for one byte
///   that fills it; 3-4 are deleted data, 5-6 data with a CRC error, and 7-8 both.
///  </para>
/// </remarks>
public static class ImdFormat
{
    private const byte CommentEnd = 0x1A;

    // Size code 6, the largest IMD defines.
    private const int LargestSector = 8192;

    /// <summary>
    ///  Gets whether an image looks like IMD: it starts with <c>IMD</c>.
    /// </summary>
    /// <param name="image">The file's bytes.</param>
    /// <returns>Whether it is IMD.</returns>
    public static bool IsImd(ReadOnlySpan<byte> image) => image.StartsWith("IMD"u8);

    /// <summary>
    ///  Reads an image.
    /// </summary>
    /// <param name="image">The file's bytes.</param>
    /// <returns>The disk.</returns>
    /// <exception cref="InvalidDataException">The image is not IMD or is truncated.</exception>
    public static FloppyDisk Read(ReadOnlySpan<byte> image)
    {
        FloppyDisk disk = new();
        foreach (ImdTrack track in Parse(image, out _))
        {
            for (int index = 0; index < track.Numbers.Length; index++)
            {
                if (track.Data[index] is not { } data) { continue; }
                byte record = track.Records[index];
                bool deleted = record is 3 or 4 or 7 or 8;
                FloppySector sector = new(
                    track.Cylinders.Length == 0 ? track.Cylinder : track.Cylinders[index],
                    track.Heads.Length == 0 ? (byte)track.Side : track.Heads[index],
                    track.Numbers[index],
                    data,
                    doubleDensity: track.Mode >= 3,
                    deleted ? (byte)0xF8 : (byte)0xFB)
                {
                    CrcError = record >= 5
                };

                disk.Add(track.Cylinder, track.Side, sector);
            }
        }

        return disk;
    }

    /// <summary>
    ///  Gets an image's layout, which <see cref="Encode(FloppyDisk, ReadOnlySpan{byte})"/> writes a disk back to: the
    ///  image with its sectors' data zeroed, so its comment, modes, maps, order, compression and sectors with no data
    ///  stay.
    /// </summary>
    /// <param name="image">The file's bytes.</param>
    /// <returns>The layout, itself an IMD image.</returns>
    /// <exception cref="InvalidDataException">The image is not IMD or is truncated.</exception>
    public static byte[] Layout(ReadOnlySpan<byte> image)
    {
        List<ImdTrack> tracks = Parse(image, out int commentLength);
        using MemoryStream output = new();
        output.Write(image[..commentLength]);
        foreach (ImdTrack track in tracks)
        {
            WriteHeader(output, track);
            foreach (byte record in track.Records)
            {
                // Each record as it was, so a save compresses the sectors the image did, with its data zeroed.
                output.WriteByte(record);
                if (record != 0) { output.Write(new byte[record % 2 == 1 ? 128 << track.SizeCode : 1]); }
            }
        }

        return output.ToArray();
    }

    /// <summary>
    ///  Writes a disk as IMD, listing what IMD cannot hold of it.
    /// </summary>
    /// <param name="disk">The disk.</param>
    /// <returns>The image and its losses.</returns>
    public static EncodedImage Encode(FloppyDisk disk) => Encode(disk, []);

    /// <summary>
    ///  Writes a disk as IMD in the layout of the image it was read from (<see cref="Layout"/>), listing what IMD
    ///  cannot hold of it.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   A track whose sectors are still the layout's, by ID, size and density, keeps its mode, its maps, its sector
    ///   numbers, the sectors that had no data and which sectors were compressed, and only its records change; a
    ///   track whose sectors differ from the layout's keeps the layout's data rate; one formatted again with the
    ///   same sectors in the same order is written as the layout has it. An image that lists a track twice keeps both
    ///   listings while their sectors are still the layout's, each taking its sectors in turn, and is written once
    ///   otherwise; a track the layout lacks goes in cylinder and side order. An unchanged disk
    ///   writes the image it was read from. On a new track, a sector whose bytes are all one value is written
    ///   compressed, as ImageDisk writes it.
    ///  </para>
    ///  <para>
    ///   A track has one mode and one sector size, so a sector whose density or size is not its track's first
    ///   sector's cannot be held, nor one over 8192 bytes; and a data mark is normal (<c>$FB</c>) or deleted, so
    ///   <c>$F9</c> and <c>$FA</c> are written as deleted.
    ///  </para>
    /// </remarks>
    /// <param name="disk">The disk.</param>
    /// <param name="layout">The layout, or empty for a new image.</param>
    /// <returns>The image and its losses.</returns>
    /// <exception cref="InvalidDataException">The layout is not IMD.</exception>
    public static EncodedImage Encode(FloppyDisk disk, ReadOnlySpan<byte> layout)
    {
        ArgumentNullException.ThrowIfNull(disk);
        FloppyLosses losses = new();
        List<ImdTrack> tracks = [];
        int commentLength = 0;
        if (!layout.IsEmpty) { tracks = Parse(layout, out commentLength); }

        using MemoryStream output = new();
        if (layout.IsEmpty)
        {
            string stamp = DateTime.Now.ToString("dd/MM/yyyy HH:mm:ss", System.Globalization.CultureInfo.InvariantCulture);
            output.Write(System.Text.Encoding.ASCII.GetBytes($"IMD 1.18: {stamp}\r\n"));
            output.WriteByte(CommentEnd);
        }
        else
        {
            output.Write(layout[..commentLength]);
        }

        // The data rate of a track the layout lacks: the layout's first track's, or for a new image 500 kbps, an 8-inch
        // drive's, when a track holds more than a 5¼-inch drive's 250 kbps does, and 250 kbps otherwise.
        int rate = tracks.Count != 0 ? tracks[0].Mode % 3 : disk.Tracks().Any(EightInch) ? 0 : 2;

        // Each track the layout has, in its order, takes its sectors from the disk's track in turn, as a track an
        // image lists twice is read; a track whose sectors are no longer the layout's is written anew, once.
        List<((int Cylinder, int Side) Key, byte[] Bytes)> segments = [];
        Dictionary<(int Cylinder, int Side), int> taken = [];
        HashSet<(int Cylinder, int Side)> rewritten = [];
        Dictionary<(int Cylinder, int Side), int> last = [];
        for (int index = 0; index < tracks.Count; index++)
        {
            last[(tracks[index].Cylinder, tracks[index].Side)] = index;
        }

        for (int index = 0; index < tracks.Count; index++)
        {
            ImdTrack track = tracks[index];
            (int, int) key = (track.Cylinder, track.Side);
            if (rewritten.Contains(key)) { continue; }
            IReadOnlyList<FloppySector> sectors = disk.Track(track.Cylinder, track.Side);
            int start = taken.GetValueOrDefault(key);
            using MemoryStream segment = new();
            if (Matches(track, sectors, start, all: last[key] == index) is int count)
            {
                WriteHeader(segment, track);
                int next = start;
                foreach (byte record in track.Records)
                {
                    if (record == 0) { segment.WriteByte(0); }
                    else { WriteRecord(segment, sectors[next++], record % 2 == 0, track.Cylinder, losses); }
                }

                taken[key] = start + count;
            }
            else
            {
                WriteTrack(segment, track.Cylinder, track.Side, [.. sectors.Skip(start)], track.Mode % 3, losses);
                rewritten.Add(key);
            }

            segments.Add((key, segment.ToArray()));
        }

        // The disk's tracks the layout lacks go in cylinder and side order.
        foreach ((int cylinder, int side, IReadOnlyList<FloppySector> sectors) in disk.Tracks())
        {
            (int, int) key = (cylinder, side);
            if (last.ContainsKey(key)) { continue; }
            using MemoryStream segment = new();
            WriteTrack(segment, cylinder, side, sectors, rate, losses);
            int at = segments.FindIndex(other => other.Key.CompareTo(key) > 0);
            segments.Insert(at < 0 ? segments.Count : at, (key, segment.ToArray()));
        }

        foreach ((_, byte[] bytes) in segments) { output.Write(bytes); }
        return new(output.ToArray(), losses.ToList());
    }

    // Whether a track holds more than a 5¼-inch track at 250 kbps: ten 256-byte sectors in single density, or ten
    // 512-byte sectors in double, as the Kaypro's are; the Model II's 8-inch disks hold 26 sectors.
    private static bool EightInch((int Cylinder, int Side, IReadOnlyList<FloppySector> Sectors) track) =>
        Bytes(track.Sectors, doubleDensity: false) > 10 * 256 || Bytes(track.Sectors, doubleDensity: true) > 10 * 512;

    private static int Bytes(IReadOnlyList<FloppySector> sectors, bool doubleDensity) =>
        sectors.Where(sector => sector.DoubleDensity == doubleDensity).Sum(sector => sector.Data.Length);

    // How many of a disk track's sectors, from start, are still a layout track's: those with data, in order, by ID,
    // size and density, and, for the last time the image lists the track, all the rest. Null when they are not.
    private static int? Matches(ImdTrack track, IReadOnlyList<FloppySector> sectors, int start, bool all)
    {
        int next = start;
        for (int index = 0; index < track.Records.Length; index++)
        {
            if (track.Records[index] == 0) { continue; }
            if (next == sectors.Count) { return null; }
            FloppySector sector = sectors[next++];
            byte cylinder = track.Cylinders.Length == 0 ? track.Cylinder : track.Cylinders[index];
            byte head = track.Heads.Length == 0 ? (byte)track.Side : track.Heads[index];
            if (sector.Track != cylinder
                || sector.Side != head
                || sector.Sector != track.Numbers[index]
                || sector.Data.Length != 128 << track.SizeCode
                || sector.DoubleDensity != track.Mode >= 3)
            {
                return null;
            }
        }

        return all && next != sectors.Count ? null : next - start;
    }

    // A track the layout does not have as it is: its first sector's density and size, at the data rate given.
    private static void WriteTrack(
        MemoryStream output,
        int cylinder,
        int side,
        IReadOnlyList<FloppySector> sectors,
        int rate,
        FloppyLosses losses)
    {
        List<FloppySector> kept = [];
        foreach (FloppySector sector in sectors)
        {
            if (sector.Data.Length > LargestSector)
            {
                losses.Add($"Sectors of more than {LargestSector} bytes", cylinder);
                continue;
            }

            if (kept.Count != 0 && (sector.Data.Length != kept[0].Data.Length || sector.DoubleDensity != kept[0].DoubleDensity))
            {
                losses.Add("Sectors of another size or density than their track's first", cylinder);
                continue;
            }

            kept.Add(sector);
        }

        bool doubleDensity = kept.Count != 0 && kept[0].DoubleDensity;
        bool cylinderMap = kept.Any(sector => sector.Track != cylinder);
        bool headMap = kept.Any(sector => sector.Side != side);
        ImdTrack track = new(
            (byte)(rate + (doubleDensity ? 3 : 0)),
            (byte)cylinder,
            side,
            (byte)(side | (cylinderMap ? 0x80 : 0) | (headMap ? 0x40 : 0)),
            kept.Count == 0 ? (byte)0 : kept[0].SizeCode,
            [.. kept.Select(sector => sector.Sector)],
            cylinderMap ? [.. kept.Select(sector => sector.Track)] : [],
            headMap ? [.. kept.Select(sector => sector.Side)] : [],
            [],
            []);

        WriteHeader(output, track);
        foreach (FloppySector sector in kept) { WriteRecord(output, sector, compress: true, cylinder, losses); }
    }

    private static void WriteHeader(MemoryStream output, ImdTrack track)
    {
        output.Write([track.Mode, track.Cylinder, track.Head, (byte)track.Numbers.Length, track.SizeCode]);
        output.Write(track.Numbers);
        output.Write(track.Cylinders);
        output.Write(track.Heads);
    }

    // A sector's record: 1 for data, 3 deleted, 5 with a CRC error, 7 both, and one more for a sector of one byte,
    // which is compressed when it may be. $F9 and $FA are written as deleted, which is a loss.
    private static void WriteRecord(MemoryStream output, FloppySector sector, bool compress, int cylinder, FloppyLosses losses)
    {
        if (sector.DataAddressMark is 0xF9 or 0xFA)
        {
            losses.Add("Data address marks $F9 and $FA, which IMD writes as deleted ($F8)", cylinder);
        }

        ReadOnlySpan<byte> data = sector.Data;
        int record = 1 + (sector.DataAddressMark != 0xFB ? 2 : 0) + (sector.CrcError ? 4 : 0);
        bool filled = compress && !data.ContainsAnyExcept(data[0]);
        output.WriteByte((byte)(record + (filled ? 1 : 0)));
        if (filled) { output.WriteByte(data[0]); }
        else { output.Write(data); }
    }

    // The comment's length, through its $1A, and each track as the image has it.
    private static List<ImdTrack> Parse(ReadOnlySpan<byte> image, out int commentLength)
    {
        if (!IsImd(image)) { throw new InvalidDataException("An IMD image starts with \"IMD\"."); }
        int offset = image.IndexOf(CommentEnd);
        if (offset < 0) { throw new InvalidDataException("An IMD image's comment ends with $1A."); }
        offset++;
        commentLength = offset;
        List<ImdTrack> tracks = [];
        while (offset < image.Length)
        {
            Need(image, offset, 5);
            byte mode = image[offset];
            byte cylinder = image[offset + 1];
            byte head = image[offset + 2];
            int count = image[offset + 3];
            byte sizeCode = image[offset + 4];
            offset += 5;
            if (sizeCode > 6)
            {
                throw new InvalidDataException("IMD sectors larger than 8192 bytes are not supported.");
            }

            int size = 128 << sizeCode;
            Need(image, offset, count);
            byte[] numbers = image.Slice(offset, count).ToArray();
            offset += count;
            byte[] cylinders = [];
            byte[] heads = [];
            if ((head & 0x80) != 0)
            {
                Need(image, offset, count);
                cylinders = image.Slice(offset, count).ToArray();
                offset += count;
            }

            if ((head & 0x40) != 0)
            {
                Need(image, offset, count);
                heads = image.Slice(offset, count).ToArray();
                offset += count;
            }

            byte[] records = new byte[count];
            byte[]?[] data = new byte[count][];
            for (int index = 0; index < count; index++)
            {
                Need(image, offset, 1);
                byte record = image[offset++];
                if (record > 8) { throw new InvalidDataException($"IMD sector record {record} is not defined."); }
                records[index] = record;
                if (record == 0) { continue; }
                byte[] bytes = new byte[size];
                if (record % 2 == 1)
                {
                    Need(image, offset, size);
                    image.Slice(offset, size).CopyTo(bytes);
                    offset += size;
                }
                else
                {
                    Need(image, offset, 1);
                    bytes.AsSpan().Fill(image[offset++]);
                }

                data[index] = bytes;
            }

            tracks.Add(new(mode, cylinder, head & 1, head, sizeCode, numbers, cylinders, heads, records, data));
        }

        return tracks;
    }

    private static void Need(ReadOnlySpan<byte> image, int offset, int length)
    {
        if (offset + length > image.Length) { throw new InvalidDataException("The IMD image is truncated."); }
    }

}
