// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.IO.Compression;
using Retrocore.Machines.Atari;

namespace Retrocore.Tests;

/// <summary>
///  Cartridges and binary load files: the banking schemes, and real cartridges from MAME's <c>a800</c> list
///  (<c>%USERPROFILE%\Retrocore\atari8-media\extract\a800</c>).
/// </summary>
[TestClass]
public class AtariCartridgeTests
{
    // A ROM whose every 8 KB bank is filled with its number.
    private static byte[] Banks(int size)
    {
        byte[] rom = new byte[size];
        for (int i = 0; i < size; i++) { rom[i] = (byte)(i >> 13); }
        return rom;
    }

    // A cartridge's ROM from MAME's list, or inconclusive.
    private static byte[] FromList(string set)
    {
        string zip = Path.Join(ExternalTestData.Root, "atari8-media", "extract", "a800", "a800", set + ".zip");
        if (!File.Exists(zip)) { Assert.Inconclusive($"MAME's {set} isn't at {zip}."); }
        using ZipArchive archive = ZipFile.OpenRead(zip);
        ZipArchiveEntry entry = archive.Entries.First(e => e.Name.EndsWith(".rom", StringComparison.OrdinalIgnoreCase));
        using Stream stream = entry.Open();
        using MemoryStream memory = new();
        stream.CopyTo(memory);
        return memory.ToArray();
    }

    /// <summary>
    ///  XEGS: the bank written to the control page shows at <c>$8000</c>, the last bank stays at <c>$A000</c>.
    /// </summary>
    [TestMethod]
    public void XegsBanksOnWrite()
    {
        AtariCartridge cartridge = new(Banks(0x8000), AtariCartridgeType.Xegs32);
        cartridge.Rd4.Should().BeTrue();
        cartridge.Rd5.Should().BeTrue();
        cartridge.Read(0xA123).Should().Be(3);
        cartridge.Read(0x8123).Should().Be(0);
        cartridge.Control(0xD500, 2);
        cartridge.Read(0x8123).Should().Be(2);
        cartridge.Control(0xD5FF, value: null);
        cartridge.Read(0x8123).Should().Be(2, "reads of the control page don't switch an XEGS cartridge");
    }

    /// <summary>
    ///  Williams: an access to <c>$D500-$D507</c> picks the bank, <c>$D508-$D50F</c> turns the cartridge off, and the
    ///  RAM under it shows.
    /// </summary>
    [TestMethod]
    public void WilliamsBanksAndTurnsOff()
    {
        AtariMachine machine = AtariMachineTests.Machine();
        AtariCartridge cartridge = new(Banks(0x10000), AtariCartridgeType.Williams64);
        machine = new(AtariRoms.LoadFromDirectory(AtariMachineTests.RomDirectory), left: cartridge);
        AtariBus bus = machine.Bus;
        bus.Read(0xA000).Should().Be(0);
        bus.Read(0xD505);
        bus.Read(0xA000).Should().Be(5);
        bus.Read(0xD518);
        bus.Read(0xA000).Should().Be(5, "the cartridge decodes only $D500-$D50F");
        bus.Write(0xD508, 0);
        cartridge.Rd5.Should().BeFalse();
        bus.Area(0xA000).Should().Be(AtariMemoryArea.Ram);
        bus.Write(0xA000, 0x42);
        bus.Read(0xA000).Should().Be(0x42);
        bus.Read(0xD502);
        bus.Read(0xA000).Should().Be(2, "the cartridge covers the RAM again");
    }

    /// <summary>
    ///  Atarimax 128 KB, Express and OSS: their control page schemes.
    /// </summary>
    [TestMethod]
    public void OtherSchemesSwitch()
    {
        AtariCartridge atarimax = new(Banks(0x20000), AtariCartridgeType.Atarimax128);
        atarimax.Control(0xD50C, value: null);
        atarimax.Read(0xA000).Should().Be(12);
        atarimax.Control(0xD510, value: null);
        atarimax.Rd5.Should().BeFalse();

        AtariCartridge express = new(Banks(0x10000), AtariCartridgeType.Express64);
        express.Control(0xD571, value: null);
        express.Read(0xA000).Should().Be(6, "Express inverts the bank number");
        express.Control(0xD500, value: null);
        express.Read(0xA000).Should().Be(6, "Express answers only at $D570-$D57F");

        byte[] oss = new byte[0x4000];
        for (int i = 0; i < oss.Length; i++) { oss[i] = (byte)(i >> 12); }
        AtariCartridge oss091 = new(oss, AtariCartridgeType.Oss091);
        oss091.Read(0xB000).Should().Be(0, "the first 4 KB is fixed at $B000");
        oss091.Control(0xD501, value: null);
        oss091.Read(0xA000).Should().Be(3);
        oss091.Control(0xD509, value: null);
        oss091.Read(0xA000).Should().Be(2);
        oss091.Control(0xD508, value: null);
        oss091.Rd5.Should().BeFalse();
    }

    /// <summary>
    ///  A <c>.car</c> file names its type in its header.
    /// </summary>
    [TestMethod]
    public void CarHeaderGivesTheType()
    {
        byte[] car = new byte[16 + 0x8000];
        "CART"u8.CopyTo(car);
        car[7] = 12;
        AtariCartridge.Load(car).Type.Should().Be(AtariCartridgeType.Xegs32);
    }

    /// <summary>
    ///  Real cartridges start: Star Raiders (8 KB) and Dropzone (Williams 64 KB) take over from the OS and draw their
    ///  screens, and Dropzone switches its banks (it ends with the cartridge turned off, running from RAM).
    /// </summary>
    /// <param name="set">MAME's set name.</param>
    /// <param name="type">The cartridge's hardware.</param>
    [TestMethod]
    [DataRow("starraid", AtariCartridgeType.Standard8)]
    [DataRow("dropzone", AtariCartridgeType.Williams64)]
    public void CartridgesStart(string set, AtariCartridgeType type)
    {
        AtariMachineTests.Machine();
        AtariCartridge cartridge = new(FromList(set), type);
        AtariMachine machine = new(AtariRoms.LoadFromDirectory(AtariMachineTests.RomDirectory), left: cartridge);
        machine.Run(TimeSpan.FromSeconds(5));
        machine.RunFrame();
        machine.Bus.Peek(0x0244).Should().Be(0, "COLDST is clear once the OS hands over");
        machine.ReadTextScreen().Should().NotContain(line => line.Contains("MEMO PAD", StringComparison.Ordinal));
        if (type == AtariCartridgeType.Williams64)
        {
            (cartridge.Bank != 0 || !cartridge.Rd5).Should().BeTrue("Dropzone switched banks");
        }

        HashSet<uint> colors = [];
        byte[] frame = machine.RenderBitmap();
        for (int i = 0; i < frame.Length; i += 4) { colors.Add(BitConverter.ToUInt32(frame, i)); }
        colors.Count.Should().BeGreaterThan(2, "the game draws its screen");
    }

    /// <summary>
    ///  A binary load file boots from a disk of our loader: its segments load, past <c>$FFFF</c> headers, the
    ///  segment that sets <c>INITAD</c> is called, and <c>RUNAD</c> runs.
    /// </summary>
    [TestMethod]
    public void ExecutableLoadsAndRuns()
    {
        byte[] file =
        [
            0xFF, 0xFF,
            0x00, 0x30, 0x07, 0x30,                         // $3000: LDA #$46; STA COLOR4; JMP $3005
            0xA9, 0x46, 0x8D, 0xC8, 0x02, 0x4C, 0x05, 0x30,
            0x00, 0x31, 0x05, 0x31,                         // $3100: LDA #$55; STA $0600; RTS
            0xA9, 0x55, 0x8D, 0x00, 0x06, 0x60,
            0xE2, 0x02, 0xE3, 0x02, 0x00, 0x31,             // INITAD = $3100
            0xFF, 0xFF,
            0xE0, 0x02, 0xE1, 0x02, 0x00, 0x30              // RUNAD = $3000
        ];

        // And a 600-byte segment at $4000, across five sectors.
        byte[] pattern = new byte[600];
        for (int i = 0; i < pattern.Length; i++) { pattern[i] = (byte)(i * 7); }
        file = [.. file, 0x00, 0x40, 0x57, 0x42, .. pattern];

        AtariMachineTests.Machine();
        AtariRoms roms = AtariRoms.LoadFromDirectory(AtariMachineTests.RomDirectory);
        if (roms.DiskDrive.IsEmpty)
        {
            Assert.Inconclusive("The 810's firmware (MAME's atari810 set) isn't beside the OS ROMs.");
        }

        AtariMachine machine = new(roms, diskDrives: 1);
        machine.Drives[0].Insert(AtariExecutable.BootDisk(file), "test.xex", "XEX");
        for (int second = 0; second < 30 && machine.Bus.Peek(0x02C8) != 0x46; second++)
        {
            machine.Run(TimeSpan.FromSeconds(1));
        }

        for (int i = 0; i < pattern.Length; i++) { machine.Bus.Peek((ushort)(0x4000 + i)).Should().Be(pattern[i]); }
        machine.Bus.Peek(0x0600).Should().Be(0x55, "INITAD ran");
        machine.Bus.Peek(0x02C8).Should().Be(0x46, "RUNAD ran");
        machine.Processor.Registers.ProgramCounter.Should().BeInRange((ushort)0x3005, (ushort)0x3007);
    }
}
