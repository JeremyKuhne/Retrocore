// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Chips;
using Retrocore.Machines.Commodore.Vic20;

namespace Retrocore.Tests;

/// <summary>
///  The VIC's registers and what it reads, on a VIC-20 with blank ROMs, so no dumps are needed.
/// </summary>
[TestClass]
public class Vic6560Tests
{
    /// <summary>
    ///  The light pen's registers read 0 whatever is written to them, since no pen is connected; the others written
    ///  read back.
    /// </summary>
    [TestMethod]
    public void LightPenRegistersReadZero()
    {
        Vic20Machine machine = Blank();
        machine.Bus.Write(0x9006, 0x55);
        machine.Bus.Write(0x9007, 0xAA);
        machine.Bus.Write(0x900E, 0x3C);
        machine.Bus.Peek(0x9006).Should().Be(0);
        machine.Bus.Peek(0x9007).Should().Be(0);
        machine.Bus.Peek(0x900E).Should().Be(0x3C);
    }

    /// <summary>
    ///  The VIC sees colour RAM at its <c>$1400-$17FF</c>, the processor's <c>$9400</c>: four bits under the high
    ///  nybble of its last fetch. Its I/O around it answers nothing, so reads as that fetch.
    /// </summary>
    [TestMethod]
    public void VicSeesColourRam()
    {
        byte[] characters = new byte[0x1000];
        characters[0x1C] = 0xC3;
        Vic20Machine machine = new(new Vic20Roms(new byte[0x2000], new byte[0x2000], characters));
        machine.Bus.Write(0x9400, 0x05);
        machine.Bus.Write(0x97FF, 0x0A);
        IVicMemory vic = machine.Bus;

        // Outside its window the chip's last fetch is its idle read of $001C, here the character ROM's $C3.
        machine.Vic.LastFetch.Should().Be(0xC3);
        vic.FetchVideo(0x1400).Should().Be(0xC5);
        vic.FetchVideo(0x17FF).Should().Be(0xCA);
        vic.FetchVideo(0x1000).Should().Be(0xC3);
        vic.FetchVideo(0x1800).Should().Be(0xC3);
    }

    /// <summary>
    ///  The window's rows are taken at the frame's start and its columns at each line's, as MAME's 6560 takes them:
    ///  rows written mid-frame show from the next frame, and columns written mid-line from the next line.
    /// </summary>
    [TestMethod]
    public void WindowSizeIsTakenAtTheFrameAndLine()
    {
        const byte Border = 2;
        const byte Background = 6;
        Vic20Machine machine = Blank();
        Vic6560 chip = machine.Vic;

        // A 22-column window from cycle 10 and line 40, with no rows, on NTSC; blank characters show the background.
        chip.Write(0, 10);
        chip.Write(1, 20);
        chip.Write(2, 22);
        chip.Write(3, 0);
        chip.Write(15, (Background << 4) | 8 | Border);

        // Rows written at line 100 leave this frame all border, and open the window in the next.
        RunTo(chip, 100, 0);
        chip.Write(3, 23 << 1);
        RunTo(chip, 160, 0);
        Dot(chip, 20, 150).Should().Be(Border, "the frame took no rows");
        RunTo(chip, 0, 0);
        RunTo(chip, 150, 5);

        // Two columns written at line 150, after the line took its columns, narrow the window from line 151.
        chip.Write(2, 2);
        RunTo(chip, 152, 0);
        Dot(chip, 20, 150).Should().Be(Background, "line 150 took 22 columns");
        Dot(chip, 20, 151).Should().Be(Border, "line 151 took 2");
    }

    // Ticks the chip to a line and cycle.
    private static void RunTo(Vic6560 chip, int line, int cycle)
    {
        do { chip.Tick(); } while (chip.Line != line || chip.Cycle != cycle);
    }

    // The colour drawn at a cycle's first dot on a line, NTSC's frame starting at cycle 2 and line 12.
    private static int Dot(Vic6560 chip, int cycle, int line) => chip.ScannedColour((cycle * 4) - 8, line - 12);

    private static Vic20Machine Blank() => new(new Vic20Roms(new byte[0x2000], new byte[0x2000], new byte[0x1000]));
}
