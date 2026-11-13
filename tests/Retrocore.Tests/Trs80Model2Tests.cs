// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Cpu.Z80;
using Retrocore.Machines.Trs80;
using Retrocore.Media.Trs80;
using NativeAssembler = Retrocore.Assembler.Assembler;

namespace Retrocore.Tests;

/// <summary>
///  The Model II: its banked memory, the CTC's mode 2 keyboard interrupt, the clock's NMI, the 6845 and the DMA
///  reading the FD1791, run with a test boot ROM in native Z80 source.
/// </summary>
[TestClass]
public class Trs80Model2Tests
{
    // Sets up mode 2 with the CTC's channel 3 counting keyboard interrupts, maps video RAM and shows READY, and
    // enables the clock. A key's code goes to $4000 and keys are counted at $4002; clock NMIs are counted at $4001.
    private const string TestRom = """
        .cpu Z80
                .org 0
                DI
                JP   Start
                .org $66
        Nmi:    PUSH AF
                IN   A,[$FE]            ; acknowledge the clock
                LD   A,[$4001]
                INC  A
                LD   [$4001],A
                POP  AF
                RETN
                .org $100
        Start:  LD   SP,$8000
                LD   A,$07
                LD   I,A
                IM   2
                XOR  A
                LD   [$4000],A
                LD   [$4001],A
                LD   [$4002],A
                LD   A,$10
                OUT  [$F0],A            ; the CTC's vectors from $10
                LD   A,$C7              ; interrupt, counter, falling edge, constant follows, reset
                OUT  [$F3],A
                LD   A,1
                OUT  [$F3],A
                LD   A,$A1              ; video RAM in, the clock on, bank 1 at $8000
                OUT  [$FF],A
                LD   HL,Ready
                LD   DE,$F800
                LD   BC,5
                LDIR
                EI
        Loop:   JR   Loop
        Key:    PUSH AF
                IN   A,[$FC]
                LD   [$4000],A
                LD   A,[$4002]
                INC  A
                LD   [$4002],A
                POP  AF
                EI
                RETI
        Ready:  .byte "READY"
                .org $716
                .word Key
        """;

    /// <summary>
    ///  The boot ROM's program shows READY, takes the clock's NMI 30 times a second and each key through the CTC in
    ///  mode 2, the daisy chain releasing the CTC at each RETI.
    /// </summary>
    [TestMethod]
    public void TestRomTakesKeysAndTheClock()
    {
        Trs80Model2Machine machine = Create(new());
        machine.Run(Trs80Model2Timing.ClockHertz / 10);
        machine.Bus.Video.Displayed(0, 0).Should().Be((byte)'R');
        machine.Bus.Video.Displayed(0, 4).Should().Be((byte)'Y');

        machine.Run(Trs80Model2Timing.ClockHertz);
        int ticks = machine.Bus.Peek(0x4001);
        ticks.Should().BeInRange(28, 34, "the clock interrupts on every other frame");

        machine.Bus.Keyboard.Type((byte)'A');
        machine.Bus.Keyboard.Type((byte)'B');
        machine.Bus.Keyboard.Type(0x1E);
        machine.Run(Trs80Model2Timing.ClockHertz / 10);
        machine.Bus.Peek(0x4002).Should().Be(3);
        machine.Bus.Peek(0x4000).Should().Be(0x1E);
        machine.Bus.Keyboard.IsTyping.Should().BeFalse();
    }

    /// <summary>
    ///  The first 32K is always RAM, under the boot ROM until port <c>$F9</c> switches it out; port <c>$FF</c>
    ///  selects the bank at <c>$8000</c> and maps video RAM over its top 2K.
    /// </summary>
    [TestMethod]
    public void MemoryBanks()
    {
        Trs80Model2Bus bus = Create(new() { RamKilobytes = 128 }).Bus;
        bus.Area(0x0000).Should().Be(Trs80Model2MemoryArea.Rom);
        bus.Write(0x0000, 0x55);
        bus.Read(0x0000).Should().Be(0xF3, "the ROM's DI");
        bus.Out(0xF9, 0);
        bus.Read(0x0000).Should().Be(0x55, "the RAM under the ROM");

        bus.Area(0x8000).Should().Be(Trs80Model2MemoryArea.Unmapped, "no bank is selected at reset");
        bus.Out(0xFF, 0x01);
        bus.Write(0x8000, 0x11);
        bus.Out(0xFF, 0x02);
        bus.Write(0x8000, 0x22);
        bus.Out(0xFF, 0x01);
        bus.Read(0x8000).Should().Be(0x11);
        bus.Out(0xFF, 0x03);
        bus.Read(0x8000).Should().Be(0x00, "bank 3 is the last 32K of 128K");
        bus.Out(0xFF, 0x04);
        bus.Area(0x8000).Should().Be(Trs80Model2MemoryArea.Unmapped, "bank 4 is beyond 128K");
        bus.Out(0xFF, 0x81);
        bus.Area(0xF800).Should().Be(Trs80Model2MemoryArea.Video);
        bus.Area(0xF7FF).Should().Be(Trs80Model2MemoryArea.Ram);
    }

    /// <summary>
    ///  The DMA, ready on the FD1791's DRQ, moves a sector from the controller's data port into memory and
    ///  stops after its block.
    /// </summary>
    [TestMethod]
    public void DmaReadsASector()
    {
        Trs80Model2Machine machine = Create(new());
        Trs80Model2Bus bus = machine.Bus;
        FloppyDisk disk = new();
        for (int sector = 1; sector <= 26; sector++)
        {
            byte[] data = new byte[128];
            for (int index = 0; index < data.Length; index++) { data[index] = (byte)((sector * 3) + index); }
            disk.Add(0, 0, new FloppySector(0, 0, (byte)sector, data, doubleDensity: false));
        }

        machine.Drives[0].Insert(disk, "test", "IMD");
        bus.Out(0xEF, 0x4E);
        bus.Disks.SelectedDrive.Should().Be(0);
        bus.Disks.Side.Should().Be(0);
        bus.Disks.DoubleDensity.Should().BeFalse();

        // B (the controller's data port) to A (memory at $2000, counting up), 128 bytes, a byte at each DRQ.
        foreach (byte value in (byte[])[0xC3, 0x79, 0x00, 0x20, 0x7F, 0x00, 0x14, 0x28, 0x85, 0xE7, 0x8A, 0xCF, 0x87])
        {
            bus.Out(0xF8, value);
        }

        bus.Dma.Enabled.Should().BeTrue();
        bus.Out(0xE6, 2);
        bus.Out(0xE4, 0x88);
        for (int cycle = 0; cycle < Trs80Model2Timing.ClockHertz && (bus.Disks.IsBusy || bus.Dma.Enabled); cycle++)
        {
            bus.Tick();
        }

        bus.Dma.Enabled.Should().BeFalse("the block ended");
        bus.Dma.Counter.Should().Be(128);
        bus.Read(0x2000).Should().Be(6);
        bus.Read(0x207F).Should().Be(6 + 127);
        bus.Read(0x2080).Should().Be(0);
        (bus.Pio.Read(0) & 0x01).Should().Be(1, "the PIO's port A shows INTRQ");
        bus.In(0xE4).Should().Be(0x00, "success");
    }

    /// <summary>
    ///  The 6845's registers set the picture: rows, scanlines, the start address and the cursor.
    /// </summary>
    [TestMethod]
    public void CrtcSetsThePicture()
    {
        Trs80Model2Bus bus = Create(new()).Bus;
        Trs80Model2Video video = bus.Video;
        video.Columns.Should().Be(80);
        video.Rows.Should().Be(24);
        video.LinesPerRow.Should().Be(10);
        bus.Out(0xFC, 12);
        bus.Out(0xFD, 0x01);
        bus.Out(0xFC, 13);
        bus.Out(0xFD, 0x00);
        video.StartAddress.Should().Be(0x100);
        bus.Out(0xFC, 14);
        bus.Out(0xFD, 0x01);
        bus.In(0xFD).Should().Be(0x01, "the cursor address reads back");
        bus.Out(0xFF, 0x80);
        bus.Write(0xF900, (byte)'X');
        video.Displayed(0, 0).Should().Be((byte)'X');
    }

    /// <summary>
    ///  A <c>.dsk</c> is read by its contents: JV1 for any whole number of 256-byte sectors, a last track cut short
    ///  included, and JV3 by its sector table, even when its length is whole JV1 tracks.
    /// </summary>
    [TestMethod]
    public void DetectsTheFormatOfADsk()
    {
        Trs80DiskImage.Read(new byte[256], ".dsk").Format.Should().Be("JV1", "one sector is a JV1 track cut short");
        Trs80DiskImage.Read(new byte[2560 + 512], ".dsk").Format.Should().Be("JV1");
        Trs80DiskImage.Read(new byte[2560 * 4], ".dsk").Format.Should().Be("JV1");

        FloppyDisk disk = new();
        for (int sector = 0; sector < 10; sector++)
        {
            disk.Add(0, 0, new FloppySector(0, 0, (byte)sector, new byte[256], doubleDensity: false));
        }

        byte[] jv3 = Jv3Format.Write(disk);
        (FloppyDisk read, string format) = Trs80DiskImage.Read(jv3, ".dsk");
        format.Should().Be("JV3");
        read.Track(0, 0).Should().HaveCount(10);
    }

    /// <summary>
    ///  IMD images read their sectors, compressed and deleted records among them.
    /// </summary>
    [TestMethod]
    public void ReadsImd()
    {
        List<byte> image = [.. "IMD 1.18: test\r\n"u8, 0x1A];
        image.AddRange([3, 0, 0, 2, 1, 1, 2]);
        image.Add(1);
        image.AddRange(Enumerable.Range(0, 256).Select(index => (byte)index));
        image.AddRange([4, 0xE5]);
        (FloppyDisk disk, string format) = Trs80DiskImage.Read([.. image], ".dsk");
        format.Should().Be("IMD");
        IReadOnlyList<FloppySector> sectors = disk.Track(0, 0);
        sectors.Should().HaveCount(2);
        sectors[0].DoubleDensity.Should().BeTrue();
        sectors[0].Data[255].Should().Be(255);
        sectors[1].Sector.Should().Be(2);
        sectors[1].Data.Should().AllSatisfy(value => value.Should().Be(0xE5));
        sectors[1].DataAddressMark.Should().Be(0xF8, "record 4 is compressed deleted data");
    }

    /// <summary>
    ///  DMK images read each ID mark the track's table points to, and the data field after it, with a CRC error when
    ///  the data field's stored CRC does not match.
    /// </summary>
    [TestMethod]
    public void ReadsDmk()
    {
        const int Length = 0x200;
        byte[] image = new byte[16 + Length];
        image[1] = 1;
        image[2] = Length & 0xFF;
        image[3] = Length >> 8;
        image[4] = 0x10;
        int track = 16;
        image[track] = 0x80;
        image[track + 1] = 0x80;
        int id = track + 0x80;
        image[id] = 0xFE;
        image[id + 1] = 0;
        image[id + 2] = 0;
        image[id + 3] = 7;
        image[id + 4] = 1;
        int data = id + 7 + 22;
        image[data] = 0xFB;
        for (int index = 0; index < 256; index++) { image[data + 1 + index] = (byte)(255 - index); }

        // CRC-CCITT over the three A1 sync bytes, the mark and the data, high byte first.
        ushort crc = 0xFFFF;
        foreach (byte value in (byte[])[0xA1, 0xA1, 0xA1, .. image.AsSpan(data, 257)])
        {
            crc ^= (ushort)(value << 8);
            for (int bit = 0; bit < 8; bit++)
            {
                crc = (crc & 0x8000) != 0 ? (ushort)((crc << 1) ^ 0x1021) : (ushort)(crc << 1);
            }
        }

        image[data + 257] = (byte)(crc >> 8);
        image[data + 258] = (byte)crc;
        (FloppyDisk disk, string format) = Trs80DiskImage.Read(image, ".dmk");
        format.Should().Be("DMK");
        FloppySector sector = disk.Track(0, 0).Should().ContainSingle().Subject;
        sector.Sector.Should().Be(7);
        sector.DoubleDensity.Should().BeTrue();
        sector.Data[0].Should().Be(255);
        sector.Data[255].Should().Be(0);
        sector.CrcError.Should().BeFalse();

        image[data + 100] ^= 0x01;
        Trs80DiskImage.Read(image, ".dmk").Disk.Track(0, 0).Single().CrcError.Should().BeTrue("a data byte no longer matches the CRC");
    }

    private static Trs80Model2Machine Create(Trs80Model2Configuration configuration)
    {
        AssemblyResult result = new NativeAssembler().Assemble(
            new AssemblySource(TestRom, "boot.asm"),
            new AssemblyOptions(Z80Isa.Name, 0, Trs80Model2Roms.BootSize));

        result.Diagnostics.Should().BeEmpty();
        byte[] font = new byte[Trs80Model2Roms.CharacterGeneratorSize];
        return new(configuration, new Trs80Model2Roms(result.Sections[0].Bytes.Span, font));
    }
}
