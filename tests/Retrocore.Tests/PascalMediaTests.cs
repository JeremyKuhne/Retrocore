// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Media;

namespace Retrocore.Tests;

/// <summary>
///  Apple Pascal's media: Pascal volumes, code files, and sectors read back from a disk's bits. The disk tests use
///  Apple Pascal 1.1 and Apple III Pascal 1.1 when they are present.
/// </summary>
/// <remarks>
///  <para>
///   Apple Pascal's disks are in <c>RETROCORE_APPLE2_PASCAL_DISKS</c> or <c>&lt;cache&gt;\apple2-pascal-disks</c>
///   (<c>UCSD Pascal 1.1_0.dsk</c> to <c>1.1_3.dsk</c>), and Apple III Pascal's with the other Apple III disks.
///  </para>
/// </remarks>
[TestClass]
public class PascalMediaTests
{
    /// <summary>
    ///  Gets the folder of Apple Pascal's Apple II disks.
    /// </summary>
    internal static string Apple2Disks => Environment.GetEnvironmentVariable("RETROCORE_APPLE2_PASCAL_DISKS")
        ?? Path.Join(ExternalTestData.Root, "apple2-pascal-disks");

    /// <summary>
    ///  Reads an Apple Pascal disk, or ends the test as inconclusive without it.
    /// </summary>
    /// <param name="disk">The disk's file name.</param>
    /// <returns>The volume.</returns>
    internal static PascalVolume Apple2Volume(string disk)
    {
        string path = Path.Join(Apple2Disks, disk);
        if (!File.Exists(path)) { Assert.Inconclusive($"Set RETROCORE_APPLE2_PASCAL_DISKS to a folder with {disk}."); }
        return PascalVolume.Read(File.ReadAllBytes(path), proDosOrder: false);
    }

    /// <summary>
    ///  A volume made here reads back: its name, size and files, each file's length and bytes, and its date.
    /// </summary>
    [TestMethod]
    public void VolumeReadsItsDirectoryAndFiles()
    {
        byte[] blocks = new byte[280 * 512];
        Span<byte> directory = blocks.AsSpan(2 * 512);
        directory[2] = 6;
        directory[6] = 4;
        "TEST"u8.CopyTo(directory[7..]);
        directory[14] = 24;
        directory[15] = 1;
        directory[16] = 1;

        // HELLO.TEXT in blocks 10 and 11, using 3 bytes of the second, changed 13-Nov-86.
        Span<byte> entry = directory[26..];
        entry[0] = 10;
        entry[2] = 12;
        entry[4] = (byte)PascalFileKind.Text;
        entry[6] = 10;
        "HELLO.TEXT"u8.CopyTo(entry[7..]);
        entry[22] = 3;
        int date = 11 | (13 << 4) | (86 << 9);
        entry[24] = (byte)date;
        entry[25] = (byte)(date >> 8);
        blocks[(10 * 512) + 7] = 0x42;
        blocks[(11 * 512) + 2] = 0x43;

        byte[] image = ProDosToDos(blocks);
        PascalVolume.IsPascalVolume(image, proDosOrder: false).Should().BeTrue();
        PascalVolume.IsPascalVolume(blocks, proDosOrder: false).Should().BeFalse();

        PascalVolume volume = PascalVolume.Read(image, proDosOrder: false);
        volume.Name.Should().Be("TEST");
        volume.Blocks.Should().Be(280);
        volume.Files.Should().ContainSingle();
        PascalFileEntry file = volume.Files[0];
        file.Should().Be(new PascalFileEntry("HELLO.TEXT", 10, 12, PascalFileKind.Text, 3, new DateOnly(1986, 11, 13)));
        file.Length.Should().Be(515);

        byte[] data = volume.ReadFile("hello.text");
        data.Should().HaveCount(515);
        data[7].Should().Be(0x42);
        data[514].Should().Be(0x43);
        PascalVolume.Read(blocks, proDosOrder: true).ReadFile("HELLO.TEXT").Should().Equal(data);
    }

    /// <summary>
    ///  A code file made here reads as its segments and procedures: a p-code procedure's entry, exit, sizes and
    ///  lexical level, and an assembled procedure's relocation lists.
    /// </summary>
    [TestMethod]
    public void CodeFileReadsSegmentsAndProcedures()
    {
        // Procedure 1 is p-code: 4 bytes of code from 0, exit at 2. Procedure 2 is assembled: code at 4, one
        // procedure-relative relocation at 6.
        List<byte> code = [0x00, 0x00, 0xAD, 0x00, 0xEA, 0xEA, 0x34, 0x12];
        void Word(int value) { code.Add((byte)value); code.Add((byte)(value >> 8)); }
        int Here() => code.Count;

        Word(8);                                  // data size
        Word(2);                                  // parameter size
        Word(Here() - 2);                         // exit, self-relative
        Word(Here() - 0);                         // entry
        int first = Here();
        code.Add(1);                              // procedure 1, lexical level 0
        code.Add(0);

        // Read downward from the attributes: the entry, then the base-, segment-, procedure- and interpreter-relative
        // lists, each a count with its pointers below it.
        Word(0);                                  // interpreter-relative: none
        Word(Here() - 6);                         // the relocated word at 6
        Word(1);                                  // procedure-relative: one
        Word(0);                                  // segment-relative: none
        Word(0);                                  // base-relative: none
        Word(Here() - 4);                         // entry: 4
        int second = Here();
        code.Add(0);                              // assembled
        code.Add(0xFF);                           // lexical level -1
        int dictionary = Here();
        Word(dictionary - second);                // procedure 2's attributes, self-relative
        Word(dictionary + 2 - first);             // procedure 1's
        code.Add(1);                              // segment 1
        code.Add(2);                              // two procedures

        byte[] file = new byte[1024];
        file[4] = 1;
        file[6] = (byte)code.Count;
        "MAIN    "u8.CopyTo(file.AsSpan(64 + 8));
        file[256 + 2] = 1;
        file[256 + 3] = 0x42;                     // p-code, least significant byte first, version 2
        code.CopyTo(file, 512);

        PascalCodeFile.IsCodeFile(file).Should().BeTrue();
        PascalCodeFile codeFile = PascalCodeFile.Read(file);
        PascalSegment segment = codeFile.Segments.Should().ContainSingle().Subject;
        segment.Slot.Should().Be(1);
        segment.Name.Should().Be("MAIN");
        segment.Number.Should().Be(1);
        segment.MachineType.Should().Be(PascalMachineType.PcodeLeastFirst);
        segment.Version.Should().Be(2);
        segment.Code.Should().HaveCount(code.Count);

        PascalProcedure pcode = segment.Procedures.Single(procedure => procedure.Index == 1);
        pcode.IsNative.Should().BeFalse();
        (pcode.Entry, pcode.Exit, pcode.ParameterSize, pcode.DataSize, pcode.LexicalLevel).Should().Be((0, 2, 2, 8, 0));

        PascalProcedure native = segment.Procedures.Single(procedure => procedure.Index == 2);
        native.IsNative.Should().BeTrue();
        native.Entry.Should().Be(4);
        native.LexicalLevel.Should().Be(-1);
        native.Relocations.Select(list => list.Count).Should().Equal(0, 0, 1, 0);
        native.Relocations[2][0].Should().Be(6);
    }

    /// <summary>
    ///  A segment whose code runs past the file is refused.
    /// </summary>
    [TestMethod]
    public void CodeFileRefusesASegmentPastItsEnd()
    {
        byte[] file = new byte[512];
        file[0] = 1;
        file[3] = 2;
        PascalCodeFile.IsCodeFile(file).Should().BeFalse();
        Action read = () => PascalCodeFile.Read(file);
        read.Should().Throw<InvalidDataException>();
    }

    /// <summary>
    ///  A text file reads as its lines after the header page, with packed leading spaces expanded and the pages'
    ///  padding dropped.
    /// </summary>
    [TestMethod]
    public void TextFileReadsItsLines()
    {
        byte[] file = new byte[3072];
        file[0] = 0x55;
        byte[] first = [.. "BEGIN"u8, 0x0D, 0x10, 32 + 2, .. "X"u8, 0x0D];
        first.CopyTo(file, 1024);
        byte[] second = [.. "END."u8, 0x0D];
        second.CopyTo(file, 2048);
        PascalTextFile.Read(file).Should().Be("BEGIN\n  X\nEND.\n");
    }

    /// <summary>
    ///  A disk made from a sector image reads back to the same image, in either sector order.
    /// </summary>
    [TestMethod]
    public void SectorsReadBackFromADisksBits()
    {
        byte[] image = new byte[35 * 4096];
        new Random(1980).NextBytes(image);
        SectorDiskReader.Read(SectorDiskConverter.Convert(image, proDosOrder: false), proDosOrder: false).Should().Equal(image);

        byte[] proDos = SectorDiskReader.Read(SectorDiskConverter.Convert(image, proDosOrder: false), proDosOrder: true);
        SectorDiskReader.Read(SectorDiskConverter.Convert(proDos, proDosOrder: true), proDosOrder: false).Should().Equal(image);
    }

    /// <summary>
    ///  A blank disk has no sectors to read.
    /// </summary>
    [TestMethod]
    public void BlankDiskHasNoSectors()
    {
        Action read = () => SectorDiskReader.Read(WozDisk.CreateBlank(), proDosOrder: false);
        read.Should().Throw<InvalidDataException>();
    }

    /// <summary>
    ///  Apple Pascal 1.1's APPLE3: lists its sample programs, and their code files read as one p-code segment each.
    /// </summary>
    [TestMethod]
    public void Apple3VolumeListsSamplePrograms()
    {
        PascalVolume volume = Apple2Volume("UCSD Pascal 1.1_3.dsk");
        volume.Name.Should().Be("APPLE3");
        volume.Files.Select(file => file.Name).Should().Contain(["HILBERT.TEXT", "HILBERT.CODE", "TREE.CODE"]);
        volume.Files.Single(file => file.Name == "HILBERT.CODE").Kind.Should().Be(PascalFileKind.Code);

        PascalCodeFile hilbert = PascalCodeFile.Read(volume.ReadFile("HILBERT.CODE"));
        PascalSegment segment = hilbert.Segments.Should().ContainSingle().Subject;
        segment.Name.Should().Be("HILBERT");
        segment.MachineType.Should().Be(PascalMachineType.PcodeLeastFirst);
        segment.Version.Should().Be(2);
        segment.Procedures.Should().NotBeEmpty();
        segment.Procedures.Single(procedure => procedure.Index == 1).LexicalLevel.Should().Be(0);
    }

    /// <summary>
    ///  Every code file on Apple Pascal 1.1's and Apple III Pascal 1.1's disks reads, and its p-code procedures'
    ///  entries and exits are inside their segments.
    /// </summary>
    [TestMethod]
    public void EveryCodeFileOnTheDisksReads()
    {
        int procedures = 0;
        foreach ((string name, byte[] data) in CodeFiles())
        {
            PascalCodeFile file = PascalCodeFile.Read(data);
            foreach (PascalSegment segment in file.Segments)
            {
                foreach (PascalProcedure procedure in segment.Procedures)
                {
                    procedure.Entry.Should().BeLessThan(procedure.Attributes, $"{name} {segment.Name}.{procedure.Index}");
                    procedure.Exit.Should().BeInRange(procedure.Entry, procedure.Attributes);
                    procedures++;
                }
            }
        }

        procedures.Should().BeGreaterThan(1000);
    }

    /// <summary>
    ///  Gets the code files on the Apple Pascal 1.1 and 1.3 and Apple III Pascal 1.1 and 1.2 disks, or ends the test as
    ///  inconclusive without 1.1's.
    /// </summary>
    /// <returns>Each file's disk and name, and its contents.</returns>
    internal static List<(string Name, byte[] Data)> CodeFiles()
    {
        List<(string, byte[])> files = [];
        // Apple Pascal 1.3's disks join 1.1's where they are present.
        string[] apple2 =
        [
            "UCSD Pascal 1.1_0.dsk", "UCSD Pascal 1.1_1.dsk", "UCSD Pascal 1.1_2.dsk", "UCSD Pascal 1.1_3.dsk",
            .. ((string[])["UCSD Pascal 1.3_0.DSK", "UCSD Pascal 1.3_1.DSK", "UCSD Pascal 1.3_2.DSK", "UCSD Pascal 1.3_3.DSK"])
                .Where(disk => File.Exists(Path.Join(Apple2Disks, disk)))
        ];

        foreach (string disk in apple2)
        {
            PascalVolume volume = Apple2Volume(disk);
            foreach (PascalFileEntry entry in volume.Files)
            {
                byte[] data = volume.ReadFile(entry);
                if (entry.Kind == PascalFileKind.Code || (entry.Name is "SYSTEM.PASCAL" && PascalCodeFile.IsCodeFile(data)))
                {
                    files.Add(($"{volume.Name}:{entry.Name}", data));
                }
            }
        }

        foreach (string disk in (string[])["Apple3Pascal1.1Disk1.dsk", "Apple3Pascal1.1Disk2.dsk", "Apple3Pascal1.1Disk3.dsk", "Apple3Pascal1.2UpdateDisk1.dsk", "Apple3Pascal1.2UpdateDisk2.dsk"])
        {
            SosVolume volume = SosVolumeTests.Volume(disk);
            foreach (SosFileEntry entry in volume.Files)
            {
                byte[] data = volume.ReadFile(entry.Name);
                if (entry.FileType == 0x02 || entry.Name is "SYSTEM.PASCAL")
                {
                    files.Add(($"/{volume.Name}/{entry.Name}", data));
                }
            }
        }

        return files;
    }

    // Lays ProDOS-order blocks out as a DOS-order image.
    private static byte[] ProDosToDos(byte[] blocks) =>
        SectorDiskReader.Read(SectorDiskConverter.Convert(blocks, proDosOrder: true), proDosOrder: false);
}
