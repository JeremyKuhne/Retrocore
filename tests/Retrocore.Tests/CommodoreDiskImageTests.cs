// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Media;
using Retrocore.Media.Commodore;

namespace Retrocore.Tests;

/// <summary>
///  Commodore disk images: a D64's sectors laid out as GCR and read back, and a G64's cells kept as they are.
/// </summary>
[TestClass]
public class CommodoreDiskImageTests
{
    /// <summary>
    ///  A D64's sectors, laid out as the 4040 writes them, read back the same.
    /// </summary>
    [TestMethod]
    public void D64RoundTrips()
    {
        byte[] image = RandomImage();
        (byte[] written, IReadOnlyList<string> unreadable) = D64Format.Write(D64Format.Read(image));
        unreadable.Should().BeEmpty();
        written.Should().Equal(image);
    }

    /// <summary>
    ///  Each track has its zone's sector count and cells, on the even half-track positions.
    /// </summary>
    [TestMethod]
    public void D64LaysOutTheZones()
    {
        CommodoreDisk disk = D64Format.Read(RandomImage());
        disk.BitCount(0).Should().Be(7_692 * 8);
        disk.BitCount((18 - 1) * 2).Should().Be(7_142 * 8);
        disk.BitCount((25 - 1) * 2).Should().Be(6_666 * 8);
        disk.BitCount((35 - 1) * 2).Should().Be(6_250 * 8);
        disk.BitCount(1).Should().Be(0, "half tracks hold nothing");
        disk.Zone(0).Should().Be(3);
        disk.Zone((35 - 1) * 2).Should().Be(0);
    }

    /// <summary>
    ///  A G64 keeps every cell: a disk written as one and read back writes the same file, and holds the same sectors.
    /// </summary>
    [TestMethod]
    public void G64RoundTrips()
    {
        byte[] image = RandomImage();
        byte[] g64 = G64Format.Write(D64Format.Read(image));
        G64Format.IsG64(g64).Should().BeTrue();
        CommodoreDisk disk = G64Format.Read(g64);
        G64Format.Write(disk).Should().Equal(g64);
        D64Format.Write(disk).Image.Should().Equal(image);
    }

    /// <summary>
    ///  The codec reads either format by its contents and writes the one it was made for; a D64 names the sectors
    ///  it could not hold.
    /// </summary>
    [TestMethod]
    public void CodecChoosesByContents()
    {
        byte[] image = RandomImage();
        (CommodoreDisk disk, CommodoreDiskCodec codec) = CommodoreDiskCodec.Load(image);
        codec.Format.Should().Be("D64");
        CommodoreDiskCodec.Load(G64Format.Write(disk)).Codec.Format.Should().Be("G64");

        EncodedImage d64 = codec.Encode(disk.Snapshot());
        d64.Bytes.Should().Equal(image);
        d64.Losses.Should().BeEmpty();

        EncodedImage blank = codec.Encode(CommodoreDisk.Blank().Snapshot());
        blank.Losses.Should().HaveCount(GcrLayout.Sectors);
        blank.Losses[0].Should().Be("track 1, sector 0, which does not read, written as zeros.");

        FluentActions.Invoking(() => CommodoreDiskCodec.Load(new byte[1000])).Should().Throw<InvalidDataException>();
    }

    /// <summary>
    ///  A write changes the disk's version, as the drives' unsaved mark needs; writing what is there does not.
    /// </summary>
    [TestMethod]
    public void WritesChangeTheVersion()
    {
        CommodoreDisk disk = D64Format.Read(RandomImage());
        long version = disk.Version;
        bool cell = disk.Read(0, 100);
        disk.Write(0, 100, cell);
        disk.Version.Should().Be(version);
        disk.Write(0, 100, !cell);
        disk.Version.Should().Be(version + 1);
        disk.Read(0, 100).Should().Be(!cell);
    }

    /// <summary>
    ///  A D67's 690 sectors, laid out as the 2040 writes them, read back the same, with 20 sectors on each of tracks
    ///  18-24; the codec reads it by its size and writes it back as D67.
    /// </summary>
    [TestMethod]
    public void D67RoundTrips()
    {
        byte[] image = RandomImage(D67Format.Size);
        (CommodoreDisk disk, CommodoreDiskCodec codec) = CommodoreDiskCodec.Load(image);
        codec.Format.Should().Be("D67");
        GcrLayout.SectorsOn(18, CommodoreDos.Dos1).Should().Be(20);
        GcrLayout.FirstSector(25, CommodoreDos.Dos1).Should().Be((17 * 21) + (7 * 20));

        (byte[] written, IReadOnlyList<string> unreadable) = D67Format.Write(disk);
        unreadable.Should().BeEmpty();
        written.Should().Equal(image);
        codec.Encode(disk.Snapshot()).Bytes.Should().Equal(image);
        disk.BitCount((18 - 1) * 2).Should().Be(7_142 * 8, "the zones' tracks are as long as DOS 2's");
    }

    /// <summary>
    ///  Sectors with a header and no data block, as DOS 1 formats them, write to a D67 as zeros without a loss; on a
    ///  D64 they are losses, and a sector with no header is a loss on either.
    /// </summary>
    [TestMethod]
    public void D67KeepsUnwrittenSectorsAsZeros()
    {
        CommodoreDisk disk = CommodoreDisk.Blank();
        int position = (5 - 1) * 2;
        GcrBitWriter writer = new(disk.BitCount(position));
        for (int sector = 0; sector < 21; sector++)
        {
            writer.Ones(20);
            writer.Bytes([0x08, (byte)(sector ^ 5 ^ 'B' ^ 'A'), (byte)sector, 5, (byte)'B', (byte)'A']);
            writer.Zeros(100);
        }

        disk.SetTrack(position, writer.Buffer, disk.BitCount(position), GcrLayout.Zone(5));
        (byte[] image, IReadOnlyList<string> unreadable) = D67Format.Write(disk);
        unreadable.Should().NotContain(sector => sector.StartsWith("track 5,", StringComparison.Ordinal));
        unreadable.Should().HaveCount(D67Format.Size / GcrLayout.SectorSize - 21);
        image.Should().OnlyContain(value => value == 0);
        D64Format.Write(disk).Unreadable.Should().HaveCount(GcrLayout.Sectors);
    }

    private static byte[] RandomImage(int size = D64Format.Size)
    {
        byte[] image = new byte[size];
        new Random(1541).NextBytes(image);
        return image;
    }
}
