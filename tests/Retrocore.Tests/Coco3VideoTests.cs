// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Runtime.InteropServices;
using Retrocore.Machines.Coco;

namespace Retrocore.Tests;

/// <summary>
///  The CoCo 3's GIME video on the RGB monitor: its text and graphics modes through the palette.
/// </summary>
[TestClass]
public class Coco3VideoTests
{
    private const int Width = 704;
    private const int BorderX = 32;

    /// <summary>
    ///  WIDTH 40 shows characters in two palette colors, sixteen dots wide each.
    /// </summary>
    [TestMethod]
    public void FortyColumnTextUsesThePalette()
    {
        CocoMachine machine = Boot();
        CocoMachineTests.Type(machine, "width 40\r");
        CocoGime gime = machine.Bus.Gime ?? throw new AssertFailedException("A CoCo 3 has a GIME.");
        uint[] frame = Render(machine);
        int top = 12 + ((225 - machine.Bus.Coco3Video.ActiveLines) / 2);

        // The first row's first cell holds O of OK: its colors are the attribute's foreground and background.
        HashSet<uint> cell = [];
        for (int y = 0; y < 8; y++)
        {
            for (int x = 0; x < 16; x++) { cell.Add(frame[((top + y) * Width) + BorderX + x]); }
        }

        cell.Should().HaveCount(2);
        HashSet<uint> palette = [.. Enumerable.Range(0, 16).Select(index => Rgb(gime.Palette(index)))];
        cell.Should().BeSubsetOf(palette);
    }

    /// <summary>
    ///  HSCREEN 2 shows 320 x 192 graphics in sixteen colors; HCLS fills with a palette entry.
    /// </summary>
    [TestMethod]
    public void SixteenColorGraphicsFillsWithAPaletteEntry()
    {
        CocoMachine machine = Boot();
        CocoMachineTests.Type(machine, "10 hscreen 2:palette 5,36:hcls 5\r20 goto 20\rrun\r");
        machine.Run(2 * (ulong)CocoTiming.ClockHertz);
        CocoGime gime = machine.Bus.Gime ?? throw new AssertFailedException("A CoCo 3 has a GIME.");
        machine.Bus.Coco3Video.IsText.Should().BeFalse();
        uint[] frame = Render(machine);
        int top = 12 + ((225 - machine.Bus.Coco3Video.ActiveLines) / 2);
        frame[((top + 100) * Width) + BorderX + 320].Should().Be(Rgb(36));
        gime.Palette(5).Should().Be(36);
    }

    private static CocoMachine Boot()
    {
        string directory = Environment.GetEnvironmentVariable("RETROCORE_COCO_ROMS")
            ?? Path.Join(ExternalTestData.Root, "coco-roms", "extract");

        if (!Directory.Exists(directory))
        {
            Assert.Inconclusive("Set RETROCORE_COCO_ROMS to the Color Computer ROM dumps.");
        }

        CocoMachine machine = new(
            new() { Model = CocoModel.Coco3, RgbMonitor = true },
            CocoRoms.Load(CocoModel.Coco3, directory));

        machine.Run(3 * (ulong)CocoTiming.ClockHertz);
        return machine;
    }

    private static uint[] Render(CocoMachine machine)
    {
        Coco3Video video = machine.Bus.Coco3Video;
        byte[] pixels = new byte[video.Width * video.Height * 4];
        video.Render(pixels, scanned: true);
        return MemoryMarshal.Cast<byte, uint>(pixels).ToArray();
    }

    // The RGB monitor's color for a 6-bit value: bits 5 and 2 red, 4 and 1 green, 3 and 0 blue.
    private static uint Rgb(byte color)
    {
        int red = (((color >> 4) & 2) | ((color >> 2) & 1)) * 0x55;
        int green = (((color >> 3) & 2) | ((color >> 1) & 1)) * 0x55;
        int blue = (((color >> 2) & 2) | (color & 1)) * 0x55;
        return 0xFF000000 | (uint)(blue << 16) | (uint)(green << 8) | (uint)red;
    }
}
