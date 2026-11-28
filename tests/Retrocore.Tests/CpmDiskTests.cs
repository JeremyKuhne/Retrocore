// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Media.Floppy;

namespace Retrocore.Tests;

/// <summary>
///  A file the SDK adds to a CP/M 2.2 disk takes the lowest free blocks and the first unused directory entries, an
///  entry for each 16K, and reads back as CP/M reads it.
/// </summary>
[TestClass]
public class CpmDiskTests
{
    private static readonly CpmGeometry s_kaypro = CpmGeometry.KayproII;

    /// <summary>
    ///  On a Kaypro II disk, blocks are 1K from track 1, the directory in blocks 0 and 1 of the four reserved; a file
    ///  gives user 0, its name and type padded with spaces, its extent, its record count and its blocks, and its last
    ///  record is filled out with <c>$1A</c>. A file over 16K takes a second entry, its extent 1.
    /// </summary>
    [TestMethod]
    public void AddsFilesInBlocksAndExtents()
    {
        byte[] image = Blank();
        byte[] large = [.. Enumerable.Range(0, (17 * 1024) + 5).Select(index => (byte)(index * 7))];
        CpmDisk.Add(image, s_kaypro, "HELLO", "COM", [0xC3, 0x00, 0x01]);
        CpmDisk.Add(image, s_kaypro, "BIG", "DAT", large);

        int directory = 10 * 512;
        image.AsSpan(directory, 18).ToArray().Should().Equal([0, .. "HELLO   COM"u8, 0, 0, 0, 1, 4, 0]);
        image.AsSpan(directory + 32, 16).ToArray().Should().Equal([0, .. "BIG     DAT"u8, 0, 0, 0, 128]);
        image.AsSpan(directory + 48, 16).ToArray().Should().Equal(Enumerable.Range(5, 16).Select(block => (byte)block));
        image.AsSpan(directory + 64, 18).ToArray().Should().Equal([0, .. "BIG     DAT"u8, 1, 0, 0, 9, 21, 22]);
        image[directory + 96].Should().Be(0xE5, "the next entry is unused");

        byte[] hello = CpmDisk.Read(image, s_kaypro, "HELLO", "COM");
        hello.Should().HaveCount(128);
        hello[..3].Should().Equal(0xC3, 0x00, 0x01);
        hello[3..].Should().OnlyContain(value => value == 0x1A);
        CpmDisk.Read(image, s_kaypro, "BIG", "DAT")[..large.Length].Should().Equal(large);

        // An empty file is an entry with no records and no blocks, as CP/M writes one.
        CpmDisk.Add(image, s_kaypro, "EMPTY", "", []);
        image.AsSpan(directory + 96, 17).ToArray().Should().Equal([0, .. "EMPTY      "u8, 0, 0, 0, 0, 0]);
        CpmDisk.Read(image, s_kaypro, "EMPTY", "").Should().BeEmpty();
    }

    /// <summary>
    ///  Blocks a file already holds stay its own, and a name is the SDK's: capitals and digits from a letter, once.
    /// </summary>
    [TestMethod]
    public void KeepsTheDisksFilesAndRefusesWhatItCannotHold()
    {
        byte[] image = Blank();
        CpmDisk.Add(image, s_kaypro, "FIRST", "COM", new byte[3000]);
        CpmDisk.Add(image, s_kaypro, "SECOND", "", [1]);
        image[(10 * 512) + 32 + 16].Should().Be(7, "SECOND takes block 7, after FIRST's 4 to 6 and the four reserved");

        Action add = () => CpmDisk.Add(image, s_kaypro, "FIRST", "COM", [1]);
        add.Should().Throw<ArgumentException>().WithMessage("The disk already has FIRST.COM.");

        // A type's attribute bits, read-only and system, are not its letters.
        image[(10 * 512) + 9] |= 0x80;
        add.Should().Throw<ArgumentException>().WithMessage("The disk already has FIRST.COM.");
        add = () => CpmDisk.Add(image, s_kaypro, "1ST", "COM", [1]);
        add.Should().Throw<ArgumentException>();
        add = () => CpmDisk.Add(image, s_kaypro, "HUGE", "DAT", new byte[200 * 1024]);
        add.Should().Throw<InvalidOperationException>().WithMessage("HUGE.DAT does not fit on the disk:*");
    }

    // A Kaypro II disk with its directory empty: CP/M's unused $E5 throughout.
    private static byte[] Blank()
    {
        byte[] image = new byte[KayproFormat.SingleSidedLength];
        image.AsSpan().Fill(0xE5);
        return image;
    }
}
