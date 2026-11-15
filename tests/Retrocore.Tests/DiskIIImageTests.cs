// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Media;
using System.Buffers.Binary;

namespace Retrocore.Tests;

/// <summary>
///  The Disk II's media as the persistence plan's first phase has it: the lock counted as a change, immutable
///  snapshots, the codecs and what each says it lost, the sector reader's 35 to 40 tracks, quarter tracks and
///  volumes, and a <c>.dsk</c> image's sector order found from its file system.
/// </summary>
[TestClass]
public sealed class DiskIIImageTests
{
    private const int TrackSize = 4096;

    /// <summary>
    ///  Changing the lock changes the version, and an exported image keeps the lock in its write-protection flag.
    /// </summary>
    [TestMethod]
    public void LockIsACountedChangeKeptInTheImage()
    {
        WozDisk disk = SectorDiskConverter.Convert(new byte[35 * TrackSize], proDosOrder: false);
        disk.IsWriteProtected.Should().BeTrue("a Disk II disk loads locked");
        long version = disk.Version;

        disk.IsWriteProtected = false;
        disk.Version.Should().NotBe(version);
        disk.IsDirty.Should().BeFalse("the lock is not a write");
        WozDisk.Load(disk.Export(), writable: true).IsWriteProtected.Should().BeFalse();

        long unlocked = disk.Version;
        disk.IsWriteProtected = false;
        disk.Version.Should().Be(unlocked, "setting the lock it has is no change");

        disk.IsWriteProtected = true;
        WozDisk.Load(disk.Export(), writable: true).IsWriteProtected.Should().BeTrue();
    }

    /// <summary>
    ///  A snapshot is the disk as it was: writes after it change the disk, not the snapshot.
    /// </summary>
    [TestMethod]
    public void SnapshotIsImmutable()
    {
        WozDisk disk = SectorDiskConverter.Convert(new byte[35 * TrackSize], proDosOrder: false).Writable();
        MediumSnapshot before = disk.Snapshot();
        byte[] image = before.Image.ToArray();
        before.Kind.Should().Be(WozDisk.SnapshotKind);
        before.Version.Should().Be(disk.Version);
        before.WriteProtected.Should().BeFalse();

        disk.WriteBit(quarterTrack: 0, position: 0, transition: false);
        disk.Version.Should().NotBe(before.Version);
        before.Image.ToArray().Should().Equal(image);
        disk.Snapshot().Image.ToArray().Should().NotEqual(image);
    }

    /// <summary>
    ///  The WOZ codec writes the snapshot as it is, and a WOZ1 image notes that it is now WOZ2 without calling that a
    ///  loss.
    /// </summary>
    [TestMethod]
    public void WozCodecWritesTheSnapshot()
    {
        WozDisk disk = SectorDiskConverter.Convert(new byte[35 * TrackSize], proDosOrder: false);
        MediumSnapshot snapshot = disk.Snapshot();
        EncodedImage woz = new WozCodec().Encode(snapshot);
        woz.Bytes.Should().Equal(snapshot.Image.ToArray());
        woz.IsLossless.Should().BeTrue();
        woz.Notes.Should().BeEmpty();

        EncodedImage upgraded = new WozCodec(sourceVersion: 1).Encode(snapshot);
        upgraded.IsLossless.Should().BeTrue();
        upgraded.Notes.Should().ContainSingle().Which.Should().Contain("WOZ1");

        Action wrong = () => new WozCodec().Encode(snapshot with { Kind = "2mg" });
        wrong.Should().Throw<ArgumentException>();
    }

    /// <summary>
    ///  A sector image of 35 to 40 tracks reads back whole, in either order, with nothing lost.
    /// </summary>
    /// <param name="tracks">The image's tracks.</param>
    /// <param name="proDosOrder">Its sector order.</param>
    [TestMethod]
    [DataRow(35, false)]
    [DataRow(35, true)]
    [DataRow(40, false)]
    [DataRow(40, true)]
    public void SectorImagesOf35To40TracksReadBack(int tracks, bool proDosOrder)
    {
        byte[] image = new byte[tracks * TrackSize];
        new Random(tracks).NextBytes(image);
        WozDisk disk = SectorDiskConverter.Convert(image, proDosOrder);

        SectorImage read = SectorDiskReader.Decode(disk, proDosOrder);
        read.Tracks.Should().Be(tracks);
        read.Losses.Should().BeEmpty();
        read.Bytes.Should().Equal(image);

        EncodedImage encoded = new SectorImageCodec("DSK", proDosOrder).Encode(disk.Snapshot());
        encoded.IsLossless.Should().BeTrue();
        encoded.Bytes.Should().Equal(image);
    }

    /// <summary>
    ///  A track that no longer reads as 16 sectors is a loss, left as zeros, and fails a plain read.
    /// </summary>
    [TestMethod]
    public void UnreadableTrackIsALoss()
    {
        byte[] image = new byte[35 * TrackSize];
        new Random(3).NextBytes(image);
        WozDisk disk = SectorDiskConverter.Convert(image, proDosOrder: false).Writable();
        disk.SetTrack(quarterTrack: 3 * 4, new byte[6378], bitCount: 51024);

        SectorImage read = SectorDiskReader.Decode(disk, proDosOrder: false);
        read.Unreadable.Should().ContainSingle().Which.Should().Contain("Track 3");
        read.Losses.Should().Contain(read.Unreadable[0]);
        read.Bytes.AsSpan(3 * TrackSize, TrackSize).ToArray().Should().OnlyContain(value => value == 0);
        read.Bytes.AsSpan(4 * TrackSize, TrackSize).ToArray().Should().Equal(image.AsSpan(4 * TrackSize, TrackSize).ToArray());

        Action plain = () => SectorDiskReader.Read(disk, proDosOrder: false);
        plain.Should().Throw<InvalidDataException>().WithMessage("Track 3*");
    }

    /// <summary>
    ///  A bad checksum loses only its own sector: the sectors after it on the track still read.
    /// </summary>
    [TestMethod]
    public void BadChecksumKeepsTheRestOfTheTrack()
    {
        byte[] image = new byte[35 * TrackSize];
        new Random(5).NextBytes(image);
        WozDisk disk = SectorDiskConverter.Convert(image, proDosOrder: false).Writable();

        // Physical sector 1's 100th data nibble becomes $AA, which no 6-and-2 value encodes. Each sector the converter
        // writes is 3,134 bits: its address field, 7 syncs, the data prologue, 343 nibbles, the epilogue and 16 syncs.
        byte[] bits = (disk.Track(5 * 4) ?? throw new InvalidOperationException()).Bits.ToArray();
        int position = 160 + 3134 + 112 + 70 + 24 + (100 * 8);
        for (int bit = 0; bit < 8; bit++)
        {
            int at = position + bit;
            bool one = (0xAA & (0x80 >> bit)) != 0;
            bits[at / 8] = (byte)(one ? bits[at / 8] | (0x80 >> (at % 8)) : bits[at / 8] & ~(0x80 >> (at % 8)));
        }

        disk.SetTrack(quarterTrack: 5 * 4, bits, bitCount: 51024);
        SectorImage read = SectorDiskReader.Decode(disk, proDosOrder: false);
        read.Unreadable.Should().ContainSingle().Which.Should().Be("Track 5 has a bad checksum in sector 1.");

        // DOS order puts physical sector 1 at logical 7; every other sector reads as it was.
        for (int physical = 0; physical < 16; physical++)
        {
            int logical = physical == 15 ? 15 : physical * 7 % 15;
            int offset = (5 * TrackSize) + (logical * 256);
            byte[] expected = physical == 1 ? new byte[256] : image.AsSpan(offset, 256).ToArray();
            read.Bytes.AsSpan(offset, 256).ToArray().Should().Equal(expected, $"physical sector {physical}");
        }
    }

    /// <summary>
    ///  Every sector in a whole revolution is read, so a second copy of a sector with other data, and the volume on
    ///  it, are losses even after all 16 sectors were found.
    /// </summary>
    [TestMethod]
    public void SectorsFoundTwiceWithOtherDataAreLosses()
    {
        byte[] first = new byte[35 * TrackSize];
        byte[] second = new byte[35 * TrackSize];
        new Random(1).NextBytes(first);
        new Random(2).NextBytes(second);
        WozDisk disk = SectorDiskConverter.Convert(first, proDosOrder: false).Writable();
        WozDisk other = SectorDiskConverter.Convert(second, proDosOrder: false, volume: 7);

        // Track 9 is the disk's own sixteen sectors followed by the other disk's sixteen, round one longer track.
        byte[] own = (disk.Track(9 * 4) ?? throw new InvalidOperationException()).Bits.ToArray();
        byte[] theirs = (other.Track(9 * 4) ?? throw new InvalidOperationException()).Bits.ToArray();
        disk.SetTrack(quarterTrack: 9 * 4, [.. own, .. theirs], bitCount: 2 * 51024);

        SectorImage read = SectorDiskReader.Decode(disk, proDosOrder: false);
        read.Unreadable.Should().BeEmpty();
        read.Losses.Should().Contain(loss => loss.Contains("more than one sector 0", StringComparison.Ordinal));
        read.Losses.Should().Contain(loss => loss.Contains("volume is 7", StringComparison.Ordinal));
        read.Bytes.AsSpan(9 * TrackSize, TrackSize).ToArray().Should().Equal(first.AsSpan(9 * TrackSize, TrackSize).ToArray(), "the first copy is kept");

        // The same sectors twice with the same data lose nothing.
        disk.SetTrack(quarterTrack: 9 * 4, [.. own, .. own], bitCount: 2 * 51024);
        SectorDiskReader.Decode(disk, proDosOrder: false).Losses.Should().BeEmpty();
    }

    /// <summary>
    ///  A track read from any starting bit gives all its sectors: the reader comes into step before the revolution it
    ///  reads, so a sector the first bits cut into is read whole.
    /// </summary>
    /// <param name="rotation">How many bits the track starts later.</param>
    [TestMethod]
    [DataRow(1)]
    [DataRow(154)]
    [DataRow(3000)]
    [DataRow(51023)]
    public void RotatedTrackReadsWhole(int rotation)
    {
        byte[] image = new byte[35 * TrackSize];
        new Random(rotation).NextBytes(image);
        WozDisk disk = SectorDiskConverter.Convert(image, proDosOrder: false).Writable();
        DiskTrack track = disk.Track(12 * 4) ?? throw new InvalidOperationException();
        byte[] rotated = new byte[track.Bits.Length];
        for (int bit = 0; bit < track.BitCount; bit++)
        {
            if (track.ReadBit((bit + rotation) % track.BitCount)) { rotated[bit / 8] |= (byte)(0x80 >> (bit % 8)); }
        }

        disk.SetTrack(quarterTrack: 12 * 4, rotated, track.BitCount);
        SectorImage read = SectorDiskReader.Decode(disk, proDosOrder: false);
        read.Losses.Should().BeEmpty();
        read.Bytes.Should().Equal(image);
    }

    /// <summary>
    ///  A whole address field that names another track is a loss, with its volume, though the track's own sixteen
    ///  sectors all read.
    /// </summary>
    [TestMethod]
    public void SectorOfAnotherTrackIsALoss()
    {
        WozDisk disk = SectorDiskConverter.Convert(new byte[35 * TrackSize], proDosOrder: false).Writable();
        WozDisk other = SectorDiskConverter.Convert(new byte[35 * TrackSize], proDosOrder: false, volume: 9);
        byte[] own = (disk.Track(9 * 4) ?? throw new InvalidOperationException()).Bits.ToArray();
        byte[] theirs = (other.Track(10 * 4) ?? throw new InvalidOperationException()).Bits.ToArray();
        disk.SetTrack(quarterTrack: 9 * 4, [.. own, .. theirs], bitCount: 2 * 51024);

        SectorImage read = SectorDiskReader.Decode(disk, proDosOrder: false);
        read.Unreadable.Should().BeEmpty();
        read.Losses.Should().Contain(loss => loss.Contains("calls itself track 10", StringComparison.Ordinal));
        read.Losses.Should().Contain(loss => loss.Contains("volume is 9", StringComparison.Ordinal));
    }

    /// <summary>
    ///  Data on a half track, which the whole tracks beside it do not cover, is a loss; the quarter tracks a sector
    ///  image's disk maps to its whole tracks are not.
    /// </summary>
    [TestMethod]
    public void QuarterTrackOfItsOwnIsALoss()
    {
        WozDisk disk = SectorDiskConverter.Convert(new byte[35 * TrackSize], proDosOrder: false).Writable();
        SectorDiskReader.Decode(disk, proDosOrder: false).Losses.Should().BeEmpty();

        disk.SetTrack(quarterTrack: (17 * 4) + 2, new byte[6378], bitCount: 51024);
        SectorDiskReader.Decode(disk, proDosOrder: false).Losses.Should().ContainSingle().Which.Should().Contain("Track 17.50");
    }

    /// <summary>
    ///  A quarter or half track mapped otherwise than a sector image's disk maps it is a loss, since reading the image
    ///  back would not put it there: a half track mapped to the track below, or a quarter track to the track above it
    ///  where the one below belongs.
    /// </summary>
    [TestMethod]
    public void QuarterTrackMappedElsewhereIsALoss()
    {
        WozDisk half = SectorDiskConverter.Convert(new byte[35 * TrackSize], proDosOrder: false).Writable();
        half.MapTrack(quarterTrack: 2, sourceQuarterTrack: 0);
        SectorDiskReader.Decode(half, proDosOrder: false).Losses.Should().ContainSingle().Which.Should().Contain("Track 0.50");

        WozDisk crossed = SectorDiskConverter.Convert(new byte[35 * TrackSize], proDosOrder: false).Writable();
        crossed.MapTrack(quarterTrack: 1, sourceQuarterTrack: 4);
        SectorDiskReader.Decode(crossed, proDosOrder: false).Losses.Should().ContainSingle().Which.Should().Contain("Track 0.25");
    }

    /// <summary>
    ///  An address field's volume counts though no data field follows it.
    /// </summary>
    [TestMethod]
    public void VolumeOfAnAddressWithoutDataIsALoss()
    {
        WozDisk disk = SectorDiskConverter.Convert(new byte[35 * TrackSize], proDosOrder: false).Writable();
        WozDisk other = SectorDiskConverter.Convert(new byte[35 * TrackSize], proDosOrder: false, volume: 7);

        // The other disk's syncs and first address field, then 80 $FF nibbles where its data field would start.
        byte[] own = (disk.Track(9 * 4) ?? throw new InvalidOperationException()).Bits.ToArray();
        byte[] address = (other.Track(9 * 4) ?? throw new InvalidOperationException()).Bits[..34].ToArray();
        byte[] filler = new byte[80];
        Array.Fill(filler, (byte)0xFF);
        disk.SetTrack(quarterTrack: 9 * 4, [.. own, .. address, .. filler], bitCount: (own.Length + 34 + 80) * 8);

        SectorImage read = SectorDiskReader.Decode(disk, proDosOrder: false);
        read.Unreadable.Should().BeEmpty();
        read.Losses.Should().ContainSingle().Which.Should().Contain("volume is 7");
    }

    /// <summary>
    ///  A volume other than 254 is a loss, since a sector image is read back as volume 254.
    /// </summary>
    [TestMethod]
    public void VolumeOtherThan254IsALoss()
    {
        WozDisk standard = SectorDiskConverter.Convert(new byte[35 * TrackSize], proDosOrder: false);
        SectorDiskReader.Decode(standard, proDosOrder: false).Losses.Should().BeEmpty();

        WozDisk other = SectorDiskConverter.Convert(new byte[35 * TrackSize], proDosOrder: false, volume: 7);
        SectorImage read = SectorDiskReader.Decode(other, proDosOrder: false);
        read.Losses.Should().ContainSingle().Which.Should().Contain("volume is 7");
        new SectorImageCodec("DSK", proDosOrder: false).Encode(other.Snapshot()).IsLossless.Should().BeFalse();
    }

    /// <summary>
    ///  A DOS 3.3 disk's catalog reads whole only in DOS's order, so a <c>.dsk</c> in either order is found to be in
    ///  the one it is in, and saves back to the same bytes.
    /// </summary>
    [TestMethod]
    public void DosDiskOrderIsFound()
    {
        byte[] dosOrder = DosDisk.Create(new byte[3 * 16 * 256], []);
        DiskIIImage.IsProDosOrder(dosOrder).Should().BeFalse();
        byte[] proDosOrder = Reorder(dosOrder, toProDos: true);
        DiskIIImage.IsProDosOrder(proDosOrder).Should().BeTrue();

        SavesBackTheSame(dosOrder, expectProDos: false);
        SavesBackTheSame(proDosOrder, expectProDos: true);
    }

    /// <summary>
    ///  A ProDOS volume's directory reads whole only in ProDOS's order, so a <c>.dsk</c> of one in either order is
    ///  found to be in the one it is in.
    /// </summary>
    [TestMethod]
    public void ProDosVolumeOrderIsFound()
    {
        byte[] proDosOrder = new byte[35 * TrackSize];
        for (int block = 2; block <= 5; block++)
        {
            Span<byte> data = proDosOrder.AsSpan(block * 512, 512);
            BinaryPrimitives.WriteUInt16LittleEndian(data, (ushort)(block == 2 ? 0 : block - 1));
            BinaryPrimitives.WriteUInt16LittleEndian(data[2..], (ushort)(block == 5 ? 0 : block + 1));
        }

        Span<byte> key = proDosOrder.AsSpan(2 * 512, 512);
        key[4] = 0xF5;
        "BLANK"u8.CopyTo(key[5..]);
        key[0x23] = 0x27;
        key[0x24] = 0x0D;

        DiskIIImage.IsProDosOrder(proDosOrder).Should().BeTrue();
        byte[] dosOrder = Reorder(proDosOrder, toProDos: false);
        DiskIIImage.IsProDosOrder(dosOrder).Should().BeFalse();

        SavesBackTheSame(proDosOrder, expectProDos: true);
        SavesBackTheSame(dosOrder, expectProDos: false);
    }

    /// <summary>
    ///  An Apple Pascal volume's header reads whole only in the order the image is in.
    /// </summary>
    [TestMethod]
    public void PascalVolumeOrderIsFound()
    {
        byte[] proDosOrder = new byte[35 * TrackSize];
        Span<byte> header = proDosOrder.AsSpan(2 * 512, 26);
        BinaryPrimitives.WriteUInt16LittleEndian(header[2..], 6);
        header[6] = 5;
        "APPLE"u8.CopyTo(header[7..]);
        BinaryPrimitives.WriteUInt16LittleEndian(header[14..], 280);

        DiskIIImage.IsProDosOrder(proDosOrder).Should().BeTrue();
        DiskIIImage.IsProDosOrder(Reorder(proDosOrder, toProDos: false)).Should().BeFalse();
    }

    /// <summary>
    ///  An image with no file system it knows is taken as DOS order, as most <c>.dsk</c> images are.
    /// </summary>
    [TestMethod]
    public void UnknownImageIsDosOrder()
    {
        byte[] image = new byte[35 * TrackSize];
        new Random(35).NextBytes(image);
        DiskIIImage.IsProDosOrder(image).Should().BeFalse();
        DiskIIImage.Load(image, "dsk").Codec.Should().BeOfType<SectorImageCodec>().Which.ProDosOrder.Should().BeFalse();
    }

    /// <summary>
    ///  Each extension loads with the codec that writes it back: WOZ, sector images in their orders, and none for a
    ///  13-sector image, which is read only. A new image's codec follows its extension.
    /// </summary>
    [TestMethod]
    public void ExtensionsChooseTheirCodecs()
    {
        byte[] sectors = new byte[35 * TrackSize];
        DiskIIImage.Load(sectors, ".PO").Codec.Should().BeOfType<SectorImageCodec>().Which.ProDosOrder.Should().BeTrue();
        DiskIIImage.Load(sectors, "do").Codec?.Format.Should().Be("DO");
        DiskIIImage.Load(sectors, "").Codec?.Format.Should().Be("DSK");
        DiskIIImage.Load(new byte[35 * 13 * 256], "d13").Codec.Should().BeNull();

        WozDisk woz = DiskIIImage.Load(sectors, "dsk").Disk;
        DiskIIImage.Load(woz.Export(), "woz").Codec.Should().BeOfType<WozCodec>();
        DiskIIImage.Load(woz.Export(), "woz").Disk.IsWriteProtected.Should().BeTrue("a Disk II disk loads locked");

        DiskIIImage.CodecFor("po").Should().BeOfType<SectorImageCodec>().Which.ProDosOrder.Should().BeTrue();
        DiskIIImage.CodecFor(".dsk").Should().BeOfType<SectorImageCodec>().Which.ProDosOrder.Should().BeFalse();
        DiskIIImage.CodecFor("WOZ").Should().BeOfType<WozCodec>();
        DiskIIImage.CodecFor("d13").Should().BeNull();
        DiskIIImage.CodecFor("2mg").Should().BeNull();
    }

    // Loads an image as a .dsk, checks the order it was found in, and saves it back unchanged.
    private static void SavesBackTheSame(byte[] image, bool expectProDos)
    {
        LoadedDisk loaded = DiskIIImage.Load(image, "dsk");
        SectorImageCodec codec = loaded.Codec.Should().BeOfType<SectorImageCodec>().Subject;
        codec.ProDosOrder.Should().Be(expectProDos);
        EncodedImage saved = codec.Encode(loaded.Disk.Snapshot());
        saved.IsLossless.Should().BeTrue();
        saved.Bytes.Should().Equal(image);
    }

    // The same disk as an image in the other sector order.
    private static byte[] Reorder(byte[] image, bool toProDos) =>
        SectorDiskReader.Read(SectorDiskConverter.Convert(image, proDosOrder: !toProDos), toProDos);
}
