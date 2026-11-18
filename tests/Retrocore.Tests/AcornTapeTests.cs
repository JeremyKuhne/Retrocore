// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.IO.Compression;
using Retrocore.Media;
using Retrocore.Media.Acorn;

namespace Retrocore.Tests;

/// <summary>
///  Acorn tapes: UEF files, the cassette filing system's blocks and CRC, and <c>.inf</c> descriptions.
/// </summary>
[TestClass]
public class AcornTapeTests
{
    /// <summary>
    ///  The cassette filing system's CRC is CRC-16 with polynomial &amp;1021 from zero.
    /// </summary>
    [TestMethod]
    public void CrcIsTheMos()
    {
        AcornTapeBuilder.Crc("123456789"u8).Should().Be(0x31C3);
        AcornTapeBuilder.Crc([]).Should().Be(0);
    }

    /// <summary>
    ///  Chunks become tones: a byte is a start bit, eight bits and a stop bit; carrier is 2400 Hz; a gap is silence.
    /// </summary>
    [TestMethod]
    public void ChunksBecomeHalfCycles()
    {
        byte[] uef = Uef(
            (0x0110, [3, 0]),
            (0x0100, [0x01]),
            (0x0112, [10, 0]),
            (0x0117, [0x2C, 0x01]),
            (0x0100, [0x00]));

        AcornTape tape = UefFormat.Read(uef);
        List<int> expected = [1, 1, 1, 1, 1, 1];
        expected.AddRange([2, 2]);                                  // start bit
        expected.AddRange([1, 1, 1, 1]);                            // bit 0: a 1
        for (int bit = 1; bit < 8; bit++) { expected.AddRange([2, 2]); }
        expected.AddRange([1, 1, 1, 1]);                            // stop bit
        expected.Add(20);                                           // 10/2400 s
        for (int bit = 0; bit < 9; bit++) { expected.AddRange([2, 2, 2, 2, 2, 2, 2, 2]); }
        for (int half = 0; half < 16; half++) { expected.Add(1); }  // 300 baud stop bit: 8 cycles
        tape.HalfCycles.Should().Equal(expected);
    }

    /// <summary>
    ///  A gzip-compressed file reads as the plain one.
    /// </summary>
    [TestMethod]
    public void CompressedFilesRead()
    {
        byte[] uef = Uef((0x0110, [5, 0]), (0x0100, [0x2A]));
        using MemoryStream compressed = new();
        using (GZipStream gzip = new(compressed, CompressionLevel.Fastest, leaveOpen: true)) { gzip.Write(uef); }

        UefFormat.IsUef(compressed.ToArray()).Should().BeTrue();
        UefFormat.Read(compressed.ToArray()).HalfCycles.Should().Equal(UefFormat.Read(uef).HalfCycles);
        UefFormat.IsUef("not a tape"u8).Should().BeFalse();
    }

    /// <summary>
    ///  Writing and reading back gives the same half-cycles, at either rate, through odd lengths of carrier, explicit
    ///  bits, a lone half-cycle and silence.
    /// </summary>
    /// <param name="baud">The rate the files are recorded at.</param>
    [TestMethod]
    [DataRow(1200)]
    [DataRow(300)]
    public void WritingKeepsEveryHalfCycle(int baud)
    {
        AcornTape built = AcornTapeBuilder.Build(
            [new AcornTapeFile("FIRST", 0xFFFF1900, 0xFFFF1900, [.. Enumerable.Range(0, 300).Select(i => (byte)i)])],
            baud);

        List<int> halves = [.. built.HalfCycles];
        halves.AddRange([1, 1, 1]);             // a cycle and a half of carrier
        halves.AddRange([2, 2, 2, 2, 1, 1]);    // two 0s and half a 1
        halves.Add(7);                          // silence of 7/4800 s
        halves.Add(2);                          // a lone 1200 Hz half-cycle

        byte[] uef = UefFormat.Write(halves);
        UefFormat.Read(uef).HalfCycles.Should().Equal(halves);
    }

    /// <summary>
    ///  A built file's blocks hold its name, addresses, flags and CRCs as the MOS writes them.
    /// </summary>
    [TestMethod]
    public void BuiltBlocksAreTheMos()
    {
        AcornTape tape = AcornTapeBuilder.Build([new AcornTapeFile("AB", 0xFFFF0E00, 0xFFFF8023, [1, 2, 3], Locked: true)]);
        byte[] uef = UefFormat.Write(tape.HalfCycles);
        List<byte> bytes = DataBytes(uef);

        // The dummy byte, then the block.
        bytes[0].Should().Be(0xAA);
        byte[] header = [(byte)'A', (byte)'B', 0, 0x00, 0x0E, 0xFF, 0xFF, 0x23, 0x80, 0xFF, 0xFF, 0, 0, 3, 0, 0x81, 0, 0, 0, 0];
        bytes.Skip(1).Take(1 + header.Length).Should().Equal([0x2A, .. header]);
        ushort headerCrc = AcornTapeBuilder.Crc(header);
        bytes[22].Should().Be((byte)(headerCrc >> 8));
        bytes[23].Should().Be((byte)headerCrc);
        bytes.Skip(24).Take(3).Should().Equal([1, 2, 3]);
        ushort dataCrc = AcornTapeBuilder.Crc([1, 2, 3]);
        bytes.Skip(27).Take(2).Should().Equal([(byte)(dataCrc >> 8), (byte)dataCrc]);
    }

    /// <summary>
    ///  An <c>.inf</c> line gives the name, addresses and lock.
    /// </summary>
    [TestMethod]
    public void InfDescribesTheFile()
    {
        AcornTapeFile file = AcornTapeFile.FromInf("$.GAME   FFFF1900 FFFF8023 000300 L\n", [9]);
        file.Name.Should().Be("GAME");
        file.LoadAddress.Should().Be(0xFFFF1900);
        file.ExecutionAddress.Should().Be(0xFFFF8023);
        file.Locked.Should().BeTrue();
        file.Data.Should().Equal([9]);

        AcornTapeFile.FromInf("ELITE 1100 1100", []).Locked.Should().BeFalse();
        Action bad = () => AcornTapeFile.FromInf("NAME", []);
        bad.Should().Throw<InvalidDataException>();
    }

    /// <summary>
    ///  The tape's snapshot is its UEF file, through the codec, and its record tab is part of it.
    /// </summary>
    [TestMethod]
    public void SnapshotsEncodeAsUef()
    {
        AcornTape tape = new([1, 1, 2, 2]);
        long version = tape.Version;
        tape.IsWriteProtected = true;
        tape.Version.Should().NotBe(version);

        MediumSnapshot snapshot = tape.Snapshot();
        snapshot.Kind.Should().Be(AcornTape.SnapshotKind);
        EncodedImage image = new AcornTapeCodec().Encode(snapshot);
        image.IsLossless.Should().BeTrue();
        UefFormat.Read(image.Bytes).HalfCycles.Should().Equal([1, 1, 2, 2]);

        Action record = () => tape.Record(0, 1);
        record.Should().Throw<InvalidOperationException>();
    }

    // The bytes of a UEF's &0100 chunks, in order.
    private static List<byte> DataBytes(byte[] uef)
    {
        List<byte> bytes = [];
        int position = 12;
        while (position + 6 <= uef.Length)
        {
            int id = uef[position] | (uef[position + 1] << 8);
            int length = BitConverter.ToInt32(uef, position + 2);
            if (id == 0x0100) { bytes.AddRange(uef.AsSpan(position + 6, length).ToArray()); }
            position += 6 + length;
        }

        return bytes;
    }

    private static byte[] Uef(params (int Id, byte[] Data)[] chunks)
    {
        List<byte> file = [.. "UEF File!\0"u8.ToArray(), 10, 0];
        foreach ((int id, byte[] data) in chunks)
        {
            file.AddRange([(byte)id, (byte)(id >> 8)]);
            file.AddRange(BitConverter.GetBytes(data.Length));
            file.AddRange(data);
        }

        return [.. file];
    }
}
