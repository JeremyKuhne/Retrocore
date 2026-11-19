// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug;
using Retrocore.Machines.Chips;
using Retrocore.Machines.Coco;
using Retrocore.Media;
using Retrocore.Media.Floppy;
using Retrocore.Media.Trs80;
using System.Security.Cryptography;
using System.Text.Json.Nodes;

namespace Retrocore.Tests;

/// <summary>
///  The TRS-80 and Color Computer floppies save as the Apple II's drives do: their writes are counted, DMK holds all
///  of a disk and is its snapshot, and JV1, JV3 and JVC list what they cannot hold.
/// </summary>
[TestClass]
public sealed class FloppyMediaSaveTests
{
    private static string s_root = "";

    /// <summary>
    ///  Makes the tests' folder; local data, where backups and locks go, is the run's (<see cref="TestLocalData"/>).
    /// </summary>
    /// <param name="context">The test context.</param>
    [ClassInitialize]
    public static void Initialize(TestContext context)
    {
        _ = context;
        s_root = Path.Join(Path.GetTempPath(), $"retrocore-floppies-{Environment.ProcessId}");
        Directory.CreateDirectory(s_root);
    }

    /// <summary>
    ///  Removes the tests' folder.
    /// </summary>
    [ClassCleanup]
    public static void Cleanup() => Directory.Delete(s_root, recursive: true);

    /// <summary>
    ///  DMK keeps every ID, density, mark, CRC error, side, order and the lock, so a disk reads back as it was.
    /// </summary>
    [TestMethod]
    public void DmkHoldsAllOfTheDisk()
    {
        FloppyDisk disk = Varied();
        disk.IsWriteProtected = true;
        FloppyDisk read = DmkFormat.Read(DmkFormat.Write(disk));
        read.IsWriteProtected.Should().BeTrue();
        Describe(read).Should().Equal(Describe(disk));

        // The snapshot is that image.
        MediumSnapshot snapshot = disk.Snapshot();
        snapshot.Kind.Should().Be(DmkFormat.SnapshotKind);
        snapshot.WriteProtected.Should().BeTrue();
        Describe(DmkFormat.ReadSnapshot(snapshot.Image.Span)).Should().Equal(Describe(disk));
    }

    /// <summary>
    ///  A track holds what a DMK track can: as many sectors as fit with no gaps, up to 64, and refuses more.
    /// </summary>
    [TestMethod]
    public void TracksHoldWhatDmkHolds()
    {
        FloppyDisk full = new();
        for (int sector = 0; sector < 58; sector++)
        {
            full.Add(0, 0, Sector(0, 0, sector, size: 128, doubleDensity: false));
        }

        Action more = () => full.Add(0, 0, Sector(0, 0, 58, size: 128, doubleDensity: false));
        more.Should().Throw<InvalidDataException>();
        Describe(DmkFormat.Read(DmkFormat.Write(full))).Should().Equal(Describe(full), "a track too full for gaps has none");

        FloppyDisk many = new();
        for (int sector = 0; sector < DmkFormat.MaximumSectors; sector++)
        {
            many.Add(0, 0, Sector(0, 0, sector, size: 128, doubleDensity: true));
        }

        Action another = () => many.Add(0, 0, Sector(0, 0, 64, size: 128, doubleDensity: true));
        another.Should().Throw<InvalidDataException>();

        // Formatting keeps the sectors that fit.
        many.Format(1, 0, Enumerable.Range(0, 70).Select(sector => Sector(1, 0, sector, size: 128, doubleDensity: true)));
        many.Track(1, 0).Should().HaveCount(DmkFormat.MaximumSectors);
    }

    /// <summary>
    ///  The 8271's large sectors keep their size through DMK, a bad CRC and all, while a WD track's short sector whose
    ///  ID carries a large size code is still read at the code's low two bits.
    /// </summary>
    [TestMethod]
    public void LargeSectorsKeepTheirSize()
    {
        FloppyDisk disk = new();
        byte[] data = [.. Enumerable.Range(0, 2048).Select(index => (byte)index)];
        disk.Add(3, 0, new FloppySector(3, 0, 0, data, doubleDensity: false) { CrcError = true });
        disk.Add(4, 0, new FloppySector(4, 0, 0, data, doubleDensity: false));
        byte[] snapshot = DmkFormat.Write(disk);
        snapshot.AsSpan(5, 11).ToArray().Should().OnlyContain(value => value == 0, "the header's reserved bytes, as MAME requires");
        FloppyDisk read = DmkFormat.ReadSnapshot(snapshot);
        FloppySector bad = read.Track(3, 0).Should().ContainSingle().Subject;
        bad.CrcError.Should().BeTrue();
        bad.Data.ToArray().Should().Equal(data, "the bad CRC's sector keeps all 2048 bytes");
        FloppySector good = read.Track(4, 0).Should().ContainSingle().Subject;
        good.CrcError.Should().BeFalse();
        good.Data.Length.Should().Be(2048);

        // No payload fools a snapshot: bytes 128 and 129 that are a good CRC for the first 128 still leave 2048. Read
        // as a file from elsewhere, the same image is sized by guessing, which that payload does fool.
        byte[] tricky = [.. Enumerable.Range(0, 2048).Select(index => (byte)index)];
        tricky[128] = 0xA0;
        tricky[129] = 0x23;
        FloppyDisk trap = new();
        trap.Add(5, 0, new FloppySector(5, 0, 0, tricky, doubleDensity: false) { CrcError = true });
        FloppySector kept = DmkFormat.ReadSnapshot(DmkFormat.Write(trap)).Track(5, 0).Should().ContainSingle().Subject;
        kept.CrcError.Should().BeTrue();
        kept.Data.ToArray().Should().Equal(tricky);
        DmkFormat.Read(DmkFormat.Write(trap)).Track(5, 0).Single().Data.Length.Should().Be(128);

        // Saved as a file, a sector over 1024 bytes is listed as a loss, for DMK, JV3 and JVC, rather than written so
        // that other readers size it wrongly or the table or header is broken.
        DmkFormat.Encode(disk).Losses.Should().ContainSingle().Which.Should().Contain("more than 1024 bytes");
        Jv3Format.Encode(disk).Losses.Should().NotBeEmpty();
        Action jv3 = () => Jv3Format.Write(disk);
        jv3.Should().Throw<InvalidOperationException>();
        FloppyDisk large = new();
        large.Add(0, 0, new FloppySector(0, 0, 1, data, doubleDensity: true));
        EncodedImage jvc = JvcFormat.Encode(large);
        jvc.Losses.Should().NotBeEmpty();
        JvcFormat.Read(jvc.Bytes).Should().NotBeNull("the header stays one JVC reads");

        // A WD track of 128-byte sectors from a file, one ID changed to size code 4, which WD reads as 0: the first,
        // the last, which has only padding after it, and a sole sector all stay 128 bytes, with good CRCs.
        foreach ((int count, int patched) in (ReadOnlySpan<(int, int)>)[(3, 0), (3, 2), (1, 0)])
        {
            FloppyDisk wd = new();
            for (int sector = 0; sector < count; sector++)
            {
                wd.Add(0, 0, Sector(0, 0, sector, size: 128, doubleDensity: false));
            }

            byte[] image = DmkFormat.Write(wd);
            int track = 16;                                     // the DMK header, then track 0's ID table
            int entry = track + (2 * patched);
            int id = track + ((image[entry] | (image[entry + 1] << 8)) & 0x3FFF);
            image[id].Should().Be(0xFE, "the table points at an ID field");
            image[id + 8].Should().Be(0, "its size code, 128 bytes");
            image[id + 8] = image[id + 9] = 4;                  // the size code, doubled as single density is
            IReadOnlyList<FloppySector> sectors = DmkFormat.Read(image).Track(0, 0);
            sectors.Select(sector => sector.Data.Length).Should().OnlyContain(length => length == 128, $"sector {patched} of {count}");
            sectors.Should().HaveCount(count);
            sectors.Should().NotContain(sector => sector.CrcError);
        }
    }

    /// <summary>
    ///  A write or a format changes the disk and counts in its version; a lock change counts but is not a change to
    ///  save; a save marks it unchanged.
    /// </summary>
    [TestMethod]
    public void WritesAreCounted()
    {
        FloppyDisk disk = JvcFormat.Formatted();
        disk.IsDirty.Should().BeFalse("reading an image does not change it");
        long version = disk.Version;

        disk.IsWriteProtected = true;
        disk.Version.Should().BeGreaterThan(version);
        disk.IsDirty.Should().BeFalse();

        version = disk.Version;
        FloppySector sector = disk.Track(17, 0)[1];
        disk.Write(sector, Filled(256, 0x42), 0xF8);
        disk.Version.Should().BeGreaterThan(version);
        disk.IsDirty.Should().BeTrue();
        sector.Data.ToArray().Should().AllBeEquivalentTo((byte)0x42);
        sector.DataAddressMark.Should().Be(0xF8);

        disk.MarkSaved();
        disk.IsDirty.Should().BeFalse();
        version = disk.Version;
        disk.Format(3, 0, [Sector(3, 0, 1, size: 256, doubleDensity: true)]);
        disk.Version.Should().BeGreaterThan(version);
        disk.IsDirty.Should().BeTrue();

        Action wrongSize = () => disk.Write(sector, Filled(128, 0), 0xFB);
        wrongSize.Should().Throw<ArgumentException>();
    }

    /// <summary>
    ///  JV1 holds an image it read without loss, and lists double density, marks other than its own, other sides,
    ///  sectors and sizes, CRC errors and IDs that name another track.
    /// </summary>
    [TestMethod]
    public void Jv1ListsWhatItCannotHold()
    {
        byte[] image = new byte[40 * 10 * 256];
        new Random(1).NextBytes(image);
        FloppyDisk disk = Jv1Format.Read(image);
        EncodedImage same = Jv1Format.Encode(disk);
        same.IsLossless.Should().BeTrue();
        same.Bytes.Should().Equal(image);

        disk.Write(disk.Track(5, 0)[2], Filled(256, 1), 0xF8);
        disk.Write(disk.Track(6, 0)[2], Filled(256, 1), 0xF8);
        disk.Format(9, 0, Enumerable.Range(1, 18).Select(sector => Sector(9, 0, sector, size: 256, doubleDensity: true)));
        disk.Format(20, 1, [Sector(20, 1, 0, size: 256, doubleDensity: false)]);
        disk.Format(30, 0, Enumerable.Range(0, 10).Select(sector => Sector(31, 0, sector, size: 256, doubleDensity: false)));
        EncodedImage lossy = Jv1Format.Encode(disk);
        lossy.Losses.Should().BeEquivalentTo(
        [
            "Data address marks other than $FA on track 17 and $FB elsewhere, on tracks 5-6.",
            "Sectors other than 0-9, or repeated, on track 9.",
            "Double-density sectors, on track 9.",
            "Sectors 0-9 missing, which JV1 writes as zeros, on track 9.",
            "Side 1's sectors, on track 20.",
            "Sector IDs naming another track or side, on track 30.",
        ]);

        Action write = () => Jv1Format.Write(disk);
        write.Should().Throw<InvalidOperationException>().WithMessage("JV1 cannot hold all of the disk: *");

        // A last track that ends early, as an image may, saves as long as it was, its sectors all there.
        byte[] partial = image[..(12 * 256)];
        FloppyDisk brief = Jv1Format.Read(partial);
        brief.Write(brief.Track(1, 0)[1], Filled(256, 7), 0xFB);
        EncodedImage trimmed = Jv1Format.Encode(brief);
        trimmed.IsLossless.Should().BeTrue();
        trimmed.Bytes.Length.Should().Be(partial.Length);
        trimmed.Bytes.AsSpan(11 * 256, 256).ToArray().Should().AllBeEquivalentTo((byte)7);
    }

    /// <summary>
    ///  JV3 holds what it read, and lists sector IDs that name another track or side and double-density marks it has
    ///  no flags for.
    /// </summary>
    [TestMethod]
    public void Jv3ListsWhatItCannotHold()
    {
        FloppyDisk disk = new();
        disk.Add(0, 0, Sector(0, 0, 1, size: 256, doubleDensity: false, mark: 0xFA));
        disk.Add(0, 1, Sector(0, 1, 1, size: 512, doubleDensity: true, mark: 0xF8));
        disk.Add(1, 0, Sector(1, 0, 1, size: 128, doubleDensity: false));
        FloppyDisk read = Jv3Format.Read(Jv3Format.Encode(disk).Bytes);
        Describe(read).Should().Equal(Describe(disk));

        disk.Format(2, 0, [Sector(7, 1, 1, size: 256, doubleDensity: true, mark: 0xF9)]);
        Jv3Format.Encode(disk).Losses.Should().BeEquivalentTo(
        [
            "Sector IDs naming another track or side, on track 2.",
            "Double-density data address marks other than $FB and $F8, on track 2.",
        ]);

        // DMK holds them.
        Describe(DmkFormat.Read(DmkFormat.Write(disk))).Should().Equal(Describe(disk));
    }

    /// <summary>
    ///  JVC saves back with the header it was read with, even one longer than it needs; a disk from elsewhere takes its
    ///  first track's geometry; a disk that gains a side says so in its header; and sectors outside the geometry are
    ///  listed.
    /// </summary>
    [TestMethod]
    public void JvcKeepsItsHeader()
    {
        byte[] body = new byte[35 * 18 * 256];
        new Random(2).NextBytes(body);
        byte[] image = [18, 1, 1, 1, 0, .. body];
        FloppyDisk disk = JvcFormat.Read(image);
        EncodedImage same = JvcFormat.Encode(disk, JvcFormat.Header(image));
        same.IsLossless.Should().BeTrue();
        same.Bytes.Should().Equal(image, "the header is the one it read");
        JvcFormat.Encode(disk).Bytes.Should().Equal(body, "Disk BASIC's geometry needs no header");

        FloppyImageCodec codec = FloppyImageCodec.ForImage("JVC", image) ?? throw new InvalidOperationException();
        codec.Encode(disk.Snapshot()).Bytes.Should().Equal(image);

        // Ten sectors of 512 bytes from sector 0: a header gives each field up to the last that differs.
        FloppyDisk other = new();
        for (int sector = 0; sector < 10; sector++)
        {
            other.Add(0, 0, Sector(0, 0, sector, size: 512, doubleDensity: true));
        }

        EncodedImage geometry = JvcFormat.Encode(other);
        geometry.IsLossless.Should().BeTrue();
        geometry.Bytes.AsSpan(0, 4).ToArray().Should().Equal([10, 1, 2, 0]);
        Describe(JvcFormat.Read(geometry.Bytes)).Should().Equal(Describe(other));

        // A second side.
        disk.Format(0, 1, Enumerable.Range(1, 18).Select(sector => Sector(0, 1, sector, size: 256, doubleDensity: true)));
        EncodedImage sided = JvcFormat.Encode(disk, JvcFormat.Header(image));
        sided.Bytes.AsSpan(0, 5).ToArray().Should().Equal([18, 2, 1, 1, 0]);
        sided.Losses.Should().BeEquivalentTo(["Sectors 1-18 missing, which JVC writes as zeros, on tracks 1-34."]);

        disk.Format(4, 0, Enumerable.Range(1, 19).Select(sector => Sector(4, 0, sector, size: 256, doubleDensity: false)));
        JvcFormat.Encode(disk, JvcFormat.Header(image)).Losses.Should().Contain(
        [
            "Sectors other than 1-18, or repeated, on track 4.",
            "Single-density sectors, on track 4.",
        ]);

        // Sector numbers wrap past 255, as the reader numbers them: 254, 255, 0 and 1.
        byte[] wrapped = [4, 1, 0, 254, .. body.AsSpan(0, 2 * 4 * 128)];
        FloppyDisk wraps = JvcFormat.Read(wrapped);
        wraps.Track(0, 0).Select(sector => sector.Sector).Should().Equal([254, 255, 0, 1]);
        EncodedImage again = JvcFormat.Encode(wraps, JvcFormat.Header(wrapped));
        again.IsLossless.Should().BeTrue();
        again.Bytes.Should().Equal(wrapped);

        // An odd number of 128-byte sectors cannot fill whole 256-byte blocks, which the header's length needs.
        FloppyDisk odd = new();
        odd.Add(0, 0, Sector(0, 0, 1, size: 128, doubleDensity: true));
        Action unframed = () => JvcFormat.Encode(odd);
        unframed.Should().Throw<InvalidOperationException>().WithMessage("*save it as DMK*");
    }

    /// <summary>
    ///  A format's codec comes from its extension: <c>.dsk</c> is JVC on a drive that saves JVC and JV1 on one that
    ///  does not; IMD has no writer; and every codec writes from the DMK snapshot.
    /// </summary>
    [TestMethod]
    public void CodecsComeFromTheExtension()
    {
        FloppyImageCodec.For(".dsk", ["dsk", "jvc", "dmk"])?.Format.Should().Be("JVC");
        FloppyImageCodec.For("dsk", ["jv3", "dmk", "dsk", "jv1"])?.Format.Should().Be("JV1");
        FloppyImageCodec.For(".JV3", [])?.Format.Should().Be("JV3");
        FloppyImageCodec.For(".dmk", [])?.Format.Should().Be("DMK");
        FloppyImageCodec.For(".imd", []).Should().BeNull();
        FloppyImageCodec.ForImage("IMD", []).Should().BeNull();

        FloppyDisk disk = Varied();
        MediumSnapshot snapshot = disk.Snapshot();
        (FloppyImageCodec.For(".dmk", []) ?? throw new InvalidOperationException()).Encode(snapshot).Bytes
            .Should().Equal(snapshot.Image.ToArray(), "a DMK save is the snapshot");

        FloppyDisk formatted = JvcFormat.Formatted();
        EncodedImage jv3 = (FloppyImageCodec.For(".jv3", []) ?? throw new InvalidOperationException()).Encode(formatted.Snapshot());
        jv3.IsLossless.Should().BeTrue();
        Describe(Jv3Format.Read(jv3.Bytes)).Should().Equal(Describe(formatted));
        FloppyImageCodec.For(".jv3", [])?.Encode(snapshot).Losses.Should().Equal(["Sector IDs naming another track or side, on track 2."]);

        Action block = () => FloppyImageCodec.For(".dmk", [])?.Encode(new MediumSnapshot("2mg", 0, WriteProtected: false, new byte[64]));
        block.Should().Throw<ArgumentException>();
    }

    /// <summary>
    ///  A drive's disk saves through the host as other drives' do: a changed disk holds back an eject, saves to its own
    ///  format, and saves as another, after which it comes from that image; a disk read from IMD saves only as another.
    /// </summary>
    [TestMethod]
    public void DriveSavesThroughTheHost()
    {
        CocoDiskController controller = new(new byte[CocoRoms.BasicSize]);
        FloppyDrive drive = controller.Drives[0];
        string path = Path.Join(s_root, $"host-{Guid.NewGuid():N}.dsk");
        File.WriteAllBytes(path, JvcFormat.Write(JvcFormat.Formatted()));
        FloppyMedia.Insert(drive, path, FloppyFamily.Coco);
        drive.Media?.Format.Should().Be("JVC");
        int generation = drive.MountGeneration;

        FloppyDisk disk = drive.Disk ?? throw new InvalidOperationException("The drive is empty.");
        disk.Write(disk.Track(17, 0)[2], Filled(256, 0x33), 0xFB);
        drive.Media?.Changed.Should().BeTrue();
        MediaActions.Device(drive, "eject", Speaking())?.String("outcome").Should().Be("changed");

        MediaActions.Save(drive, Speaking()).String("outcome").Should().Be("saved");
        drive.Media?.Changed.Should().BeFalse();
        JvcFormat.Read(File.ReadAllBytes(path)).Track(17, 0)[2].Data.ToArray().Should().AllBeEquivalentTo((byte)0x33);

        // Save as DMK: the disk now comes from it.
        string dmk = Path.ChangeExtension(path, ".dmk");
        JsonObject saveAs = Speaking();
        saveAs["path"] = dmk;
        MediaActions.Save(drive, saveAs).String("outcome").Should().Be("saved");
        drive.Media?.Label.Should().Be(dmk);
        drive.Media?.Format.Should().Be("DMK");
        drive.MountGeneration.Should().Be(generation, "a save is not a new mount");
        Describe(DmkFormat.Read(File.ReadAllBytes(dmk))).Should().Equal(Describe(disk));

        // A single-density track cannot go back to JVC without the person's leave.
        disk.Format(0, 0, [Sector(0, 0, 1, size: 256, doubleDensity: false)]);
        JsonObject asJvc = Speaking();
        asJvc["path"] = Path.ChangeExtension(path, ".jvc");
        JsonObject losses = MediaActions.Save(drive, asJvc);
        losses.String("outcome").Should().Be("losses");
        losses.String("format").Should().Be("JVC");

        // A disk read from IMD, which has no writer, saves only as another format.
        string imd = Path.ChangeExtension(path, ".imd");
        byte[] bytes = [.. "IMD"u8];
        File.WriteAllBytes(imd, bytes);
        FloppyDisk read = JvcFormat.Formatted();
        MediaActions.Register(read, imd, codec: null, bytes);
        FloppyDrive other = controller.Drives[1];
        other.Insert(read, imd, "IMD");
        read.Write(read.Track(0, 0)[0], Filled(256, 0), 0xFB);
        MediaActions.Save(other, Speaking()).String("reason").Should().Be("format");
    }

    /// <summary>
    ///  Disk BASIC formats a disk and saves a program; the disk saves as JVC and as DMK, each pinned by digest, and
    ///  each boots in a new machine, where the program loads and runs.
    /// </summary>
    [TestMethod]
    public void CocoDiskSavesAndLoadsAgain()
    {
        CocoMachine machine = CocoDiskTests.Create(CocoModel.Coco2);
        string path = Path.Join(s_root, $"basic-{Guid.NewGuid():N}.dsk");
        File.WriteAllBytes(path, JvcFormat.Write(JvcFormat.Formatted()));
        FloppyDrive drive = machine.Bus.DiskController?.Drives[0] ?? throw new InvalidOperationException("No disk controller.");
        FloppyMedia.Insert(drive, path, FloppyFamily.Coco);
        CocoMachineTests.Type(machine, "10 print \"saved\";6*7\rsave \"hello\"\r");
        CocoDiskTests.WaitForOk(machine, limit: 10);
        drive.Media?.Changed.Should().BeTrue();

        MediaActions.Save(drive, Speaking()).String("outcome").Should().Be("saved");
        string dmk = Path.ChangeExtension(path, ".dmk");
        JsonObject saveAs = Speaking();
        saveAs["path"] = dmk;
        MediaActions.Save(drive, saveAs).String("outcome").Should().Be("saved");

        Digest(path).Should().Be("8172787B782528CE352BFE0EC54738A17F2B98E99038B8EA3EEB17E517EC89A1");
        Digest(dmk).Should().Be("CDBD387B3385EC38F01D306D51CD79539303697B36ACAD4DCAE649BC8CC9841A");
        foreach (string image in (string[])[path, dmk])
        {
            CocoMachine again = CocoDiskTests.Create(CocoModel.Coco2);
            FloppyMedia.Insert(again.Bus.DiskController?.Drives[0] ?? throw new InvalidOperationException(), image, FloppyFamily.Coco);
            CocoMachineTests.Type(again, "load \"hello\"\r");
            CocoDiskTests.WaitForOk(again, limit: 10);
            CocoMachineTests.Type(again, "run\r");
            CocoMachineTests.Screen(again).Should().Contain("SAVED 42", image);
        }
    }

    // A disk of every kind of sector: densities, sizes, marks, a CRC error, an ID naming another track, two sides,
    // and an order other than by number.
    private static FloppyDisk Varied()
    {
        FloppyDisk disk = new();
        disk.Add(0, 0, Sector(0, 0, 3, size: 256, doubleDensity: false, mark: 0xFA));
        disk.Add(0, 0, Sector(0, 0, 1, size: 128, doubleDensity: false, mark: 0xF9));
        disk.Add(0, 0, Sector(0, 0, 2, size: 1024, doubleDensity: true, mark: 0xF8));
        disk.Add(0, 1, Sector(0, 1, 1, size: 512, doubleDensity: true));
        disk.Add(2, 0, new FloppySector(9, 1, 7, Filled(256, 0x77), doubleDensity: true) { CrcError = true });
        disk.Add(2, 1, Sector(2, 1, 0, size: 256, doubleDensity: false, mark: 0xF8));
        return disk;
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

    private static string Digest(string path) => Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(path)));

    private static JsonObject Speaking() => new() { ["supportsRetrocoreMedia"] = true };
}
