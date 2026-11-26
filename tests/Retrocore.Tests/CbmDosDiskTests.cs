// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug;
using Retrocore.Machines.Commodore;
using Retrocore.Media.Commodore;

namespace Retrocore.Tests;

/// <summary>
///  <see cref="CbmDosDisk"/>'s disks: their sectors read back through the D64 and GCR layout code, and, where MAME's
///  <c>c4040</c> set is in <c>RETROCORE_PET_ROMS</c>, through the emulated 4040's own DOS on a PET built from the
///  SDK's sources. Those tests are inconclusive without the set.
/// </summary>
[TestClass]
public class CbmDosDiskTests
{
    private const int Track18 = 357;

    private static string PetSources => Path.Join(BasicNames.Inputs, "Pet");

    /// <summary>
    ///  A formatted disk's header and first directory sector, byte for byte.
    /// </summary>
    [TestMethod]
    public void FormatWritesTheHeader()
    {
        CbmDosDisk disk = CbmDosDisk.Format("retrocore", "rc");
        byte[] image = disk.ToD64();
        image.Length.Should().Be(D64Format.Size);

        byte[] header = Sector(image, 18, 0);
        header[..4].Should().Equal(18, 1, (byte)'A', 0);
        for (int track = 1; track <= 35; track++)
        {
            int sectors = GcrLayout.SectorsOn(track);
            int bits = (1 << sectors) - 1;
            if (track == 18) { (sectors, bits) = (sectors - 2, bits & ~3); }
            header[(4 * track)..((4 * track) + 4)].Should().Equal(
                [(byte)sectors, (byte)bits, (byte)(bits >> 8), (byte)(bits >> 16)], $"track {track}'s BAM entry");
        }

        byte[] name = [.. "RETROCORE"u8, .. Enumerable.Repeat((byte)0xA0, 7)];
        byte[] rest = [0xA0, 0xA0, (byte)'R', (byte)'C', 0xA0, (byte)'2', (byte)'A', 0xA0, 0xA0, 0xA0, 0xA0];
        header[0x90..0xAB].Should().Equal([.. name, .. rest]);
        header[0xAB..].Should().AllBeEquivalentTo((byte)0);
        Sector(image, 18, 1).Should().Equal([0x00, 0xFF, .. new byte[254]]);
        image.AsSpan(0, Track18 * 256).IndexOfAnyExcept((byte)0).Should().Be(-1);
        image.AsSpan((Track18 + 2) * 256).IndexOfAnyExcept((byte)0).Should().Be(-1);

        disk.Name.Should().Be("RETROCORE");
        disk.Id.Should().Be("RC");
        disk.BlocksFree.Should().Be(664);
        disk.Files.Should().BeEmpty();
    }

    /// <summary>
    ///  Files laid out by the D64 reader as the 4040 formats tracks, and read back from those tracks, are the same
    ///  sectors, and their chains give back their bytes.
    /// </summary>
    [TestMethod]
    public void FilesReadBackThroughTheGcrLayout()
    {
        byte[] program = PetSysProgram.Build([0xA9, 0x2A, 0x60]);
        byte[] exact = [.. Enumerable.Range(0, 254).Select(i => (byte)i)];
        byte[] longer = [.. Enumerable.Range(0, 600).Select(i => (byte)(i * 7))];
        CbmDosDisk disk = CbmDosDisk.Format("files", "f1");
        disk.AddProgram("program", program);
        disk.AddSequential("exact", exact);
        disk.AddSequential("longer", longer);
        disk.BlocksFree.Should().Be(664 - 1 - 1 - 3);

        byte[] image = disk.ToD64();
        CommodoreDisk gcr = D64Format.Read(image);
        (byte[] back, IReadOnlyList<string> unreadable) = D64Format.Write(gcr);
        unreadable.Should().BeEmpty();
        back.Should().Equal(image);
        (byte[] viaG64, IReadOnlyList<string> lost) = D64Format.Write(G64Format.Read(G64Format.Write(disk.ToDisk())));
        lost.Should().BeEmpty();
        viaG64.Should().Equal(image);

        CbmDosDisk read = CbmDosDisk.FromD64(back);
        (string, CbmDosFileType, bool, int)[] expected =
        [
            ("PROGRAM", CbmDosFileType.Program, true, 1),
            ("EXACT", CbmDosFileType.Sequential, true, 1),
            ("LONGER", CbmDosFileType.Sequential, true, 3)
        ];

        read.Files.Select(file => (file.Name, file.Type, file.IsClosed, file.Blocks)).Should().Equal(expected);
        read.ReadFile("PROGRAM").Should().Equal(program);
        read.ReadFile("EXACT").Should().Equal(exact);
        read.ReadFile("LONGER").Should().Equal(longer);
    }

    /// <summary>
    ///  A file's blocks start on track 17 and go ten sectors apart, onto track 19 once 17 is full, and its last block
    ///  gives its last byte's index.
    /// </summary>
    [TestMethod]
    public void BlocksAreTakenNearTheDirectory()
    {
        CbmDosDisk disk = CbmDosDisk.Format("chain", "ch");
        disk.AddSequential("big", new byte[22 * 254 + 10]);
        CbmDosFile file = disk.Files.Single();
        (file.Track, file.Sector, file.Blocks).Should().Be((17, 0, 23));

        byte[] image = disk.ToD64();
        List<(int, int)> chain = [];
        (int track, int sector) = (file.Track, file.Sector);
        for (int guard = 0; guard < 30; guard++)
        {
            chain.Add((track, sector));
            byte[] block = Sector(image, track, sector);
            if (block[0] == 0)
            {
                block[1].Should().Be(11);
                break;
            }

            (track, sector) = (block[0], block[1]);
        }

        chain.Should().HaveCount(23);
        chain.Take(4).Should().Equal((17, 0), (17, 10), (17, 20), (17, 9));
        chain.Where(place => place.Item1 == 17).Should().HaveCount(21).And.OnlyHaveUniqueItems();
        chain.Skip(21).Should().Equal((19, 0), (19, 10));
    }

    /// <summary>
    ///  The directory takes sectors three apart as it grows, to its 144 entries, and a file more is refused with the
    ///  disk unchanged; so is a file larger than the free blocks.
    /// </summary>
    [TestMethod]
    public void FullDirectoryAndDiskAreRefused()
    {
        CbmDosDisk disk = CbmDosDisk.Format("many", "mn");
        for (int i = 0; i < 9; i++) { disk.AddSequential($"file{i}", [(byte)i]); }
        Sector(disk.ToD64(), 18, 1)[..2].Should().Equal(18, 4);
        Sector(disk.ToD64(), 18, 4)[..2].Should().Equal(0, 0xFF);

        for (int i = 9; i < 144; i++) { disk.AddSequential($"file{i}", [(byte)i]); }
        disk.Files.Should().HaveCount(144);
        disk.ReadFile("FILE143").Should().Equal(143);
        byte[] before = disk.ToD64();
        FluentActions.Invoking(() => disk.AddSequential("one more", [1])).Should().Throw<IOException>();
        disk.ToD64().Should().Equal(before);

        CbmDosDisk full = CbmDosDisk.Format("full", "fu");
        full.AddSequential("most", new byte[663 * 254]);
        full.BlocksFree.Should().Be(1);
        before = full.ToD64();
        FluentActions.Invoking(() => full.AddSequential("two", new byte[255])).Should().Throw<IOException>();
        full.ToD64().Should().Equal(before);
        full.AddSequential("last", new byte[254]);
        full.BlocksFree.Should().Be(0);
        full.ReadFile("MOST").Length.Should().Be(663 * 254);
    }

    /// <summary>
    ///  Names the DOS would misread, a name already taken, an empty file and a program file of its load address
    ///  alone are refused.
    /// </summary>
    /// <param name="name">The name.</param>
    [TestMethod]
    [DataRow("")]
    [DataRow("SEVENTEEN CHARS!!")]
    [DataRow("A,B")]
    [DataRow("A:B")]
    [DataRow("A*")]
    [DataRow("A?")]
    [DataRow("A=B")]
    [DataRow("A\"B")]
    [DataRow("café")]
    [DataRow("taken")]
    [DataRow("$")]
    [DataRow("@replace")]
    [DataRow("ı")]
    public void BadNamesAreRefused(string name)
    {
        CbmDosDisk disk = CbmDosDisk.Format("names", "nm");
        disk.AddSequential("TAKEN", [1]);
        FluentActions.Invoking(() => disk.AddSequential(name, [])).Should().ThrowExactly<ArgumentException>();
        FluentActions.Invoking(() => CbmDosDisk.Format("disk", "x")).Should().ThrowExactly<ArgumentException>();
        FluentActions.Invoking(() => disk.AddProgram("short", [1, 4])).Should().ThrowExactly<ArgumentException>();
        FluentActions.Invoking(() => disk.AddSequential("empty", [])).Should().ThrowExactly<ArgumentException>();
        disk.Files.Should().ContainSingle();
    }

    /// <summary>
    ///  The emulated 4040's <c>N</c> command writes the same header and first directory sector.
    /// </summary>
    [TestMethod]
    [TestCategory("Conformance")]
    public void DriveFormatsTheSameHeader()
    {
        PetMachine machine = Machine(PetModel.Pet2001Basic2);
        CommodoreDisk blank = CommodoreDisk.Blank();
        machine.Disks[0].Drive0.Insert(blank, "blank", "D64", changed: true);
        PetMachineTests.RunToReady(machine);
        PetDiskTests.DiskCommand(machine, "N0:RETROCORE,RC", seconds: 120).Should().Be(" 0 OK 0  0");

        (byte[] drive, IReadOnlyList<string> unreadable) = D64Format.Write(blank);
        unreadable.Should().BeEmpty();
        byte[] ours = CbmDosDisk.Format("RETROCORE", "RC").ToD64();
        Sector(drive, 18, 0).Should().Equal(Sector(ours, 18, 0));
        Sector(drive, 18, 1).Should().Equal(Sector(ours, 18, 1));
    }

    /// <summary>
    ///  On each model, the drive lists the disk, loads its program, which runs, and reads its sequential file.
    /// </summary>
    /// <param name="model">The model.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001Basic2)]
    [DataRow(PetModel.Pet4032)]
    public void DriveLoadsAndRunsAFile(PetModel model)
    {
        PetMachine machine = Machine(model);
        CbmDosDisk disk = CbmDosDisk.Format("retrocore", "rc");
        List<byte> code = [];
        foreach (char c in "DISK OK") { code.AddRange([0xA9, (byte)c, 0x20, 0xD2, 0xFF]); }
        code.Add(0x60);
        disk.AddProgram("sysok", PetSysProgram.Build([.. code]));
        disk.AddSequential("data", "HELLO\r"u8);
        machine.Disks[0].Drive0.Insert(disk.ToDisk(), "built", "D64");
        PetMachineTests.RunToReady(machine);

        PetDiskTests.Command(machine, "LOAD\"$0\",8");
        string[] screen = PetDiskTests.Command(machine, "LIST");
        string text = string.Join('\n', screen);
        screen.Should().Contain(line => line.Contains("\"RETROCORE       \" RC 2A", StringComparison.Ordinal), text);
        screen.Should().Contain(line => line.TrimEnd() == " 1    \"SYSOK\"            PRG", text);
        screen.Should().Contain(line => line.TrimEnd() == " 1    \"DATA\"             SEQ", text);
        screen.Should().Contain(line => line.TrimEnd() == " 662 BLOCKS FREE.", text);

        PetDiskTests.Command(machine, "NEW");
        screen = PetDiskTests.Command(machine, "LOAD\"0:SYSOK\",8");
        screen.Should().Contain(line => line.TrimEnd() == "LOADING", string.Join('\n', screen));
        screen = PetDiskTests.Command(machine, "RUN");
        screen.Should().Contain(line => line.TrimEnd() == "DISK OK", string.Join('\n', screen));

        PetDiskTests.Command(machine, "NEW");
        PetDiskTests.Command(machine, "1 OPEN2,8,2,\"0:DATA,S,R\":INPUT#2,A$:CLOSE2:PRINT\"=\"A$");
        screen = PetDiskTests.Command(machine, "RUN");
        screen.Should().Contain(line => line.TrimEnd() == "=HELLO", string.Join('\n', screen));
    }

    // A PET built from the SDK's sources with a 4040 as device 8, or inconclusive without the drive's dumps.
    private static PetMachine Machine(PetModel model)
    {
        string drive = Path.Join(PetMachineTests.RomRoot, "c4040");
        if (!File.Exists(Path.Join(drive, "901468-14.uj1")))
        {
            Assert.Inconclusive("The 4040's ROMs are dumps: set RETROCORE_PET_ROMS to a folder with MAME's c4040 set.");
        }

        return new(PetSdkModules.BuildRoms(model, PetSources), model, 32, Cbm4040Roms.LoadFromDirectory(drive));
    }

    private static byte[] Sector(byte[] image, int track, int sector) =>
        image.AsSpan((GcrLayout.FirstSector(track) + sector) * 256, 256).ToArray();
}
