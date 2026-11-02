// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Apple2;

namespace Retrocore.Tests;

/// <summary>
///  Checks scanner boundaries and lookup graphics without requiring Apple firmware.
/// </summary>
[TestClass]
public class Apple2VideoTests
{
    /// <summary>
    ///  Checks repeated HBL bytes, visible addressing, VBL offsets and the six repeated final lines.
    /// </summary>
    /// <param name="row">The scanline.</param>
    /// <param name="column">The column clock.</param>
    /// <param name="address">The expected fetch address.</param>
    [TestMethod]
    [DataRow(0, 0, 0x468)]
    [DataRow(0, 1, 0x468)]
    [DataRow(0, 24, 0x47F)]
    [DataRow(0, 25, 0x400)]
    [DataRow(0, 64, 0x427)]
    [DataRow(8, 25, 0x480)]
    [DataRow(64, 25, 0x428)]
    [DataRow(128, 25, 0x450)]
    [DataRow(191, 64, 0x7F7)]
    [DataRow(192, 25, 0x478)]
    [DataRow(255, 25, 0x7F8)]
    [DataRow(256, 25, 0x7F8)]
    [DataRow(261, 25, 0x7F8)]
    public void ScannerFetchesBlankingAndVisibleMemory(int row, int column, int address)
    {
        Apple2Bus bus = Bus();
        Advance(bus, row * 65 + column);
        bus.Video.FetchAddress.Should().Be((ushort)address);
        bus.SetRam(auxiliary: false, (ushort)address, value: 0x5A);
        bus.Read(0xC020).Should().Be(0x5A);
        ulong cycles = bus.CycleCount;
        bus.Peek(0xC020).Should().Be(0x5A);
        bus.CycleCount.Should().Be(cycles);
    }

    /// <summary>
    ///  Checks visible HGR addressing on every line, page selection and mixed-mode text fetches.
    /// </summary>
    [TestMethod]
    public void HiresScannerUsesInterleavedRowsAndMixedText()
    {
        Apple2Bus bus = Bus();
        bus.Read(0xC050);
        bus.Read(0xC057);
        Advance(bus, cycles: 25);
        for (int row = 0; row < 192; row++)
        {
            int address = 0x2000 + (row % 8) * 1024 + ((row / 8) % 8) * 128 + (row / 64) * 40;
            bus.Video.FetchAddress.Should().Be((ushort)address);
            bus.Read(0xC055);
            bus.Video.FetchAddress.Should().Be((ushort)(address + 0x2000));
            bus.Write(0xC001, value: 0);
            bus.Video.FetchAddress.Should().Be((ushort)address);
            bus.Write(0xC000, value: 0);
            bus.Read(0xC054);
            bus.Read(0xC053);
            bus.Video.FetchAddress.Should().Be(row < 160 ? (ushort)address : (ushort)(address - 0x2000 - (row % 8) * 1024 + 0x400));
            bus.Read(0xC052);
            Advance(bus, cycles: 65);
        }
    }

    /// <summary>
    ///  Checks exact beam wraparound and inverted VBL status.
    /// </summary>
    [TestMethod]
    public void BeamAndVerticalBlankUseAnExactFrameBudget()
    {
        Apple2Bus bus = Bus();
        bus.Video.Beam.HorizontalBlank.Should().BeTrue();
        Advance(bus, cycles: 25);
        bus.Video.Beam.HorizontalBlank.Should().BeFalse();
        Advance(bus, 192 * 65 - 25);
        bus.Video.Beam.VerticalBlank.Should().BeTrue();
        (bus.Read(0xC019) & 128).Should().Be(0);
        Advance(bus, 70 * 65);
        bus.Video.Beam.Should().Be(new Apple2Beam(0, 0, 0));
        (bus.Read(0xC019) & 128).Should().Be(128);
    }

    /// <summary>
    ///  Checks lo-res nibbles, page selection, 80STORE and auxiliary colour phase.
    /// </summary>
    [TestMethod]
    public void LoresAndDoubleLoresSelectPhysicalVideoMemory()
    {
        Apple2Bus bus = Bus();
        bus.Read(0xC050);
        bus.SetRam(auxiliary: false, address: 0x400, value: 0xF1);
        bus.SetRam(auxiliary: true, address: 0x400, value: 0xF1);
        byte[] pixels = bus.Video.RenderBitmap();
        Pixel(pixels, x: 0, y: 0).Should().Equal(221, 0, 51, 255);
        Pixel(pixels, x: 0, y: 4).Should().Equal(255, 255, 255, 255);
        bus.Read(0xC055);
        Pixel(bus.Video.RenderBitmap(), x: 0, y: 0).Should().Equal(0, 0, 0, 255);
        bus.Write(0xC001, value: 0);
        bus.Write(0xC00D, value: 0);
        bus.Peek(0xC05E);
        bus.Switches.Should().NotHaveFlag(Apple2Switches.DoubleHiRes);
        bus.Read(0xC05E);
        pixels = bus.Video.RenderBitmap();
        Pixel(pixels, x: 0, y: 0).Should().Equal(0, 0, 153, 255);
        Pixel(pixels, x: 7, y: 0).Should().Equal(221, 0, 51, 255);
        bus.Write(0xC05F, value: 0);
        bus.Switches.Should().NotHaveFlag(Apple2Switches.DoubleHiRes);
    }

    /// <summary>
    ///  Checks mixed text, 80-column character ordering and flash phase against current RAM.
    /// </summary>
    [TestMethod]
    public void MixedGraphicsRetainTextAndFlash()
    {
        byte[] characters = new byte[4096];
        Array.Fill(characters, (byte)255);
        characters[0x81 * 8] = 254;
        characters[1 * 8] = 255;
        Apple2Bus bus = new(new Apple2Roms(new byte[16384], characters));
        bus.Read(0xC050);
        bus.Read(0xC053);
        bus.SetRam(auxiliary: false, address: 0x650, value: 0x41);
        Pixel(bus.Video.RenderBitmap(), x: 0, y: 160).Should().Equal(182, 243, 182, 255);
        Advance(bus, 65 * 4203);
        Pixel(bus.Video.RenderBitmap(), x: 0, y: 160).Should().Equal(16, 21, 16, 255);
        bus.Write(0xC00F, value: 0);
        Pixel(bus.Video.RenderBitmap(), x: 0, y: 160).Should().Equal(16, 21, 16, 255);
    }

    /// <summary>
    ///  Checks captured fetches are not retroactively changed by RAM writes or page switches.
    /// </summary>
    [TestMethod]
    public void ScannedFrameRetainsMidLineMemoryAndModeChanges()
    {
        Apple2Bus bus = Bus();
        bus.Read(0xC050);
        bus.SetRam(auxiliary: false, address: 0x400, value: 1);
        bus.SetRam(auxiliary: false, address: 0x801, value: 15);
        Advance(bus, cycles: 25);
        bus.Video.ScanCycle();
        bus.Tick();
        bus.SetRam(auxiliary: false, address: 0x400, value: 0);
        bus.Read(0xC055);
        bus.Video.ScanCycle();
        byte[] pixels = bus.Video.RenderScannedBitmap();
        Pixel(pixels, x: 0, y: 0).Should().Equal(221, 0, 51, 255);
        Pixel(pixels, x: 14, y: 0).Should().Equal(255, 255, 255, 255);
        Pixel(bus.Video.RenderBitmap(), x: 0, y: 0).Should().Equal(0, 0, 0, 255);
    }

    /// <summary>
    ///  Checks a CPU soft-switch access cannot replace the byte already fetched on its clock.
    /// </summary>
    [TestMethod]
    public void FloatingBusRetainsThePreCpuFetchOnAModeSwitch()
    {
        Apple2Bus bus = Bus();
        bus.Read(0xC057);
        bus.SetRam(auxiliary: false, address: 0x400, value: 0x11);
        bus.SetRam(auxiliary: false, address: 0x2000, value: 0x22);
        Advance(bus, cycles: 25);
        bus.Video.ScanCycle();
        bus.Read(0xC050).Should().Be(0x11);
        bus.Video.FetchAddress.Should().Be(0x400);
        bus.Tick();
        bus.Video.FetchAddress.Should().Be(0x2001);
    }

    /// <summary>
    ///  Checks HGR phase colours, adjacent white bits and a half-dot high-bit delay.
    /// </summary>
    [TestMethod]
    public void HiresUsesParityDelayAndAdjacentWhitePixels()
    {
        Apple2Bus bus = Bus();
        bus.Read(0xC050);
        bus.Read(0xC057);
        bus.SetRam(auxiliary: false, address: 0x2000, value: 0x81);
        byte[] pixels = bus.Video.RenderBitmap();
        Pixel(pixels, x: 0, y: 0).Should().Equal(0, 0, 0, 255);
        Pixel(pixels, x: 1, y: 0).Should().Equal(1, 150, 255, 255);
        bus.SetRam(auxiliary: false, address: 0x2000, value: 3);
        Pixel(bus.Video.RenderBitmap(), x: 0, y: 0).Should().Equal(255, 255, 255, 255);
        bus.SetRam(auxiliary: false, address: 0x2000, value: 0xC0);
        Pixel(bus.Video.RenderBitmap(), x: 14, y: 0).Should().Equal(0, 0, 0, 255);
        bus.SetRam(auxiliary: false, address: 0x2000, value: 0x40);
        bus.SetRam(auxiliary: false, address: 0x2001, value: 0x80);
        Pixel(bus.Video.RenderBitmap(), x: 14, y: 0).Should().Equal(255, 1, 255, 255);
    }

    /// <summary>
    ///  Checks reusable host buffers produce identical output with no frame allocation.
    /// </summary>
    [TestMethod]
    public void CallerOwnedFramesAreIdenticalAndAllocationFree()
    {
        Apple2Bus bus = Bus();
        bus.Read(0xC050);
        bus.Read(0xC057);
        bus.SetRam(auxiliary: false, address: 0x2000, value: 0x81);
        byte[] pixels = new byte[560 * 192 * 4];
        bus.Video.RenderBitmap(pixels);
        pixels.Should().Equal(bus.Video.RenderBitmap());
        bus.Video.RenderScannedBitmap(pixels);
        pixels.Should().Equal(bus.Video.RenderScannedBitmap());
        Allocations.Fewest(Render).Should().Be(0);
        Action invalid = () => bus.Video.RenderBitmap(new byte[1]);
        invalid.Should().Throw<ArgumentException>();

        void Render()
        {
            for (int pass = 0; pass < 16; pass++)
            {
                bus.Video.RenderBitmap(pixels);
                bus.Video.RenderScannedBitmap(pixels);
            }
        }
    }

    private static byte[] Pixel(byte[] pixels, int x, int y)
    {
        int start = (y * 560 + x) * 4;
        return pixels[start..(start + 4)];
    }

    private static Apple2Bus Bus() => new(new Apple2Roms(new byte[16384], new byte[4096]));
    private static void Advance(Apple2Bus bus, int cycles)
    {
        for (int i = 0; i < cycles; i++) { bus.Tick(); }
    }
}
