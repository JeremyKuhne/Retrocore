// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Media;

namespace Retrocore.Tests;

/// <summary>
///  Reading SOS volumes and their driver files, from Apple's Apple III disks when they are present.
/// </summary>
[TestClass]
public class SosVolumeTests
{
    /// <summary>
    ///  Gets the folder of Apple's Apple III disks.
    /// </summary>
    internal static string Disks => Environment.GetEnvironmentVariable("RETROCORE_APPLE3_DISKS")
        ?? Path.Join(ExternalTestData.Root, "apple3-disks");

    /// <summary>
    ///  Reads a volume from one of Apple's disks, or ends the test as inconclusive without it.
    /// </summary>
    /// <param name="disk">The disk's file name.</param>
    /// <returns>The volume.</returns>
    internal static SosVolume Volume(string disk)
    {
        string path = Path.Join(Disks, disk);
        if (!File.Exists(path)) { Assert.Inconclusive($"Set RETROCORE_APPLE3_DISKS to a folder with {disk}."); }
        return SosVolume.Read(File.ReadAllBytes(path), proDosOrder: false);
    }

    /// <summary>
    ///  The Business BASIC disk's volume directory lists SOS's three files, and the kernel and driver file read whole.
    /// </summary>
    [TestMethod]
    public void BusinessBasicDiskListsAndReadsSosFiles()
    {
        SosVolume volume = Volume("Apple3BusBasic1.23.dsk");
        volume.Name.Should().Be("BASIC");
        volume.Files.Select(file => file.Name).Should().StartWith(["SOS.KERNEL", "SOS.DRIVER", "SOS.INTERP"]);

        byte[] kernel = volume.ReadFile("sos.kernel");
        kernel.Should().HaveCount(22016);
        kernel.AsSpan(0, 8).ToArray().Should().Equal("SOS KRNL"u8.ToArray());

        SosDriverFile drivers = SosDriverFile.Read(volume.ReadFile("SOS.DRIVER"));
        drivers.Drivers.Select(driver => driver.Name).Should().Equal(".CONSOLE", ".RS232", ".GRAFIX", ".SILENTYPE", ".AUDIO", ".PRINTER");
        drivers.Drivers[0].Code.Should().HaveCount(4007);
        drivers.Drivers[0].Relocations.Should().HaveCount(570);
        drivers.Drivers[0].Comment.Should().StartWith("Console Driver -- Copyright (C) 1983 by Apple Computer");
    }

    /// <summary>
    ///  The same kernel is on the Business BASIC and System Utilities disks.
    /// </summary>
    [TestMethod]
    public void BusinessBasicAndUtilitiesShareTheKernel()
    {
        byte[] basic = Volume("Apple3BusBasic1.23.dsk").ReadFile("SOS.KERNEL");
        byte[] utilities = Volume("Apple3SOS1.3SysUtils.dsk").ReadFile("SOS.KERNEL");
        utilities.Should().Equal(basic);
    }

    /// <summary>
    ///  A driver code file for the System Configuration Program reads as its driver: its code, from its DIB, and the
    ///  code's procedure-relative relocations. The Utilities Data disk's console driver predates comment records.
    /// </summary>
    [TestMethod]
    public void DriverCodeFileReadsItsDriver()
    {
        SosDriver console = SosDriverCodeFile.Read(Volume("Apple3SystemUtilData.dsk").ReadFile("CONSOLE.DRIVER"));
        console.Name.Should().Be(".CONSOLE");
        console.Comment.Should().BeEmpty();
        console.Relocations.Should().NotBeEmpty().And.BeInAscendingOrder();
        console.Relocations[^1].Should().BeLessThan(console.Code.Length - 1);
    }

    /// <summary>
    ///  A volume directory whose blocks link back to one already read is refused rather than read forever.
    /// </summary>
    [TestMethod]
    public void DirectoryThatLoopsIsRefused()
    {
        byte[] image = Volume(next: 2, keyBlock: 7);
        Action read = () => SosVolume.Read(image, proDosOrder: true);
        read.Should().Throw<InvalidDataException>().WithMessage("*loop*");
    }

    /// <summary>
    ///  A file whose blocks are past the end of the volume reads as damaged, not as an argument out of range.
    /// </summary>
    [TestMethod]
    public void FilePastTheVolumeIsDamaged()
    {
        SosVolume volume = SosVolume.Read(Volume(next: 0, keyBlock: 300), proDosOrder: true);
        volume.Files.Should().ContainSingle().Which.Name.Should().Be("F");
        Action read = () => volume.ReadFile("F");
        read.Should().Throw<InvalidDataException>().WithMessage("*past the end*");
    }

    /// <summary>
    ///  A hard disk's image of whole blocks reads past a floppy's 280, and an image of partial blocks is refused.
    /// </summary>
    [TestMethod]
    public void HardDiskImageReadsPastAFloppy()
    {
        byte[] image = new byte[9728 * 512];
        Volume(next: 0, keyBlock: 9000).AsSpan(0, 3 * 512).CopyTo(image);
        image[(9000 * 512) + 3] = 0x42;
        SosVolume volume = SosVolume.ReadBlocks(image);
        volume.Name.Should().Be("V");
        volume.ReadFile("F")[3].Should().Be(0x42);

        Action partial = () => SosVolume.ReadBlocks(new byte[(3 * 512) + 1]);
        partial.Should().Throw<InvalidDataException>();
    }

    /// <summary>
    ///  A driver file without its signature is refused.
    /// </summary>
    [TestMethod]
    public void DriverFileNeedsItsSignature()
    {
        Action read = () => SosDriverFile.Read("SOS KRNL\0\0"u8);
        read.Should().Throw<InvalidDataException>();
    }

    /// <summary>
    ///  A driver file's fields read in order: the file's comment, then each driver's comment, code and relocations.
    /// </summary>
    [TestMethod]
    public void DriverFileReadsItsFields()
    {
        byte[] code = new byte[20];
        code[4] = 4;
        ".ABC"u8.CopyTo(code.AsSpan(5));
        byte[] file = [.. "SOS DRVR"u8, 2, 0, (byte)'h', (byte)'i', 1, 0, (byte)'c', 20, 0, .. code, 2, 0, 3, 0, 0xFF, 0xFF];

        SosDriverFile drivers = SosDriverFile.Read(file);
        drivers.Comment.Should().Be("hi");
        drivers.Drivers.Should().ContainSingle();
        drivers.Drivers[0].Name.Should().Be(".ABC");
        drivers.Drivers[0].Comment.Should().Be("c");
        drivers.Drivers[0].Relocations.Should().Equal(3);
    }

    // A ProDOS-order volume named V whose directory's first block links to another, with one seedling file, F.
    private static byte[] Volume(int next, int keyBlock)
    {
        byte[] image = new byte[280 * 512];
        Span<byte> directory = image.AsSpan(2 * 512, 512);
        directory[2] = (byte)next;
        directory[4] = 0xF1;
        directory[5] = (byte)'V';
        directory[0x23] = 0x27;
        directory[0x24] = 0x0D;
        Span<byte> entry = directory[(4 + 0x27)..];
        entry[0] = 0x11;
        entry[1] = (byte)'F';
        entry[0x10] = 0x06;
        entry[0x11] = (byte)keyBlock;
        entry[0x12] = (byte)(keyBlock >> 8);
        entry[0x15] = 10;
        return image;
    }

    /// <summary>
    ///  A built volume reads back: its name, each file's type, auxiliary type and contents as a seedling, an empty file
    ///  or a sapling, in either sector order, with the bitmap marking the blocks after the files free.
    /// </summary>
    /// <param name="proDosOrder">Whether the image is in ProDOS's sector order.</param>
    [TestMethod]
    [DataRow(data: false)]
    [DataRow(data: true)]
    public void BuiltVolumeReadsBack(bool proDosOrder)
    {
        byte[] large = [.. Enumerable.Range(0, 70_000).Select(index => (byte)(index * 7))];
        SosVolumeBuilder builder = new("work");
        builder.Add("SMALL.TEXT", 0x03, 0x1234, "HELLO"u8);
        builder.Add("EMPTY", 0x06, 0, []);
        builder.Add("Large.Code", 0x02, 0, large);
        builder.BlocksUsed.Should().Be(7 + 1 + 1 + 138);

        SosVolume volume = SosVolume.Read(builder.Build(proDosOrder), proDosOrder);
        volume.Name.Should().Be("WORK");
        volume.Files.Select(file => (file.Name, file.StorageType, file.FileType, file.AuxType, file.EndOfFile)).Should().Equal(
            ("SMALL.TEXT", 1, 0x03, 0x1234, 5), ("EMPTY", 1, 0x06, 0, 0), ("LARGE.CODE", 2, 0x02, 0, 70_000));

        volume.ReadFile("small.text").Should().Equal("HELLO"u8.ToArray());
        volume.ReadFile("EMPTY").Should().BeEmpty();
        volume.ReadFile("LARGE.CODE").Should().Equal(large);

        byte[] bitmap = volume.Block(6);
        int free = Enumerable.Range(0, 280).Count(block => (bitmap[block / 8] & (0x80 >> (block % 8))) != 0);
        free.Should().Be(280 - builder.BlocksUsed);
        (bitmap[builder.BlocksUsed / 8] & (0x80 >> (builder.BlocksUsed % 8))).Should().NotBe(0, "the first block after the files is free");
    }

    /// <summary>
    ///  A builder takes only SOS names, a name once, and files that fit.
    /// </summary>
    [TestMethod]
    public void BuilderRefusesWhatSosCannotHold()
    {
        Action badVolume = () => _ = new SosVolumeBuilder("1DISK");
        badVolume.Should().Throw<ArgumentException>();
        SosVolumeBuilder builder = new("DISK");
        Action badName = () => builder.Add("A FILE", 0x06, 0, []);
        badName.Should().Throw<ArgumentException>();
        builder.Add("FILE", 0x06, 0, []);
        Action again = () => builder.Add("file", 0x06, 0, []);
        again.Should().Throw<ArgumentException>();
        Action tree = () => builder.Add("TREE", 0x06, 0, new byte[(256 * 512) + 1]);
        tree.Should().Throw<ArgumentException>();
        builder.Add("BIG", 0x06, 0, new byte[256 * 512]);
        Action full = () => builder.Add("MORE", 0x06, 0, new byte[20 * 512]);
        full.Should().Throw<InvalidOperationException>();
    }

    /// <summary>
    ///  A volume built from Apple III Pascal's first disk, with its boot blocks, holds the same files.
    /// </summary>
    [TestMethod]
    public void BuiltVolumeCopiesAnotherVolumesFiles()
    {
        SosVolume source = Volume("Apple3Pascal1.1Disk1.dsk");
        SosVolumeBuilder builder = new(source.Name);
        builder.BootFrom(source);
        foreach (SosFileEntry file in source.Files) { builder.Add(source, file.Name); }

        SosVolume copy = SosVolume.Read(builder.Build(proDosOrder: false), proDosOrder: false);
        copy.Block(0).Should().Equal(source.Block(0));
        copy.Block(1).Should().Equal(source.Block(1));
        copy.Files.Select(file => (file.Name, file.FileType, file.AuxType, file.EndOfFile)).Should().Equal(
            source.Files.Select(file => (file.Name, file.FileType, file.AuxType, file.EndOfFile)));

        foreach (SosFileEntry file in source.Files)
        {
            copy.ReadFile(file.Name).Should().Equal(source.ReadFile(file.Name), file.Name);
        }
    }
}