// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Media;
using System.Buffers.Binary;

namespace Retrocore.Tests;

/// <summary>
///  Original synthetic WOZ media tests; no copyrighted game or firmware data is included.
/// </summary>
[TestClass]
public class DiskMediaTests
{
    /// <summary>
    ///  Checks exact bit lengths, aliases, CRC and mutable/read-only round trips.
    /// </summary>
    [TestMethod]
    public void WozRoundTripPreservesBitsAliasesAndPermissions()
    {
        WozDisk original = WozDisk.CreateBlank();
        original.SetTrack(quarterTrack: 0, [0xA5, 0xC0], bitCount: 10);
        original.MapTrack(quarterTrack: 1, sourceQuarterTrack: 0);
        byte[] file = original.Export();
        WozDisk disk = WozDisk.Load(file, writable: true);
        DiskTrack track = disk.Track(0) ?? throw new InvalidOperationException();
        track.BitCount.Should().Be(10);
        disk.Track(1).Should().BeSameAs(track);
        disk.Track(2).Should().BeNull();
        disk.WriteBit(quarterTrack: 1, position: 0, transition: false);
        disk.Track(0)?.ReadBit(0).Should().BeFalse();
        disk.IsDirty.Should().BeTrue();
        disk.MarkSaved();
        disk.IsDirty.Should().BeFalse();
        WozDisk readOnly = WozDisk.Load(disk.Export());
        readOnly.IsReadOnly.Should().BeTrue();
        Action write = () => readOnly.WriteBit(quarterTrack: 0, position: 0, transition: true);
        write.Should().Throw<InvalidOperationException>();
    }

    /// <summary>
    ///  Checks chunk offsets are discovered by IDs and metadata survives export.
    /// </summary>
    [TestMethod]
    public void UnknownChunksAndNonCanonicalInfoOffsetsArePreserved()
    {
        WozDisk original = WozDisk.CreateBlank();
        original.SetTrack(quarterTrack: 0, [255], bitCount: 8);
        byte[] canonical = original.Export();
        byte[] file = new byte[canonical.Length + 12];
        canonical.AsSpan(0, 12).CopyTo(file);
        // Exchange INFO and TMAP without moving the absolute track blocks.
        canonical.AsSpan(80, 168).CopyTo(file.AsSpan(12));
        canonical.AsSpan(12, 68).CopyTo(file.AsSpan(180));
        canonical.AsSpan(248).CopyTo(file.AsSpan(248));
        "META"u8.CopyTo(file.AsSpan(canonical.Length));
        BinaryPrimitives.WriteUInt32LittleEndian(file.AsSpan(canonical.Length + 4), value: 4);
        "test"u8.CopyTo(file.AsSpan(canonical.Length + 8));
        BinaryPrimitives.WriteUInt32LittleEndian(file.AsSpan(8), WozCrc.Compute(file.AsSpan(12)));
        WozDisk parsed = WozDisk.Load(file);
        parsed.Track(0)?.BitCount.Should().Be(8);
        byte[] exported = parsed.Export();
        exported[^4..].Should().Equal("test"u8.ToArray());
    }

    /// <summary>
    ///  Checks CRC, missing chunks and malformed extents fail rather than producing blank media.
    /// </summary>
    [TestMethod]
    public void InvalidWozFilesFailExplicitly()
    {
        WozDisk disk = WozDisk.CreateBlank();
        disk.SetTrack(quarterTrack: 0, [255], bitCount: 8);
        byte[] file = disk.Export();
        file[^1] ^= 1;
        Action badCrc = () => WozDisk.Load(file);
        badCrc.Should().Throw<InvalidDataException>();
        Array.Clear(file, 8, 4);
        BinaryPrimitives.WriteUInt32LittleEndian(file.AsSpan(260), uint.MaxValue);
        Action badBits = () => WozDisk.Load(file);
        badBits.Should().Throw<InvalidDataException>();
        Action empty = () => WozDisk.Load(new byte[12]);
        empty.Should().Throw<InvalidDataException>();
    }

    /// <summary>
    ///  Checks WOZ1 track lengths are parsed from their records and can be upgraded.
    /// </summary>
    [TestMethod]
    public void Woz1LoadsWithoutAssumingWoz2Descriptors()
    {
        byte[] file = new byte[256 + 6656];
        "WOZ1"u8.CopyTo(file);
        file[4] = 255;
        file[5] = 10;
        file[6] = 13;
        file[7] = 10;
        "INFO"u8.CopyTo(file.AsSpan(12));
        BinaryPrimitives.WriteUInt32LittleEndian(file.AsSpan(16), value: 60);
        file[20] = 1;
        file[21] = 1;
        "TMAP"u8.CopyTo(file.AsSpan(80));
        BinaryPrimitives.WriteUInt32LittleEndian(file.AsSpan(84), value: 160);
        Array.Fill(file, (byte)255, 88, 160);
        file[88] = 0;
        "TRKS"u8.CopyTo(file.AsSpan(248));
        BinaryPrimitives.WriteUInt32LittleEndian(file.AsSpan(252), value: 6656);
        file[256] = 0xAA;
        BinaryPrimitives.WriteUInt16LittleEndian(file.AsSpan(256 + 6646), value: 1);
        BinaryPrimitives.WriteUInt16LittleEndian(file.AsSpan(256 + 6648), value: 7);
        WozDisk disk = WozDisk.Load(file);
        disk.Track(0)?.BitCount.Should().Be(7);
        WozDisk.Load(disk.Export()).Track(0)?.Bits.ToArray().Should().Equal(0xAA);
    }

    /// <summary>
    ///  Checks unformatted writable space acquires a track on a physical write.
    /// </summary>
    [TestMethod]
    public void WritingUnformattedMediaCreatesTrackStorage()
    {
        WozDisk disk = WozDisk.CreateBlank();
        disk.WriteBit(quarterTrack: 8, position: 13, transition: true);
        disk.Track(8)?.BitCount.Should().Be(51024);
        disk.Track(8)?.ReadBit(13).Should().BeTrue();
        WozDisk.Load(disk.Export()).Track(8)?.ReadBit(13).Should().BeTrue();
    }

    /// <summary>
    ///  Checks six-and-two differential coding and the 343-nibble shape.
    /// </summary>
    [TestMethod]
    public void SixAndTwoSectorEncodingHasTheCanonicalZeroPattern()
    {
        byte[] encoded = new byte[343];
        SectorDiskConverter.EncodeSector(new byte[256], encoded);
        encoded.Should().OnlyContain(value => value == 0x96);
        byte[] sector = Enumerable.Range(0, 256).Select(value => (byte)value).ToArray();
        SectorDiskConverter.EncodeSector(sector, encoded);
        byte[] values = new byte[342];
        byte previous = 0;
        byte[] gcr =
        [
            0x96,0x97,0x9A,0x9B,0x9D,0x9E,0x9F,0xA6,0xA7,0xAB,0xAC,0xAD,0xAE,0xAF,0xB2,0xB3,
            0xB4,0xB5,0xB6,0xB7,0xB9,0xBA,0xBB,0xBC,0xBD,0xBE,0xBF,0xCB,0xCD,0xCE,0xCF,0xD3,
            0xD6,0xD7,0xD9,0xDA,0xDB,0xDC,0xDD,0xDE,0xDF,0xE5,0xE6,0xE7,0xE9,0xEA,0xEB,0xEC,
            0xED,0xEE,0xEF,0xF2,0xF3,0xF4,0xF5,0xF6,0xF7,0xF9,0xFA,0xFB,0xFC,0xFD,0xFE,0xFF
        ];

        for (int index = 0; index < values.Length; index++)
        {
            previous ^= (byte)Array.IndexOf(gcr, encoded[index]);
            values[index] = previous;
        }

        Array.IndexOf(gcr, encoded[342]).Should().Be(previous);
        byte[] decoded = new byte[256];
        for (int index = 0; index < 256; index++)
        {
            int low = (values[index % 86] >> (index / 86 * 2)) & 3;
            decoded[index] = (byte)((values[86 + index] << 2) | ((low & 1) << 1) | ((low & 2) >> 1));
        }

        decoded.Should().Equal(sector);
    }

    /// <summary>
    ///  Checks full raw-media conversion generates address/data prologues, sync slip bits and aliases.
    /// </summary>
    /// <param name="proDos">The sector order.</param>
    [TestMethod]
    [DataRow(data: false)]
    [DataRow(data: true)]
    public void RawFloppyConversionProducesRealBitstreams(bool proDos)
    {
        WozDisk disk = SectorDiskConverter.Convert(new byte[35 * 4096], proDos);
        disk.IsReadOnly.Should().BeTrue();
        DiskTrack track = disk.Track(0) ?? throw new InvalidOperationException();
        track.BitCount.Should().Be(51024);
        disk.Track(1).Should().BeSameAs(track);
        disk.Track(2).Should().BeNull();
        // Sixteen ten-bit sync words precede the first address prologue.
        byte[] prologue = new byte[3];
        for (int value = 0; value < 3; value++)
        {
            for (int bit = 0; bit < 8; bit++)
            {
                prologue[value] = (byte)((prologue[value] << 1) | (track.ReadBit(160 + value * 8 + bit) ? 1 : 0));
            }
        }

        prologue.Should().Equal(0xD5, 0xAA, 0x96);
    }
}
