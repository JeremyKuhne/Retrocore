// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Apple3;

namespace Retrocore.Tests;

/// <summary>
///  The Apple III's video modes on made-up memory, so no dump is needed: which bytes each mode and page shows, and
///  how.
/// </summary>
[TestClass]
public class Apple3VideoTests
{
    private const int White = 0xFFFFFF;
    private const int Black = 0x000000;

    // The switches, as $C050-$C057 set them: GR/TEXT, MIX, PG2, HIRES.
    private const byte Gr = 1;
    private const byte Mix = 2;
    private const byte Page2 = 4;
    private const byte Hires = 8;

    /// <summary>
    ///  40-column text draws each dot twice; codes $80-$FF are normal, $00-$7F inverse.
    /// </summary>
    /// <param name="page2">Whether page 2 shows.</param>
    [TestMethod]
    [DataRow(data: false)]
    [DataRow(data: true)]
    public void FortyColumnTextDoublesDotsAndInvertsLowCodes(bool page2)
    {
        (Apple3Machine machine, Apple3Bus bus) = Machine(page2 ? Page2 : (byte)0);
        machine.Video.CharacterRam[(0x41 * 8) + 0] = 0b0000_0001;   // 'A', row 0: the leftmost dot
        int text = page2 ? 0x800 : 0x400;
        System(bus, text) = 0xC1;
        System(bus, text + 1) = 0x41;

        int[] frame = Render(machine);
        frame[0].Should().Be(White);
        frame[1].Should().Be(White);
        frame[2].Should().Be(Black);
        frame[14].Should().Be(Black, "inverse lights the background, not the dot");
        frame[16].Should().Be(White);
    }

    /// <summary>
    ///  Color text takes its colors from the other page, foreground in the high nibble; page 2 swaps the pages.
    /// </summary>
    /// <param name="page2">Whether page 2 shows.</param>
    [TestMethod]
    [DataRow(data: false)]
    [DataRow(data: true)]
    public void ColorTextTakesColorsFromTheOtherPage(bool page2)
    {
        (Apple3Machine machine, Apple3Bus bus) = Machine((byte)(Gr | (page2 ? Page2 : 0)));
        machine.Video.CharacterRam[(0x41 * 8) + 0] = 0b0000_0001;
        System(bus, page2 ? 0x800 : 0x400) = 0xC1;
        System(bus, page2 ? 0x400 : 0x800) = 0x9C;               // orange on light green

        int[] frame = Render(machine);
        frame[0].Should().Be(0xFF6600);
        frame[2].Should().Be(0x11DD00);
    }

    /// <summary>
    ///  80-column text alternates the primary page and the secondary, a dot each; page 2 swaps them.
    /// </summary>
    /// <param name="page2">Whether page 2 shows.</param>
    [TestMethod]
    [DataRow(data: false)]
    [DataRow(data: true)]
    public void EightyColumnTextAlternatesPages(bool page2)
    {
        (Apple3Machine machine, Apple3Bus bus) = Machine((byte)(Mix | (page2 ? Page2 : 0)));
        machine.Video.CharacterRam[(0x41 * 8) + 0] = 0b0000_0001;
        machine.Video.CharacterRam[(0x42 * 8) + 0] = 0b0000_0010;
        System(bus, page2 ? 0x800 : 0x400) = 0xC1;
        System(bus, page2 ? 0x400 : 0x800) = 0xC2;

        int[] frame = Render(machine);
        frame[0].Should().Be(White);
        frame[1].Should().Be(Black);
        frame[7].Should().Be(Black);
        frame[8].Should().Be(White);
    }

    /// <summary>
    ///  280-dot black and white comes from bank 0, page 1 at $2000 and page 2 at $4000, each dot twice.
    /// </summary>
    /// <param name="page2">Whether page 2 shows.</param>
    [TestMethod]
    [DataRow(data: false)]
    [DataRow(data: true)]
    public void HiresIsInBankZero(bool page2)
    {
        (Apple3Machine machine, Apple3Bus bus) = Machine((byte)(Hires | (page2 ? Page2 : 0)));
        bus.Ram[page2 ? 0x2000 : 0x0000] = 0b0000_0011;
        bus.Ram[(page2 ? 0x2000 : 0x0000) + 0x400] = 0b0000_0001;  // line 1

        int[] frame = Render(machine);
        frame[0].Should().Be(White);
        frame[3].Should().Be(White);
        frame[4].Should().Be(Black);
        frame[560].Should().Be(White);
        frame[562].Should().Be(Black);
    }

    /// <summary>
    ///  280 dots with color take a color byte per 7 dots from the other page: page 1 dots at $2000 and colors at
    ///  $4000, page 2 the reverse, as the manual has it.
    /// </summary>
    /// <param name="page2">Whether page 2 shows.</param>
    [TestMethod]
    [DataRow(data: false)]
    [DataRow(data: true)]
    public void ColorHiresTakesColorsFromTheOtherPage(bool page2)
    {
        (Apple3Machine machine, Apple3Bus bus) = Machine((byte)(Hires | Gr | (page2 ? Page2 : 0)));
        bus.Ram[page2 ? 0x2000 : 0x0000] = 0b0000_0001;
        bus.Ram[page2 ? 0x0000 : 0x2000] = 0xD1;                    // yellow on deep red

        int[] frame = Render(machine);
        frame[0].Should().Be(0xFFFF00);
        frame[2].Should().Be(0xDD0033);
    }

    /// <summary>
    ///  560 dots: 7 from the primary byte, then 7 from the secondary; page 1 at $2000 and $4000, page 2 at $6000 and
    ///  $8000.
    /// </summary>
    /// <param name="page2">Whether page 2 shows.</param>
    [TestMethod]
    [DataRow(data: false)]
    [DataRow(data: true)]
    public void SuperHiresAlternatesPrimaryAndSecondary(bool page2)
    {
        (Apple3Machine machine, Apple3Bus bus) = Machine((byte)(Hires | Mix | (page2 ? Page2 : 0)));
        bus.Ram[page2 ? 0x4000 : 0x0000] = 0b0000_0001;
        bus.Ram[page2 ? 0x6000 : 0x2000] = 0b0000_0010;

        int[] frame = Render(machine);
        frame[0].Should().Be(White);
        frame[1].Should().Be(Black);
        frame[7].Should().Be(Black);
        frame[8].Should().Be(White);
    }

    /// <summary>
    ///  140 dots in 16 colors: four bytes, primary and secondary alternately, hold seven 4-bit dots, 4 wide each.
    /// </summary>
    [TestMethod]
    public void ColorHiresOf140PacksSevenDotsInFourBytes()
    {
        (Apple3Machine machine, Apple3Bus bus) = Machine(Hires | Mix | Gr);
        bus.Ram[0x0000] = 0x0F | 0x10;          // dot 0 = 15; dot 1's low three bits = 1
        bus.Ram[0x2000] = 0x00 | (0x01 << 1);   // dot 1's high bit 0; dot 2 = 1

        int[] frame = Render(machine);
        frame[0].Should().Be(White);
        frame[3].Should().Be(White);
        frame[4].Should().Be(0xDD0033, "dot 1 is color 1");
        frame[8].Should().Be(0xDD0033, "dot 2 is color 1");
        frame[12].Should().Be(Black);
    }

    /// <summary>
    ///  Smooth scrolling moves graphics lines within their group of eight.
    /// </summary>
    [TestMethod]
    public void SmoothScrollMovesLinesWithinTheirGroup()
    {
        (Apple3Machine machine, Apple3Bus bus) = Machine(Hires);
        bus.Ram[0x0400] = 0x01;                  // line 1
        bus.Write(0xC0D9, 0);                    // smooth scroll on
        bus.Write(0xC0E1, 0);                    // VA: offset 1

        int[] frame = Render(machine);
        frame[0].Should().Be(White, "line 0 shows line 1");
        frame[560].Should().Be(Black);
    }

    /// <summary>
    ///  With video off in the environment register, the screen is black.
    /// </summary>
    [TestMethod]
    public void VideoOffIsBlack()
    {
        (Apple3Machine machine, Apple3Bus bus) = Machine(Hires);
        bus.Ram[0] = 0xFF;
        bus.Write(0xFFDF, (byte)(bus.Environment & ~Apple3Bus.VideoEnable));
        bus.Write(0xFFD3, 0xFF);                 // port A's pins become outputs
        Render(machine).Should().AllSatisfy(pixel => pixel.Should().Be(Black));
    }

    /// <summary>
    ///  With $C0DB on, the character set loads as vertical blanking ends: a page 2 screen hole names the character,
    ///  the page 1 hole below it holds the row.
    /// </summary>
    [TestMethod]
    public void CharacterSetLoadsFromTheScreenHoles()
    {
        (Apple3Machine machine, Apple3Bus bus) = Machine(0);
        System(bus, 0x878) = 0x41;               // the first hole names 'A'
        System(bus, 0x478) = 0x5A;               // its row 0
        System(bus, 0x87C) = 0x42;               // the fifth names 'B'
        System(bus, 0x47C) = 0x3C;               // its row 1
        bus.Write(0xC0DB, 0);
        machine.Run(TimeSpan.FromSeconds(0.04));

        machine.Video.CharacterRam[0x41 * 8].Should().Be(0x5A);
        machine.Video.CharacterRam[(0x42 * 8) + 1].Should().Be(0x3C);
    }

    // A machine on a made-up ROM, with video on, the given switches and the VIAs' color text allowed.
    private static (Apple3Machine Machine, Apple3Bus Bus) Machine(byte switches)
    {
        byte[] rom = new byte[0x1000];
        rom[0] = 0x4C;                           // JMP $F000
        rom[2] = 0xF0;
        rom[0xFFC] = 0x00;
        rom[0xFFD] = 0xF0;
        Apple3Machine machine = new(new Apple3Roms(rom, new byte[256]));
        Apple3Bus bus = machine.Bus;
        bus.Ram.Clear();
        for (int i = 0; i < 4; i++)
        {
            bus.Write((ushort)(0xC050 + (2 * i) + ((switches >> i) & 1)), 0);
        }

        return (machine, bus);
    }

    private static ref byte System(Apple3Bus bus, int address) => ref bus.Ram[bus.Ram.Length - 0x8000 + address];

    private static int[] Render(Apple3Machine machine)
    {
        byte[] rgba = machine.Video.RenderBitmap();
        int[] pixels = new int[rgba.Length / 4];
        for (int i = 0; i < pixels.Length; i++)
        {
            pixels[i] = (rgba[i * 4] << 16) | (rgba[(i * 4) + 1] << 8) | rgba[(i * 4) + 2];
        }

        return pixels;
    }
}
