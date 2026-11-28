// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Media.Trs80;

namespace Retrocore.Tests;

/// <summary>
///  A Level II <c>SYSTEM</c> tape the SDK writes reads back block by block, as the ROM's loader reads it, and reads as
///  a <c>SYSTEM</c> tape.
/// </summary>
[TestClass]
public class SystemTapeTests
{
    /// <summary>
    ///  The tape is the leader, <c>$A5</c>, <c>$55</c> and the name padded to six, then blocks of 256 bytes, each with
    ///  its count (0 for 256), its address low byte first and its checksum, and the entry block.
    /// </summary>
    [TestMethod]
    public void WritesBlocksOfTheBytes()
    {
        byte[] program = [.. Enumerable.Range(0, 300).Select(index => (byte)(index * 3))];
        byte[] tape = SystemTape.Write("GAME", 0x43F0, program, 0x4400);

        tape.AsSpan(0, 255).ToArray().Should().OnlyContain(value => value == 0);
        tape.AsSpan(255, 8).ToArray().Should().Equal([0xA5, 0x55, .. "GAME  "u8]);
        tape.AsSpan(263, 4).ToArray().Should().Equal(0x3C, 0x00, 0xF0, 0x43);
        int sum = 0xF0 + 0x43 + program.Take(256).Sum(value => value);
        tape[267 + 256].Should().Be((byte)sum);
        tape.AsSpan(268 + 256, 4).ToArray().Should().Equal(0x3C, 44, 0xF0, 0x44);
        tape[^3..].Should().Equal(0x78, 0x00, 0x44);
        CassetteFormat.Detect(tape).Should().Be(CassetteContents.Level2System);

        (string name, IReadOnlyList<(int Address, byte[] Bytes)> blocks, int entry) = SystemTape.Read(tape);
        (name, entry).Should().Be(("GAME", 0x4400));
        blocks.Select(block => block.Address).Should().Equal(0x43F0, 0x44F0);
        blocks.SelectMany(block => block.Bytes).Should().Equal(program);
    }

    /// <summary>
    ///  A name is what <c>SYSTEM</c>'s prompt takes, 1 to 6 capitals and digits from a letter, and a tape holds at least
    ///  a byte, within the address space; a bad checksum fails the read.
    /// </summary>
    [TestMethod]
    public void RefusesWhatTheLoaderCannotTake()
    {
        Action write = () => SystemTape.Write("SEVENCH", 0x4300, [0], 0x4300);
        write.Should().Throw<ArgumentException>().WithMessage("*'SEVENCH' is not*");
        write = () => SystemTape.Write("1GAME", 0x4300, [0], 0x4300);
        write.Should().Throw<ArgumentException>();
        write = () => SystemTape.Write("game", 0x4300, [0], 0x4300);
        write.Should().Throw<ArgumentException>();
        write = () => SystemTape.Write("GAME", 0x4300, [], 0x4300);
        write.Should().Throw<ArgumentException>();
        write = () => SystemTape.Write("GAME", 0xFFFF, [0, 1], 0x4300);
        write.Should().Throw<ArgumentException>();

        byte[] tape = SystemTape.Write("GAME", 0x4300, [1, 2, 3], 0x4300);
        tape[^4]++;
        Action read = () => SystemTape.Read(tape);
        read.Should().Throw<InvalidDataException>().WithMessage("The block at $4300 has a bad checksum.");
    }
}
