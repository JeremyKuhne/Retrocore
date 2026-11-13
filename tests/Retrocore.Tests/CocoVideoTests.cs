// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Runtime.InteropServices;
using Retrocore.Machines.Coco;

namespace Retrocore.Tests;

/// <summary>
///  The CoCo 1 and 2's VDG output: text, semigraphics and graphics as BASIC sets them up.
/// </summary>
[TestClass]
public class CocoVideoTests
{
    private const uint Green = 0xFF00D230;
    private const uint DarkGreen = 0xFF007C00;
    private const uint Blue = 0xFFB43A4C;
    private const uint Buff = 0xFFADC8BF;
    private const uint Red = 0xFF36329A;
    private const int BorderX = 32;
    private const int BorderY = 24;

    /// <summary>
    ///  After boot the screen is dark green text on bright green (the VDG's inverse video, which Color BASIC uses for
    ///  normal text), with the black border of the text modes.
    /// </summary>
    [TestMethod]
    public void TextIsGreenOnDarkGreen()
    {
        CocoMachine machine = CocoMachineTests.Create(CocoModel.Coco2, 12, 11, 64);
        machine.Run(2 * (ulong)CocoTiming.ClockHertz);
        uint[] frame = Render(machine);

        // Row 0's first cell holds E of EXTENDED: dots in rows 3-9, bright background in rows 0-2.
        Cell(frame, 0, 0).Should().Contain(Green).And.Contain(DarkGreen);
        Pixel(frame, 0, 0).Should().Be(Green);
        Pixel(frame, 2, 3).Should().Be(DarkGreen);
        frame[0].Should().Be(0xFF000000);
        machine.Bus.Video.IsText.Should().BeTrue();
    }

    /// <summary>
    ///  CLS 3 fills the screen with semigraphics 4 blocks in blue, the third color.
    /// </summary>
    [TestMethod]
    public void ClearScreenFillsSemigraphicsBlocks()
    {
        CocoMachine machine = CocoMachineTests.Create(CocoModel.Coco2, 12, 11, 64);
        machine.Run(2 * (ulong)CocoTiming.ClockHertz);
        CocoMachineTests.Type(machine, "cls 3\r");
        uint[] frame = Render(machine);
        Pixel(frame, 128, 150).Should().Be(Blue);
    }

    /// <summary>
    ///  PMODE 4 shows two-color 256 x 192 graphics: buff on black with color set 1, and a buff border.
    /// </summary>
    [TestMethod]
    public void HighResolutionGraphicsShowsBuff()
    {
        CocoMachine machine = CocoMachineTests.Create(CocoModel.Coco2, 12, 11, 64);
        machine.Run(2 * (ulong)CocoTiming.ClockHertz);
        CocoMachineTests.Type(machine, "10 pmode 4,1:pcls:screen 1,1:line(0,0)-(127,191),pset,bf\r20 goto 20\rrun\r");

        // BASIC fills the box a byte at a time at 0.89 MHz.
        machine.Run(5 * (ulong)CocoTiming.ClockHertz);
        uint[] frame = Render(machine);
        machine.Bus.Video.IsText.Should().BeFalse(CocoMachineTests.Screen(machine));
        Pixel(frame, 10, 100).Should().Be(Buff);
        Pixel(frame, 200, 100).Should().NotBe(Buff);
        frame[0].Should().Be(Buff);
    }

    /// <summary>
    ///  In PMODE 4 with color set 1, alternating dots show as an artifact color, red or blue by the phase.
    /// </summary>
    [TestMethod]
    public void HighResolutionGraphicsShowsArtifactColors()
    {
        CocoMachine machine = CocoMachineTests.Create(CocoModel.Coco2, 12, 11, 64);
        machine.Run(2 * (ulong)CocoTiming.ClockHertz);
        CocoMachineTests.Type(machine, "10 pmode 4,1:pcls:screen 1,1\r20 goto 20\rrun\r");
        int start = machine.Bus.Sam.DisplayOffset;
        machine.Bus.Ram.Slice(start, 32).Fill(0xAA);
        machine.Bus.Ram.Slice(start + 32, 32).Fill(0x55);
        uint[] frame = Render(machine, scanned: false);
        Pixel(frame, 0, 0).Should().Be(0xFFF05C26);
        Pixel(frame, 1, 0).Should().Be(0xFFF05C26);
        Pixel(frame, 0, 1).Should().Be(0xFF166AE6);
    }

    /// <summary>
    ///  PMODE 3 shows four-color graphics: PCLS 4 fills with red, color set 0's fourth color.
    /// </summary>
    [TestMethod]
    public void ColorGraphicsShowsTheColorSet()
    {
        CocoMachine machine = CocoMachineTests.Create(CocoModel.Coco2, 12, 11, 64);
        machine.Run(2 * (ulong)CocoTiming.ClockHertz);
        CocoMachineTests.Type(machine, "10 pmode 3,1:pcls 4:screen 1,0\r20 goto 20\rrun\r");
        uint[] frame = Render(machine);
        Pixel(frame, 100, 100).Should().Be(Red);
        frame[0].Should().Be(Green);
    }

    /// <summary>
    ///  The MC6847T1 shows codes 0-31 as lowercase when GM0 is set, as Color BASIC 1.3 selects.
    /// </summary>
    [TestMethod]
    public void TheT1ShowsLowercase()
    {
        CocoMachine machine = CocoMachineTests.Create(CocoModel.Coco2, 13, 11, 64);
        machine.Run(2 * (ulong)CocoTiming.ClockHertz);

        // Put a (code 1, not inverse) in the top-left cell with GM0 set, then compare with A.
        machine.Bus.Ram[0x0400] = 0x01;
        machine.Bus.Pia1.Write(3, (byte)(machine.Bus.Pia1.ControlB & ~0x04));
        machine.Bus.Pia1.Write(2, 0xF8);
        machine.Bus.Pia1.Write(3, (byte)(machine.Bus.Pia1.ControlB | 0x04));
        machine.Bus.Pia1.Write(2, 0x10);
        uint[] lowercase = Render(machine, scanned: false);
        machine.Bus.Pia1.Write(2, 0x00);
        uint[] uppercase = Render(machine, scanned: false);
        Cell(lowercase, 0, 0).Should().NotEqual(Cell(uppercase, 0, 0));
    }

    private static uint[] Render(CocoMachine machine, bool scanned = true)
    {
        CocoVideo video = machine.Bus.Video;
        byte[] pixels = new byte[video.Width * video.Height * 4];
        video.Render(pixels, scanned);
        return MemoryMarshal.Cast<byte, uint>(pixels).ToArray();
    }

    private static uint Pixel(uint[] frame, int x, int y) => frame[((y + BorderY) * 320) + x + BorderX];

    private static uint[] Cell(uint[] frame, int column, int row) =>
        [.. Enumerable.Range(0, 12 * 8).Select(index => Pixel(frame, (column * 8) + (index % 8), (row * 12) + (index / 8)))];
}
