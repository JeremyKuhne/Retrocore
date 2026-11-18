// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Buffers.Binary;
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

        // The D67 save says how many it kept as zeros, rather than zeroing them unsaid.
        EncodedImage saved = new CommodoreDiskCodec("D67").Encode(disk.Snapshot());
        saved.Notes.Should().Equal("21 sectors DOS 1 formatted but never wrote, kept as zeros.");
    }

    /// <summary>
    ///  A disk read from an image is the image, with nothing to save, in each format.
    /// </summary>
    [TestMethod]
    public void ReadingAnImageLeavesTheDiskClean()
    {
        CommodoreDisk d64 = D64Format.Read(RandomImage());
        d64.IsDirty.Should().BeFalse();
        D67Format.Read(RandomImage(D67Format.Size)).IsDirty.Should().BeFalse();
        G64Format.Read(G64Format.Write(d64)).IsDirty.Should().BeFalse();
        CommodoreDiskCodec.Load(RandomImage()).Disk.IsDirty.Should().BeFalse();

        d64.Write(0, 100, !d64.Read(0, 100));
        d64.IsDirty.Should().BeTrue();
    }

    /// <summary>
    ///  A code no nibble encodes makes its block bad, though reading it as zero would leave the checksum right, as
    ///  the drive's byte decoding error does.
    /// </summary>
    [TestMethod]
    public void AnInvalidCodeMakesTheSectorUnreadable()
    {
        (byte[] bits, int count) = GcrLayout.WriteTrack(1, new byte[21 * GcrLayout.SectorSize], ((byte)'A', (byte)'B'));
        GcrLayout.ReadTrack(bits, count, 1, new byte[21 * GcrLayout.SectorSize]).Should().OnlyContain(found => found);

        // Sector 0's first data byte: after a sync of 40, the header's 6 bytes, the gap's 9, a sync of 40 and the mark.
        int first = 40 + 60 + 90 + 40 + 10;
        for (int cell = first; cell < first + 5; cell++) { bits[cell >> 3] &= (byte)~(0x80 >> (cell & 7)); }

        bool[] found = GcrLayout.ReadTrack(bits, count, 1, new byte[21 * GcrLayout.SectorSize]);
        found[0].Should().BeFalse("00000 encodes no nibble");
        found[1..].Should().OnlyContain(good => good);
    }

    /// <summary>
    ///  A bad copy of a sector after a good one leaves the good one's bytes.
    /// </summary>
    [TestMethod]
    public void ABadCopyAfterAGoodOneKeepsTheGoodOne()
    {
        GcrBitWriter writer = new(GcrLayout.TrackBits(3));
        byte[] good = [.. Enumerable.Range(0, GcrLayout.SectorSize).Select(value => (byte)value)];
        WriteSector(writer, good, checksum: Xor(good));
        WriteSector(writer, new byte[GcrLayout.SectorSize], checksum: 0x55);

        byte[] sectors = new byte[21 * GcrLayout.SectorSize];
        bool[] found = GcrLayout.ReadTrack(writer.Buffer, GcrLayout.TrackBits(3), 1, sectors);
        found[0].Should().BeTrue();
        sectors.AsSpan(0, GcrLayout.SectorSize).ToArray().Should().Equal(good);

        static void WriteSector(GcrBitWriter writer, byte[] data, byte checksum)
        {
            writer.Ones(40);
            writer.Bytes([0x08, (byte)(0 ^ 1 ^ 'B' ^ 'A'), 0, 1, (byte)'B', (byte)'A']);
            writer.Zeros(9);
            writer.Ones(40);
            writer.Byte(0x07);
            writer.Bytes(data);
            writer.Byte(checksum);
            writer.Zeros(12);
        }

        static byte Xor(byte[] data)
        {
            byte sum = 0;
            foreach (byte value in data) { sum ^= value; }
            return sum;
        }
    }

    /// <summary>
    ///  An error table whose codes all say good reads as the sectors alone; one that marks a sector damaged is refused,
    ///  rather than read back repaired.
    /// </summary>
    [TestMethod]
    public void ADamagedErrorTableIsRefused()
    {
        byte[] image = [.. RandomImage(), .. Enumerable.Repeat((byte)0x01, GcrLayout.Sectors)];
        D64Format.Write(D64Format.Read(image)).Image.Should().Equal(image[..D64Format.Size]);

        image[D64Format.Size + GcrLayout.FirstSector(18) + 3] = 0x05;
        Action read = () => D64Format.Read(image);
        read.Should().Throw<InvalidDataException>().WithMessage("*1 sector damaged, the first track 18, sector 3 (code $05)*");
    }

    /// <summary>
    ///  A D67 written as a D64 loses each zone-2 track's 20th sector, which the save lists; as a G64 or D67 it loses
    ///  nothing.
    /// </summary>
    [TestMethod]
    public void SectorsALayoutHasNoPlaceForAreLosses()
    {
        MediumSnapshot snapshot = D67Format.Read(RandomImage(D67Format.Size)).Snapshot();
        List<string> dropped = [];
        for (int track = 18; track <= 24; track++)
        {
            dropped.Add($"track {track}, sector 19, which a D64 image has no place for.");
        }

        new CommodoreDiskCodec("D64").Encode(snapshot).Losses.Should().Equal(dropped);
        new CommodoreDiskCodec("D67").Encode(snapshot).Losses.Should().BeEmpty();
        new CommodoreDiskCodec("G64").Encode(snapshot).Losses.Should().BeEmpty();

        // Anything written at a half-track is lost too.
        CommodoreDisk disk = D64Format.Read(RandomImage());
        disk.SetTrack(1, disk.Track(0), disk.BitCount(0), disk.Zone(0));
        new CommodoreDiskCodec("D64").Encode(disk.Snapshot()).Losses.Should()
            .Equal("half-track 1.5, which a D64 image has no place for.");
    }

    /// <summary>
    ///  A G64 track whose speed table gives every byte one zone reads at that zone; one that mixes zones is refused,
    ///  since a disk keeps one zone a track.
    /// </summary>
    [TestMethod]
    public void AMixedSpeedTrackIsRefused()
    {
        byte[] image = G64Format.Write(D64Format.Read(RandomImage()));
        int offset = (int)BinaryPrimitives.ReadUInt32LittleEndian(image.AsSpan(12));
        int length = BinaryPrimitives.ReadUInt16LittleEndian(image.AsSpan(offset));
        int table = image.Length;
        byte[] withTable = [.. image, .. Enumerable.Repeat((byte)0b10_10_10_10, (length + 3) / 4)];
        BinaryPrimitives.WriteUInt32LittleEndian(withTable.AsSpan(12 + (image[9] * 4)), (uint)table);
        G64Format.Read(withTable).Zone(0).Should().Be(2);

        withTable[table + 10] = 0b10_10_11_10;
        Action read = () => G64Format.Read(withTable);
        read.Should().Throw<InvalidDataException>().WithMessage("*half-track 0 mixes speed zones 2 and 3*");

        // A table offset past the file, even one too big for an int, is a file cut short.
        BinaryPrimitives.WriteUInt32LittleEndian(withTable.AsSpan(12 + (image[9] * 4)), 0x9000_0000);
        Action far = () => G64Format.Read(withTable);
        far.Should().Throw<InvalidDataException>().WithMessage("*speed table for half-track 0 runs past its end*");
    }

    /// <summary>
    ///  A track the disk's G64 snapshot could not keep, part of a byte or longer than 65,535 bytes, is refused.
    /// </summary>
    [TestMethod]
    public void ATrackG64CannotKeepIsRefused()
    {
        CommodoreDisk disk = new();
        Action partial = () => disk.SetTrack(0, [0x80], 1, 3);
        partial.Should().Throw<ArgumentOutOfRangeException>();
        Action negative = () => disk.SetTrack(0, [0x80], -8, 3);
        negative.Should().Throw<ArgumentOutOfRangeException>();
        byte[] huge = new byte[CommodoreDisk.MaximumTrackBytes + 1];
        Action tooLong = () => disk.SetTrack(0, huge, huge.Length * 8, 3);
        tooLong.Should().Throw<ArgumentOutOfRangeException>();

        disk.SetTrack(0, huge, CommodoreDisk.MaximumTrackBytes * 8, 3);
        G64Format.Read(G64Format.Write(disk)).BitCount(0).Should().Be(CommodoreDisk.MaximumTrackBytes * 8);
    }

    /// <summary>
    ///  A G64 whose track table points past its end was cut short, and is refused rather than read without the track.
    /// </summary>
    [TestMethod]
    public void ACutShortG64IsRefused()
    {
        byte[] image = G64Format.Write(D64Format.Read(RandomImage()));
        int last = (int)BinaryPrimitives.ReadUInt32LittleEndian(image.AsSpan(12 + (68 * 4)));
        Action read = () => G64Format.Read(image.AsSpan(0, last + 1));
        read.Should().Throw<InvalidDataException>().WithMessage("*half-track 68 starts past its end*");
    }

    /// <summary>
    ///  A G64 with more half-tracks than a disk holds is refused rather than read without the rest.
    /// </summary>
    [TestMethod]
    public void TooManyHalfTracksAreRefused()
    {
        byte[] image = G64Format.Write(D64Format.Read(RandomImage()));
        image[9] = CommodoreDisk.Positions + 1;
        Action read = () => G64Format.Read(image);
        read.Should().Throw<InvalidDataException>().WithMessage("*85 half-tracks*");
    }

    /// <summary>
    ///  A DOS 1 sector whose data block has a damaged mark was written, so it is a loss, not a sector never written.
    /// </summary>
    [TestMethod]
    public void ADamagedDataMarkIsNotAnUnwrittenSector()
    {
        GcrBitWriter writer = new(GcrLayout.TrackBits(3));
        writer.Ones(20);
        writer.Bytes([0x08, (byte)(0 ^ 1 ^ 'B' ^ 'A'), 0, 1, (byte)'B', (byte)'A']);
        writer.Zeros(9);
        writer.Ones(20);
        writer.Byte(0x06);
        writer.Bytes(Enumerable.Repeat((byte)0x55, GcrLayout.SectorSize + 1).ToArray());
        writer.Zeros(12);

        bool[] found = GcrLayout.ReadTrack(
            writer.Buffer,
            GcrLayout.TrackBits(3),
            1,
            new byte[21 * GcrLayout.SectorSize],
            CommodoreDos.Dos1,
            out bool[] unwritten,
            out _,
            out _);

        found[0].Should().BeFalse();
        unwritten[0].Should().BeFalse("a block followed the header, though its mark is damaged");
    }

    /// <summary>
    ///  A data block cut short by the next sector's sync is bad, and the sector after it still reads.
    /// </summary>
    [TestMethod]
    public void ACutShortBlockLeavesTheNextSector()
    {
        GcrBitWriter writer = new(GcrLayout.TrackBits(3));
        byte[] good = [.. Enumerable.Range(0, GcrLayout.SectorSize).Select(value => (byte)(value * 7))];
        Header(writer, 0);
        writer.Ones(40);
        writer.Byte(0x07);
        writer.Bytes(good.AsSpan(0, 100));
        Header(writer, 1);
        Block(writer, good);
        writer.Zeros(12);

        byte[] sectors = new byte[21 * GcrLayout.SectorSize];
        bool[] found = GcrLayout.ReadTrack(writer.Buffer, GcrLayout.TrackBits(3), 1, sectors);
        found[0].Should().BeFalse("its block was cut short");
        found[1].Should().BeTrue("the sync inside the block starts sector 1's header");
        sectors.AsSpan(GcrLayout.SectorSize, GcrLayout.SectorSize).ToArray().Should().Equal(good);
    }

    /// <summary>
    ///  Two good copies of a sector that differ keep the first, and a sector image lists the sector as a loss.
    /// </summary>
    [TestMethod]
    public void DifferingGoodCopiesAreALoss()
    {
        GcrBitWriter writer = new(GcrLayout.TrackBits(3));
        byte[] first = new byte[GcrLayout.SectorSize];
        byte[] second = [.. Enumerable.Repeat((byte)0x5A, GcrLayout.SectorSize)];
        Header(writer, 0);
        Block(writer, first);
        Header(writer, 0);
        Block(writer, second);

        byte[] sectors = new byte[21 * GcrLayout.SectorSize];
        GcrLayout.ReadTrack(writer.Buffer, GcrLayout.TrackBits(3), 1, sectors, CommodoreDos.Dos2, out _, out _, out IReadOnlyList<int> differ);
        differ.Should().Equal(0);
        sectors.AsSpan(0, GcrLayout.SectorSize).ToArray().Should().Equal(first);

        CommodoreDisk disk = D64Format.Read(RandomImage());
        disk.SetTrack(0, writer.Buffer, GcrLayout.TrackBits(3), 3);
        new CommodoreDiskCodec("D64").Encode(disk.Snapshot()).Losses.Should()
            .Contain("track 1, sector 0, which holds two good copies that differ; the first is kept.");
    }

    // A track 1 header for a sector of disk BA, with its gap.
    private static void Header(GcrBitWriter writer, int sector)
    {
        writer.Ones(40);
        writer.Bytes([0x08, (byte)(sector ^ 1 ^ 'B' ^ 'A'), (byte)sector, 1, (byte)'B', (byte)'A']);
        writer.Zeros(9);
    }

    // A data block with its checksum and gap.
    private static void Block(GcrBitWriter writer, byte[] data)
    {
        writer.Ones(40);
        writer.Byte(0x07);
        writer.Bytes(data);
        byte sum = 0;
        foreach (byte value in data) { sum ^= value; }
        writer.Byte(sum);
        writer.Zeros(12);
    }

    private static byte[] RandomImage(int size = D64Format.Size)
    {
        byte[] image = new byte[size];
        new Random(1541).NextBytes(image);
        return image;
    }
}
