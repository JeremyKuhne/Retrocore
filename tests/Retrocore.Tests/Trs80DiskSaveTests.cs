// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug;
using Retrocore.Machines.Chips;
using Retrocore.Machines.Trs80;
using Retrocore.Media;
using Retrocore.Media.Floppy;
using Retrocore.Media.Trs80;
using System.Text.Json.Nodes;

namespace Retrocore.Tests;

/// <summary>
///  TRS-80 disks save back to their images in their own formats: IMD with its comment, modes, maps, compression and
///  sectors with no data, DMK with its tracks' bytes and ID offsets, JV3 and JV1; and a sector the controller writes
///  reaches the saved image.
/// </summary>
[TestClass]
public sealed class Trs80DiskSaveTests
{
    private const ushort Command = 0x37EC;
    private const ushort SectorRegister = 0x37EE;
    private const ushort DataRegister = 0x37EF;

    private static readonly byte[] s_comment = [.. "IMD 1.18: 01/02/1985 12:00:00\r\nA test disk\r\n"u8, 0x1A];

    private static string s_root = "";

    /// <summary>
    ///  Makes the tests' folder.
    /// </summary>
    /// <param name="context">The test context.</param>
    [ClassInitialize]
    public static void Initialize(TestContext context)
    {
        _ = context;
        s_root = Path.Join(Path.GetTempPath(), $"retrocore-trs80-saves-{Environment.ProcessId}");
        Directory.CreateDirectory(s_root);
    }

    /// <summary>
    ///  Removes the tests' folder.
    /// </summary>
    [ClassCleanup]
    public static void Cleanup() => Directory.Delete(s_root, recursive: true);

    /// <summary>
    ///  An unchanged IMD disk writes back the image it was read from, byte for byte: its comment, each track's mode
    ///  and maps, compressed and uncompressed sectors, deleted and CRC-error records, a sector with no data and an
    ///  empty track. A new image holds the same sectors.
    /// </summary>
    [TestMethod]
    public void ImdRoundTrips()
    {
        byte[] image = Imd();
        FloppyDisk disk = ImdFormat.Read(image);
        EncodedImage back = ImdFormat.Encode(disk, ImdFormat.Layout(image));
        back.IsLossless.Should().BeTrue();
        back.Bytes.Should().Equal(image);

        FloppySector deleted = disk.Track(0, 0)[2];
        deleted.DataAddressMark.Should().Be(0xF8);
        disk.Track(0, 0)[3].CrcError.Should().BeTrue();
        disk.Track(0, 1)[1].Track.Should().Be(7, "the cylinder map names it");

        EncodedImage fresh = ImdFormat.Encode(disk);
        fresh.IsLossless.Should().BeTrue();
        fresh.Bytes.AsSpan().StartsWith("IMD 1.18: "u8).Should().BeTrue();
        Describe(ImdFormat.Read(fresh.Bytes)).Should().Equal(Describe(disk));
    }

    /// <summary>
    ///  A written sector changes only its record, compressed where the image compressed it and its bytes are all one
    ///  value; a track formatted anew
    ///  keeps its track's data rate in the density it now has; and a new image's rate follows its tracks' size.
    /// </summary>
    [TestMethod]
    public void ImdKeepsItsLayoutThroughChanges()
    {
        byte[] image = Imd();
        byte[] layout = ImdFormat.Layout(image);
        FloppyDisk disk = ImdFormat.Read(image);

        // Sector 1, stored whole, stays whole though it now fills with one byte; sector 3 stays compressed while it
        // fills with one byte, and is written whole once it does not.
        disk.Write(disk.Track(0, 0)[0], Filled(256, 0x11), 0xFB);
        disk.Write(disk.Track(0, 0)[1], Filled(256, 0x22), 0xFB);
        byte[] written = ImdFormat.Encode(disk, layout).Bytes;
        written.AsSpan().StartsWith(s_comment).Should().BeTrue("the comment stays");
        written.Length.Should().Be(image.Length, "each sector is stored as it was");
        Describe(ImdFormat.Read(written)).Should().Equal(Describe(disk));
        disk.Write(disk.Track(0, 0)[1], Sector(0, 0, 3, 256, doubleDensity: false).Data, 0xFB);
        ImdFormat.Encode(disk, layout).Bytes.Length.Should().Be(image.Length + 255, "sector 3 no longer fills with one byte");

        // Formatting track 0 side 0 in double density keeps its 250 kbps rate: mode 5. Track 2 at 500 kbps in single
        // density is mode 0.
        disk.Format(0, 0, [.. Enumerable.Range(1, 18).Select(number => Sector(0, 0, number, 256, doubleDensity: true))]);
        disk.Format(2, 0, [Sector(2, 0, 1, 128, doubleDensity: false)]);
        byte[] formatted = ImdFormat.Encode(disk, layout).Bytes;
        Modes(formatted).Should().Equal([(0, 0, 5), (0, 1, 5), (1, 0, 0), (2, 0, 0)]);
        Describe(ImdFormat.Read(formatted)).Should().Equal(Describe(disk));

        // A new image is at 250 kbps, unless a track holds more than a 5¼-inch disk's, as an 8-inch disk's does.
        Modes(ImdFormat.Encode(Jv1Format.Read(new byte[10 * 256])).Bytes).Should().Equal([(0, 0, 2)]);
        FloppyDisk eightInch = new();
        foreach (int number in Enumerable.Range(1, 26))
        {
            eightInch.Add(0, 0, Sector(0, 0, number, 128, doubleDensity: false));
        }

        Modes(ImdFormat.Encode(eightInch).Bytes).Should().Equal([(0, 0, 0)]);
    }

    /// <summary>
    ///  A track has one mode and size, so IMD lists a sector of another size or density than its track's first, and
    ///  writes the user-defined marks <c>$F9</c> and <c>$FA</c> as deleted.
    /// </summary>
    [TestMethod]
    public void ImdListsWhatItCannotHold()
    {
        FloppyDisk disk = new();
        disk.Add(0, 0, Sector(0, 0, 1, 256, doubleDensity: false, mark: 0xFA));
        disk.Add(0, 0, Sector(0, 0, 2, 128, doubleDensity: false));
        disk.Add(1, 0, Sector(1, 0, 1, 256, doubleDensity: false));
        disk.Add(1, 0, Sector(1, 0, 2, 256, doubleDensity: true));
        EncodedImage encoded = ImdFormat.Encode(disk);
        encoded.Losses.Should().Equal(
            "Data address marks $F9 and $FA, which IMD writes as deleted ($F8), on track 0.",
            "Sectors of another size or density than their track's first, on tracks 0-1.");

        FloppyDisk read = ImdFormat.Read(encoded.Bytes);
        read.Track(0, 0).Should().ContainSingle().Which.DataAddressMark.Should().Be(0xF8);
        read.Track(1, 0).Should().ContainSingle();
    }

    /// <summary>
    ///  An unchanged DMK disk writes back the image it was read from, byte for byte: its gaps, an ID field with no
    ///  data, which no sector holds, and a CRC error's CRC. A written sector changes only its data field, where it was;
    ///  a track formatted anew is laid out again, and the others stay as they were.
    /// </summary>
    [TestMethod]
    public void DmkKeepsItsLayout()
    {
        byte[] image = Dmk(out int length);
        FloppyDisk disk = DmkFormat.Read(image);
        byte[] layout = DmkFormat.Layout(image);
        DmkFormat.Encode(disk, layout).Bytes.Should().Equal(image);

        // Sector 2 of track 0, a 256-byte double-density sector.
        FloppySector sector = disk.Track(0, 0)[1];
        disk.Write(sector, Filled(256, 0x5A), 0xF8);
        byte[] written = DmkFormat.Encode(disk, layout).Bytes;
        written.Length.Should().Be(image.Length);
        int[] changed = [.. Enumerable.Range(0, image.Length).Where(index => written[index] != image[index])];
        changed.Should().NotBeEmpty();
        (changed[^1] - changed[0]).Should().BeLessThan(1 + 256 + 2, "only the mark, data and CRC change");
        Describe(DmkFormat.Read(written)).Should().Equal(Describe(disk));

        // Formatting cylinder 1 lays it out again; cylinder 0 keeps its bytes. Cylinder 3 is past the image's tracks.
        disk.Format(1, 0, [Sector(1, 0, 9, 256, doubleDensity: true)]);
        disk.Format(3, 0, [Sector(3, 0, 1, 256, doubleDensity: true)]);
        byte[] formatted = DmkFormat.Encode(disk, layout).Bytes;
        formatted[1].Should().Be(4, "the image grows to four cylinders");
        formatted.AsSpan(16, length).SequenceEqual(written.AsSpan(16, length)).Should().BeTrue();
        Describe(DmkFormat.Read(formatted)).Should().Equal(Describe(disk));
    }

    /// <summary>
    ///  The codecs: <c>.imd</c> saves as IMD, and a codec for an image that was read keeps its layout, which a codec
    ///  made from the layout alone, as a recovery journal makes it, writes the same.
    /// </summary>
    [TestMethod]
    public void CodecsKeepTheImagesLayout()
    {
        FloppyImageCodec.For(".imd", [])?.Format.Should().Be("IMD");
        byte[] imd = Imd();
        FloppyDisk disk = ImdFormat.Read(imd);
        FloppyImageCodec codec = FloppyImageCodec.ForImage("IMD", imd) ?? throw new InvalidOperationException();
        codec.Encode(disk.Snapshot()).Bytes.Should().Equal(imd);
        FloppyImageCodec again = FloppyImageCodec.ForLayout("IMD", codec.Layout ?? []) ?? throw new InvalidOperationException();
        again.Encode(disk.Snapshot()).Bytes.Should().Equal(imd);

        byte[] dmk = Dmk(out _);
        FloppyDisk fromDmk = DmkFormat.Read(dmk);
        FloppyImageCodec dmkCodec = FloppyImageCodec.ForImage("DMK", dmk) ?? throw new InvalidOperationException();
        dmkCodec.Encode(fromDmk.Snapshot()).Bytes.Should().Equal(dmk);
        (FloppyImageCodec.ForLayout("DMK", dmkCodec.Layout ?? []) ?? throw new InvalidOperationException())
            .Encode(fromDmk.Snapshot()).Bytes.Should().Equal(dmk);

        FloppyImageCodec.ForLayout("JV3", []).Should().BeNull();
    }

    /// <summary>
    ///  A Model I writes a sector through its FD1771 to a disk read from each format; the host saves it to its image,
    ///  which reads back with the sector written and the rest as it was.
    /// </summary>
    /// <param name="extension">The image's extension.</param>
    [TestMethod]
    [DataRow(".dmk")]
    [DataRow(".imd")]
    [DataRow(".jv3")]
    [DataRow(".dsk")]
    public void ControllerWritesReachTheSavedImage(string extension)
    {
        FloppyDisk blank = new();
        foreach (int cylinder in Enumerable.Range(0, 2))
        {
            foreach (int number in Enumerable.Range(0, 10))
            {
                blank.Add(cylinder, 0, Sector(cylinder, 0, number, 256, doubleDensity: false));
            }
        }

        byte[] bytes = extension switch
        {
            ".dmk" => DmkFormat.Write(blank),
            ".imd" => ImdFormat.Encode(blank).Bytes,
            ".jv3" => Jv3Format.Write(blank),
            _ => Jv1Format.Write(blank),
        };

        string path = Path.Join(s_root, $"written-{Guid.NewGuid():N}{extension}");
        File.WriteAllBytes(path, bytes);
        Trs80Machine machine = Trs80MachineTests.Create(new());
        FloppyDrive drive = machine.Drives[0];
        FloppyMedia.Insert(drive, path, FloppyFamily.Trs80);
        string format = drive.Media?.Format ?? throw new InvalidOperationException("The drive is empty.");

        byte[] data = [.. Enumerable.Range(0, 256).Select(index => (byte)(index ^ 0xA5))];
        Trs80Bus bus = machine.Bus;
        bus.Write(0x37E1, 0x01);
        bus.Write(SectorRegister, 6);
        bus.Write(Command, 0xA8);
        bus.Tick();
        Write(bus, data).Should().Be(0, "the write ends without error");
        drive.Media?.Changed.Should().BeTrue();

        JsonObject answer = MediaActions.Save(drive, new() { ["supportsRetrocoreMedia"] = true });
        answer.String("outcome").Should().Be("saved");
        drive.Media?.Changed.Should().BeFalse();
        byte[] saved = File.ReadAllBytes(path);
        if (extension is ".dmk" or ".dsk") { saved.Length.Should().Be(bytes.Length); }

        (FloppyDisk read, string readFormat) = Trs80DiskImage.Read(saved, extension);
        readFormat.Should().Be(format);
        read.Track(0, 0)[6].Data.ToArray().Should().Equal(data);
        blank.Write(blank.Track(0, 0)[6], data, 0xFB);
        Describe(read).Should().Equal(Describe(blank));
    }

    /// <summary>
    ///  Each DOS image saves back byte for byte when nothing changed it, as DMK and IMD, and to the same sectors as
    ///  JV3. The images are in <c>trs80-disks</c> under <see cref="ExternalTestData.Root"/>; the test is inconclusive
    ///  without one.
    /// </summary>
    /// <param name="image">The image's file name.</param>
    [TestMethod]
    [DataRow("TRSDOS13.dmk")]
    [DataRow("TRSDOS13.imd")]
    [DataRow("LDOS513.dsk")]
    [DataRow("TRSDOS60.dmk")]
    [DataRow("TRSDOS60.imd")]
    [DataRow("TRSDOS62.imd")]
    [DataRow("LSDOS63J.dsk")]
    public void DosImagesSaveBackAsTheyWere(string image)
    {
        string path = Path.Join(ExternalTestData.Root, "trs80-disks", image);
        if (!File.Exists(path)) { Assert.Inconclusive($"{path} is missing."); }

        byte[] bytes = File.ReadAllBytes(path);
        (FloppyDisk disk, string format) = Trs80DiskImage.Read(bytes, Path.GetExtension(path));
        FloppyImageCodec codec = FloppyImageCodec.ForImage(format, bytes) ?? throw new InvalidOperationException(format);
        EncodedImage encoded = codec.Encode(disk.Snapshot());
        encoded.IsLossless.Should().BeTrue();
        if (format is "DMK" or "IMD") { encoded.Bytes.Should().Equal(bytes); }
        Describe(Trs80DiskImage.Read(encoded.Bytes, Path.GetExtension(path)).Disk).Should().Equal(Describe(disk));
    }

    /// <summary>
    ///  Moves bytes to the data register on each DRQ until the command ends.
    /// </summary>
    /// <param name="bus">The bus.</param>
    /// <param name="data">The bytes.</param>
    /// <returns>The status at the end.</returns>
    private static byte Write(Trs80Bus bus, byte[] data)
    {
        int next = 0;
        for (int cycle = 0; cycle < 10 * Trs80Timing.ClockHertz && bus.Disks.IsBusy; cycle++)
        {
            bus.Tick();
            if ((bus.Disks.Peek(0) & 0x02) == 0) { continue; }
            bus.Write(DataRegister, next < data.Length ? data[next++] : (byte)0);
        }

        return bus.Disks.Peek(0);
    }

    // An IMD image of every kind of record: track 0 side 0 in FM at 250 kbps with stored, compressed, deleted,
    // CRC-error and no-data sectors; side 1 in MFM with cylinder and head maps and a filled sector stored whole;
    // cylinder 1 empty at 500 kbps; and cylinder 2 in MFM at 500 kbps with 1024-byte sectors.
    private static byte[] Imd()
    {
        List<byte> image = [.. s_comment];
        image.AddRange([2, 0, 0, 5, 1, 1, 3, 2, 4, 5]);
        image.Add(1);
        image.AddRange(Sector(0, 0, 1, 256, doubleDensity: false).Data.ToArray());
        image.AddRange([2, 0xE5]);
        image.Add(3);
        image.AddRange(Sector(0, 0, 2, 256, doubleDensity: false).Data.ToArray());
        image.AddRange([5]);
        image.AddRange(Sector(0, 0, 4, 256, doubleDensity: false).Data.ToArray());
        image.Add(0);

        image.AddRange([5, 0, 1 | 0x80 | 0x40, 2, 2, 1, 2, 0, 7, 1, 0]);
        image.Add(1);
        image.AddRange(new byte[512]);
        image.Add(1);
        image.AddRange(Sector(7, 0, 2, 512, doubleDensity: true).Data.ToArray());

        image.AddRange([0, 1, 0, 0, 0]);

        image.AddRange([3, 2, 0, 1, 3, 1, 7]);
        image.AddRange(Sector(2, 0, 1, 1024, doubleDensity: true).Data.ToArray());
        return [.. image];
    }

    // Each track's cylinder, side and mode.
    private static List<(int Cylinder, int Side, int Mode)> Modes(byte[] image)
    {
        List<(int, int, int)> modes = [];
        int offset = image.AsSpan().IndexOf((byte)0x1A) + 1;
        while (offset < image.Length)
        {
            byte mode = image[offset];
            byte cylinder = image[offset + 1];
            byte head = image[offset + 2];
            int count = image[offset + 3];
            int size = 128 << image[offset + 4];
            modes.Add((cylinder, head & 1, mode));
            offset += 5 + count + ((head & 0x80) != 0 ? count : 0) + ((head & 0x40) != 0 ? count : 0);
            for (int index = 0; index < count; index++)
            {
                byte record = image[offset++];
                offset += record == 0 ? 0 : record % 2 == 1 ? size : 1;
            }
        }

        return modes;
    }

    // A DMK image of two cylinders, one side, whose layout this writer would not make: gap 4a written as $37, and
    // an ID field after cylinder 1's last sector with no data field. Its track 0 has a sector with a CRC error.
    private static byte[] Dmk(out int length)
    {
        FloppyDisk disk = new();
        disk.Add(0, 0, Sector(0, 0, 1, 256, doubleDensity: true));
        disk.Add(0, 0, Sector(0, 0, 2, 256, doubleDensity: true));
        disk.Add(0, 0, new FloppySector(0, 0, 3, Filled(256, 0x99), doubleDensity: true) { CrcError = true });
        disk.Add(1, 0, Sector(1, 0, 1, 128, doubleDensity: false, mark: 0xFA));
        byte[] image = DmkFormat.Write(disk);
        length = image[2] | (image[3] << 8);
        const int Table = 128;
        image.AsSpan(16 + Table, 40).Fill(0x37);

        // An ID mark near the end of cylinder 1, in the gap, listed in the table's second entry.
        int track = 16 + length;
        int id = length - 40;
        image.AsSpan(track + id, 14).Fill(0xFE);
        image[track + 2] = (byte)id;
        image[track + 3] = (byte)(id >> 8);
        return image;
    }

    private static FloppySector Sector(int track, int side, int sector, int size, bool doubleDensity, byte mark = 0xFB)
    {
        byte[] data = new byte[size];
        new Random((track * 1000) + (side * 100) + sector).NextBytes(data);
        return new((byte)track, (byte)side, (byte)sector, data, doubleDensity, mark);
    }

    private static byte[] Filled(int size, byte value)
    {
        byte[] data = new byte[size];
        data.AsSpan().Fill(value);
        return data;
    }

    // Each sector as a line: where it lies, its ID, density, mark, CRC error and data.
    private static List<string> Describe(FloppyDisk disk) =>
        [.. disk.Tracks().SelectMany(track => track.Sectors.Select(sector => Line(track.Cylinder, track.Side, sector)))];

    private static string Line(int cylinder, int side, FloppySector sector)
    {
        string id = $"{sector.Track} {sector.Side} {sector.Sector}";
        string field = $"{sector.DoubleDensity} {sector.DataAddressMark:X2} {sector.CrcError}";
        return $"{cylinder}/{side}: {id} {field} {Convert.ToHexString(sector.Data)}";
    }
}
