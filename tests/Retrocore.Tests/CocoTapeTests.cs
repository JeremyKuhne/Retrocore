// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Media.Trs80;

namespace Retrocore.Tests;

/// <summary>
///  A Color Computer cassette of a machine-language file the SDK writes reads back block by block, each with the
///  checksum Color BASIC checks.
/// </summary>
[TestClass]
public class CocoTapeTests
{
    /// <summary>
    ///  The tape is a leader, the name block (the name padded to eight, type 2, the ASCII and gap flags 0, then the exec
    ///  and load addresses, high bytes first), a leader, the data in blocks of 255, and the end block; each block is
    ///  <c>$55</c>, <c>$3C</c>, its type and length, its data, its checksum and <c>$55</c>.
    /// </summary>
    [TestMethod]
    public void WritesTheNameBlockThenTheData()
    {
        byte[] program = [.. Enumerable.Range(0, 300).Select(index => (byte)(index * 5))];
        byte[] tape = CocoTape.Write("GAME", 0x1F00, program, 0x1F0B);

        tape.AsSpan(0, 128).ToArray().Should().OnlyContain(value => value == 0x55);
        byte[] header = [.. "GAME    "u8, 2, 0, 0, 0x1F, 0x0B, 0x1F, 0x00];
        tape.AsSpan(128, 4).ToArray().Should().Equal(0x55, 0x3C, 0x00, 15);
        tape.AsSpan(132, 15).ToArray().Should().Equal(header);
        tape[147].Should().Be((byte)(15 + header.Sum(value => value)));
        tape[148].Should().Be(0x55);
        tape.AsSpan(149, 128).ToArray().Should().OnlyContain(value => value == 0x55);
        tape.AsSpan(277, 4).ToArray().Should().Equal(0x55, 0x3C, 0x01, 255);
        tape[^6..].Should().Equal(0x55, 0x3C, 0xFF, 0x00, 0xFF, 0x55);

        (string name, int address, byte[] bytes, int entry) = CocoTape.Read(tape);
        (name, address, entry).Should().Be(("GAME", 0x1F00, 0x1F0B));
        bytes.Should().Equal(program);
    }

    /// <summary>
    ///  A name is what CLOADM's quotes take, 1 to 8 capitals and digits from a letter, and a tape holds at least a byte
    ///  within the address space; a bad checksum fails the read.
    /// </summary>
    [TestMethod]
    public void RefusesWhatCloadmCannotTake()
    {
        Action write = () => CocoTape.Write("NINECHARS", 0x1F00, [0], 0x1F00);
        write.Should().Throw<ArgumentException>().WithMessage("*'NINECHARS' is not*");
        write = () => CocoTape.Write("game", 0x1F00, [0], 0x1F00);
        write.Should().Throw<ArgumentException>();
        write = () => CocoTape.Write("GAME", 0x1F00, [], 0x1F00);
        write.Should().Throw<ArgumentException>();
        write = () => CocoTape.Write("GAME", 0xFFFF, [0, 1], 0x1F00);
        write.Should().Throw<ArgumentException>();

        byte[] tape = CocoTape.Write("GAME", 0x1F00, [1, 2, 3], 0x1F00);
        tape[^8]++;
        Action read = () => CocoTape.Read(tape);
        read.Should().Throw<InvalidDataException>().WithMessage("A block of type $01 has a bad checksum.");
    }
}
