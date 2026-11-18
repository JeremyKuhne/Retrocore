// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Media;
using Retrocore.Media.Acorn;
using Retrocore.Media.Floppy;

namespace Retrocore.Tests;

/// <summary>
///  The DFS's SSD and DSD images.
/// </summary>
[TestClass]
public class AcornDiskImageTests
{
    /// <summary>
    ///  An SSD holds track after track of 10 FM sectors of 256 bytes; it reads as 40 tracks, and back the same.
    /// </summary>
    [TestMethod]
    public void SsdTracksInOrder()
    {
        byte[] image = new byte[40 * AcornDiskImage.TrackSize];
        for (int index = 0; index < image.Length; index++) { image[index] = (byte)(index / AcornDiskImage.SectorSize); }

        FloppyDisk disk = AcornDiskImage.Read(image, doubleSided: false);
        disk.Cylinders.Should().Be(40);
        disk.Sides.Should().Be(1);
        IReadOnlyList<FloppySector> track = disk.Track(3, 0);
        track.Should().HaveCount(10);
        track[7].Track.Should().Be(3);
        track[7].Side.Should().Be(0);
        track[7].Sector.Should().Be(7);
        track[7].DoubleDensity.Should().BeFalse();
        track[7].Data[0].Should().Be(37);

        EncodedImage written = AcornDiskImage.Encode(disk, doubleSided: false);
        written.IsLossless.Should().BeTrue();
        written.Bytes.Should().Equal(image);
    }

    /// <summary>
    ///  A short image is padded with zeros to the size its catalogue gives: 80 tracks here.
    /// </summary>
    [TestMethod]
    public void ShortImageTakesTheCatalogueSize()
    {
        byte[] image = new byte[2 * AcornDiskImage.SectorSize];
        image[AcornDiskImage.SectorSize + 6] = 0x03;
        image[AcornDiskImage.SectorSize + 7] = 0x20;    // 800 sectors
        FloppyDisk disk = AcornDiskImage.Read(image, doubleSided: false);
        disk.Cylinders.Should().Be(80);
        disk.Track(79, 0)[9].Data.ToArray().Should().OnlyContain(value => value == 0);
    }

    /// <summary>
    ///  A DSD interleaves the sides track by track.
    /// </summary>
    [TestMethod]
    public void DsdInterleavesSides()
    {
        byte[] image = new byte[2 * 40 * AcornDiskImage.TrackSize];
        image[AcornDiskImage.TrackSize] = 0xAB;                         // track 0, side 1, sector 0
        image[(3 * AcornDiskImage.TrackSize) + 256] = 0xCD;             // track 1, side 1, sector 1
        FloppyDisk disk = AcornDiskImage.Read(image, doubleSided: true);
        disk.Sides.Should().Be(2);
        disk.Track(0, 1)[0].Data[0].Should().Be(0xAB);
        disk.Track(1, 1)[1].Data[0].Should().Be(0xCD);
        new AcornDiskCodec("DSD").Encode(disk.Snapshot()).Bytes.Should().Equal(image);
    }

    /// <summary>
    ///  A blank disk is formatted with &amp;E5 and an empty catalogue of its size.
    /// </summary>
    [TestMethod]
    public void BlankIsFormatted()
    {
        FloppyDisk disk = AcornDiskImage.Blank(80);
        disk.Cylinders.Should().Be(80);
        disk.Track(0, 0)[1].Data[7].Should().Be(0x20);
        disk.Track(5, 0)[3].Data[100].Should().Be(0xE5);
    }

    /// <summary>
    ///  What an SSD cannot hold is listed: the second side, and sectors that are not the DFS's.
    /// </summary>
    [TestMethod]
    public void LossesAreListed()
    {
        FloppyDisk disk = AcornDiskImage.Blank(40, doubleSided: true);
        disk.Format(2, 0, [new FloppySector(2, 0, 0, new byte[128], doubleDensity: false)]);
        EncodedImage image = AcornDiskImage.Encode(disk, doubleSided: false);
        image.Losses.Should().Contain(loss => loss.Contains("Side 1", StringComparison.Ordinal));
        image.Losses.Should().Contain(loss => loss.Contains("128 bytes", StringComparison.Ordinal));
    }
}
