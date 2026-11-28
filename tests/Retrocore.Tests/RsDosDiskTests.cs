// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Media.Trs80;

namespace Retrocore.Tests;

/// <summary>
///  An RS-DOS disk the SDK builds reads back through its directory and allocation table, and Disk BASIC reads its
///  files: its machine-language file loads with LOADM.
/// </summary>
[TestClass]
public class RsDosDiskTests
{
    /// <summary>
    ///  Files go in granules from 0, past the directory's track 17, chained in the allocation table, the last
    ///  granule's entry <c>$C0</c> and its sector count; each directory entry gives the name, extension, type, ASCII flag,
    ///  first granule and the bytes of the last sector, and the files read back whole.
    /// </summary>
    [TestMethod]
    public void BuildsTheDirectoryAndTheAllocationTable()
    {
        byte[] large = [.. Enumerable.Range(0, (40 * 256) + 7).Select(index => (byte)(index * 3))];
        byte[] image = RsDosDisk.Create([("GAME", "BIN", RsDosDisk.MachineLanguage, false, [1, 2, 3]), ("DATA", "", RsDosDisk.Data, false, large)]);
        image.Should().HaveCount(35 * 18 * 256);

        int table = ((17 * 18) + 1) * 256;
        image[table].Should().Be(0xC1, "GAME uses one sector of granule 0");
        image.AsSpan(table + 1, 5).ToArray().Should().Equal(2, 3, 4, 5, 0xC5);
        image[table + 6].Should().Be(0xFF, "granule 6 is free");

        int directory = ((17 * 18) + 2) * 256;
        image.AsSpan(directory, 16).ToArray().Should().Equal([.. "GAME    BIN"u8, 2, 0, 0, 0, 3]);
        image.AsSpan(directory + 32, 16).ToArray().Should().Equal([.. "DATA       "u8, 1, 0, 1, 0, 7]);
        image[directory + 64].Should().Be(0xFF, "the directory ends");

        IReadOnlyList<(string Name, string Extension, byte Type, bool Ascii, byte[] Bytes)> files = RsDosDisk.Read(image);
        files.Select(file => (file.Name, file.Extension, file.Type, file.Ascii)).Should().Equal(("GAME", "BIN", (byte)2, false), ("DATA", "", (byte)1, false));
        files[0].Bytes.Should().Equal(1, 2, 3);
        files[1].Bytes.Should().Equal(large);
    }

    /// <summary>
    ///  A file past track 16's granules goes on track 18, past the directory.
    /// </summary>
    [TestMethod]
    public void GranulesPassOverTheDirectoryTrack()
    {
        byte[] filler = new byte[34 * 9 * 256];
        byte[] image = RsDosDisk.Create([("FILLER", "", RsDosDisk.Data, false, filler), ("NEXT", "", RsDosDisk.Data, false, [7])]);
        image[((18 * 18) + 0) * 256].Should().Be(7, "granule 34 is track 18's first half");
        RsDosDisk.Read(image)[1].Bytes.Should().Equal(7);
    }

    /// <summary>
    ///  A machine-language file is Disk BASIC's binary format: each block's 0, length and address, then its bytes, and
    ///  the end's <c>$FF</c>, 0 and EXEC's address.
    /// </summary>
    [TestMethod]
    public void MachineLanguageFileHasLoadmsRecords()
    {
        RsDosDisk.MachineLanguageFile([(0x2700, new byte[] { 0x39, 0x12 })], 0x2701).Should().Equal(
            0, 0, 2, 0x27, 0x00, 0x39, 0x12, 0xFF, 0, 0, 0x27, 0x01);
    }

    /// <summary>
    ///  A disk is read as Disk BASIC reads it: the last sector's count by its low byte, 0 with the high byte set being a
    ///  whole sector; and a last granule that claims more than its nine sectors is damage, not data.
    /// </summary>
    [TestMethod]
    public void ReadsCountsAsDiskBasicDoes()
    {
        byte[] image = RsDosDisk.Create([("DATA", "", RsDosDisk.Data, false, [.. Enumerable.Range(0, 300).Select(index => (byte)index)])]);
        int entry = ((17 * 18) + 2) * 256;
        (image[entry + 14], image[entry + 15]) = (0x01, 0x05);
        RsDosDisk.Read(image)[0].Bytes.Should().HaveCount(256 + 5, "$0105 is 5 bytes in the last sector");
        (image[entry + 14], image[entry + 15]) = (0x02, 0x00);
        RsDosDisk.Read(image)[0].Bytes.Should().HaveCount(256 + 256, "a low byte of 0 is a whole sector");

        image[((17 * 18) + 1) * 256] = 0xCA;
        Action read = () => RsDosDisk.Read(image);
        read.Should().Throw<InvalidDataException>().WithMessage("Granule 0's entry, $CA, ends a file in more sectors than a granule has.");
    }

    /// <summary>
    ///  A name is one the SDK writes, capitals and digits from a letter, and once on the disk; the files must fit.
    /// </summary>
    [TestMethod]
    public void RefusesWhatTheDiskCannotHold()
    {
        Action create = () => RsDosDisk.Create([("NINECHARS", "", RsDosDisk.Data, false, [1])]);
        create.Should().Throw<ArgumentException>().WithMessage("*not a name the SDK puts on a disk*");
        create = () => RsDosDisk.Create([("A", "", RsDosDisk.Data, false, [1]), ("A", "", RsDosDisk.Data, false, [2])]);
        create.Should().Throw<ArgumentException>().WithMessage("Two files are named A. (Parameter 'files')");
        create = () => RsDosDisk.Create([("BIG", "", RsDosDisk.Data, false, new byte[(68 * 9 * 256) + 1])]);
        create.Should().Throw<InvalidOperationException>().WithMessage("BIG does not fit on the disk.");
    }
}
