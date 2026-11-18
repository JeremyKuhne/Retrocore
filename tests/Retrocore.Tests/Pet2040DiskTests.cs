// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.IO.Compression;
using Retrocore.Machines.Commodore;
using Retrocore.Media.Commodore;

namespace Retrocore.Tests;

/// <summary>
///  The 2040 dual drive on the PET's IEEE-488 bus, running DOS 1.2 and its controller ROM. It needs MAME's
///  <c>c2040</c> set with DOS 1.2's two chips, the PET sets, and the <c>pet_flop</c> software list's <c>2040demo</c>,
///  whose <c>2040demov1</c> is a DOS 1 disk.
/// </summary>
[TestClass]
public class Pet2040DiskTests
{
    private static string DemoZip => Path.Join(
        ExternalTestData.Root, "pet-media", "extract", "pet_flop", "pet_flop", "2040demo.zip");

    /// <summary>
    ///  Gets the folder of MAME's <c>c2040</c> set.
    /// </summary>
    internal static string RomDirectory => Path.Join(PetMachineTests.RomRoot, "c2040");

    /// <summary>
    ///  Makes a BASIC 2 PET with one 2040 as device 8, or marks the test inconclusive without the dumps.
    /// </summary>
    /// <param name="ramKilobytes">The PET's RAM.</param>
    /// <returns>The machine.</returns>
    internal static PetMachine Machine(int ramKilobytes = 32)
    {
        string pet = PetMachineTests.RomDirectory(PetModel.Pet2001Basic2);
        if (!File.Exists(Path.Join(RomDirectory, "901468-06.ul1")) || !File.Exists(Path.Join(pet, "901465-03.ud9")))
        {
            Assert.Inconclusive("Set RETROCORE_PET_ROMS to a folder with MAME's pet2001n and c2040 sets unzipped.");
        }

        return new(
            PetRoms.LoadFromDirectory(pet, PetModel.Pet2001Basic2),
            PetModel.Pet2001Basic2,
            ramKilobytes,
            Cbm4040Roms.Load2040FromDirectory(RomDirectory));
    }

    /// <summary>
    ///  Reads the DOS 1 demo disk's G64 image, or marks the test inconclusive without it.
    /// </summary>
    /// <returns>The image.</returns>
    internal static byte[] DemoImage()
    {
        if (!File.Exists(DemoZip)) { Assert.Inconclusive("The pet_flop software list's 2040demo.zip is missing."); }
        using ZipArchive zip = ZipFile.OpenRead(DemoZip);
        using Stream stream = zip.GetEntry("2040demov1/c2040testdemo-dosv1.g64")?.Open()
            ?? throw new InvalidDataException("No DOS 1 G64.");

        using MemoryStream memory = new();
        stream.CopyTo(memory);
        return memory.ToArray();
    }

    /// <summary>
    ///  The unit is a 2040, and its drives save DOS 1's sectors as D67 images.
    /// </summary>
    [TestMethod]
    public void UnitIsA2040()
    {
        PetMachine machine = Machine();
        machine.Disks[0].Model.Should().Be("2040");
        machine.Disks[0].Drive0.Info.SaveFormats.Should().Equal("g64", "d67");
    }

    /// <summary>
    ///  The DOS 1 demo disk, a G64 of the real disk, reads as D67 sectors. DOS 1 formats a disk's headers alone, so
    ///  the sectors it never wrote, all of track 1's among them, have no data block; they are zeros, not losses.
    /// </summary>
    [TestMethod]
    public void DemoDiskReadsAsD67()
    {
        (byte[] image, IReadOnlyList<string> unreadable) = D67Format.Write(G64Format.Read(DemoImage()));
        unreadable.Should().BeEmpty();
        image.Length.Should().Be(D67Format.Size);
        image[0x16590..0x1659E].Should().Equal("UNIVERSAL DEMO"u8.ToArray());
        image[0x165A2..0x165A4].Should().Equal((byte)'V', (byte)'1');
    }

    /// <summary>
    ///  Once the I command initializes the DOS 1 demo disk, as DOS 1 needs before it reads one, <c>LOAD "$0",8</c>
    ///  reads its directory, which LIST shows as MAME's <c>c2040</c> does.
    /// </summary>
    [TestMethod]
    public void DirectoryLists()
    {
        PetMachine machine = Machine();
        machine.Disks[0].Drive0.Insert(G64Format.Read(DemoImage()), "2040demov1", "G64");
        PetMachineTests.RunToReady(machine);

        PetDiskTests.DiskCommand(machine, "I0").Should().Be(" 0 OK 0  0");
        PetDiskTests.Command(machine, "NEW");

        string[] screen = PetDiskTests.Command(machine, "LOAD\"$0\",8");
        screen.Should().Contain(line => line.TrimEnd() == "LOADING", string.Join('\n', screen));
        screen = PetDiskTests.Command(machine, "LIST");
        string text = string.Join('\n', screen);
        screen.Should().Contain(line => line.TrimEnd() == " 27   \"DUM 3.4\"          PRG", text);
        screen.Should().Contain(line => line.TrimEnd() == " 11   \"PERFORMANCE TEST\" PRG", text);
        screen.Should().Contain(line => line.TrimEnd() == " 401 BLOCKS FREE.", text);
    }

    /// <summary>
    ///  On a blank disk, the N command formats it as DOS 1; a program saves, loads back and runs, and the S, R and V
    ///  commands scratch, rename and validate, each answering on the command channel. The disk saves as D67.
    /// </summary>
    [TestMethod]
    public void FormatSaveLoadAndCommands()
    {
        PetMachine machine = Machine();
        CommodoreDisk disk = CommodoreDisk.Blank();
        machine.Disks[0].Drive0.Insert(disk, "blank", "D67", changed: true);
        PetMachineTests.RunToReady(machine);

        PetDiskTests.DiskCommand(machine, "N0:RETROCORE,RC", seconds: 120).Should().Be(" 0 OK 0  0");

        PetDiskTests.Command(machine, "NEW");
        PetDiskTests.Command(machine, "10 PRINT\"SAVED\";6*7");
        PetDiskTests.Command(machine, "SAVE\"0:FIRST\",8");
        PetDiskTests.Command(machine, "SAVE\"0:SECOND\",8");

        PetDiskTests.Command(machine, "NEW");
        string[] screen = PetDiskTests.Command(machine, "LOAD\"0:FIRST\",8");
        screen.Should().Contain(line => line.TrimEnd() == "LOADING", string.Join('\n', screen));
        screen = PetDiskTests.Command(machine, "RUN");
        screen.Should().Contain(line => line.TrimEnd() == "SAVED 42", string.Join('\n', screen));

        PetDiskTests.DiskCommand(machine, "R0:THIRD=SECOND").Should().Be(" 0 OK 0  0");
        PetDiskTests.DiskCommand(machine, "S0:FIRST").Should().Be(" 1 FILES SCRATCHED 1  0");
        PetDiskTests.DiskCommand(machine, "V0", seconds: 120).Should().Be(" 0 OK 0  0");

        PetDiskTests.Command(machine, "NEW");
        PetDiskTests.Command(machine, "LOAD\"$0\",8");
        screen = PetDiskTests.Command(machine, "LIST");
        string text = string.Join('\n', screen);
        screen.Should().Contain(line => line.Contains("\"RETROCORE       \" RC", StringComparison.Ordinal), text);
        screen.Should().Contain(line => line.TrimEnd() == " 1    \"THIRD\"            PRG", text);
        screen.Should().NotContain(line => line.Contains("FIRST", StringComparison.Ordinal), text);

        // The D67 written back holds what the DOS wrote, and reads back as the same disk's sectors.
        (byte[] image, IReadOnlyList<string> unreadable) = D67Format.Write(disk);
        unreadable.Should().BeEmpty();
        image[0x165A2..0x165A4].Should().Equal((byte)'R', (byte)'C');
        (byte[] again, IReadOnlyList<string> lost) = D67Format.Write(D67Format.Read(image));
        lost.Should().BeEmpty();
        again.Should().Equal(image);
    }
}
