// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Cpu.Z80;
using Retrocore.Machines;
using Retrocore.Machines.Trs80;
using Retrocore.Media.Trs80;
using NativeAssembler = Retrocore.Assembler.Assembler;

namespace Retrocore.Tests;

/// <summary>
///  The Model III, 4 and 4P: their memory maps, interrupts, video, keyboard and FD1793, run with a test ROM in native
///  Z80 source.
/// </summary>
[TestClass]
public class Trs80Model3Tests
{
    // Shows READY, counts clock interrupts at $4001 (acknowledged by reading $EC), records port $E4 at $4002 and
    // counts NMIs at $4003, and copies keyboard row 0 to $4000.
    private const string TestRom = """
        .cpu Z80
                .org 0
                DI
                JP   Start
                .org $38
        Tick:   PUSH AF
                IN   A,[$E0]
                IN   A,[$EC]            ; reading the options port acknowledges the clock
                LD   A,[$4001]
                INC  A
                LD   [$4001],A
                POP  AF
                EI
                RETI
                .org $66
        Nmi:    PUSH AF
                IN   A,[$E4]
                LD   [$4002],A
                LD   A,[$4003]
                INC  A
                LD   [$4003],A
                POP  AF
                RETN
                .org $100
        Start:  LD   SP,$8000
                IM   1
                LD   HL,$3C00
                LD   BC,$0400
        Clear:  LD   [HL],' '
                INC  HL
                DEC  BC
                LD   A,B
                OR   C
                JR   NZ,Clear
                LD   HL,Ready
                LD   DE,$3C00
                LD   BC,5
                LDIR
                XOR  A
                LD   [$4001],A
                LD   [$4003],A
                LD   A,$04
                OUT  [$E0],A            ; enable the clock interrupt
                EI
        Loop:   LD   A,[$3801]
                LD   [$4000],A
                JR   Loop
        Ready:  .byte "READY"
        """;

    /// <summary>
    ///  The test ROM boots, shows READY, takes the 30 Hz clock interrupt when enabled and reads the keyboard.
    /// </summary>
    [TestMethod]
    public void TestRomRunsOnTheModelIII()
    {
        Trs80Model3Machine machine = Create(new());
        machine.Run(Trs80Model3Timing.CyclesPerFrame * 2);
        Text(machine, 0, 6).Should().Be("READY ");

        machine.Run(Trs80Model3Timing.CyclesPerTick * 10);
        int ticks = machine.Bus.Peek(0x4001);
        ticks.Should().BeInRange(10, 11);

        machine.Bus.Keyboard.Set(Trs80Key.A, pressed: true);
        machine.Run(200);
        machine.Bus.Peek(0x4000).Should().Be(0x02, "A is row 0, bit 1");
    }

    /// <summary>
    ///  The clock interrupt does not reach the Z80 while port <c>$E0</c> masks it.
    /// </summary>
    [TestMethod]
    public void ClockInterruptFollowsTheMask()
    {
        Trs80Model3Bus bus = Create(new()).Bus;
        bus.Out(0xE0, 0x00);
        for (int index = 0; index < Trs80Model3Timing.CyclesPerTick; index++) { bus.Tick(); }
        bus.InterruptRequested.Should().BeFalse();
        bus.In(0xE0).Should().Be(0xFF, "nothing enabled interrupts");
        bus.Out(0xE0, 0x04);
        bus.InterruptRequested.Should().BeTrue("the clock latched while masked");
        bus.In(0xE0).Should().Be(0xFB, "bit 2, active low, is the clock");
        bus.In(0xEC);
        bus.InterruptRequested.Should().BeFalse("reading $EC acknowledges it");
    }

    /// <summary>
    ///  The Model III's map: ROM to <c>$37FF</c> with the printer at <c>$37E8</c>, the keyboard, 1K of video RAM and RAM
    ///  from <c>$4000</c>, as much as is fitted.
    /// </summary>
    [TestMethod]
    public void ModelIIIMemoryMap()
    {
        Trs80Model3Bus bus = Create(new() { RamKilobytes = 16 }).Bus;
        bus.Area(0x0000).Should().Be(Trs80Model3MemoryArea.Rom);
        bus.Area(0x37E8).Should().Be(Trs80Model3MemoryArea.Printer);
        bus.Area(0x3800).Should().Be(Trs80Model3MemoryArea.Keyboard);
        bus.Area(0x3C00).Should().Be(Trs80Model3MemoryArea.Video);
        bus.Area(0x4000).Should().Be(Trs80Model3MemoryArea.Ram);
        bus.Area(0x7FFF).Should().Be(Trs80Model3MemoryArea.Ram);
        bus.Area(0x8000).Should().Be(Trs80Model3MemoryArea.Unmapped);
        bus.Read(0x8000).Should().Be(0xFF);
        bus.Write(0x0000, 0x12);
        bus.Read(0x0000).Should().Be(0xF3, "ROM is DI");
        bus.Out(0x84, 0x03);
        bus.Area(0x0000).Should().Be(Trs80Model3MemoryArea.Rom, "a Model III has no memory maps");
    }

    /// <summary>
    ///  A Model 4's four maps: Model III, RAM under ROM for writes, RAM with the keyboard and 2K of video at the top,
    ///  and all RAM.
    /// </summary>
    [TestMethod]
    public void Model4MemoryMaps()
    {
        Trs80Model3Bus bus = Create(new() { Variant = Trs80Model3Variant.Model4, RamKilobytes = 64 }).Bus;
        bus.Area(0x1000).Should().Be(Trs80Model3MemoryArea.Rom);

        bus.Out(0x84, 0x01);
        bus.Write(0x1000, 0x5A);
        bus.Read(0x1000).Should().Be(0x00, "map 1 still reads the ROM");
        bus.Area(0x1000).Should().Be(Trs80Model3MemoryArea.Rom);

        bus.Out(0x84, 0x03);
        bus.Area(0x1000).Should().Be(Trs80Model3MemoryArea.Ram);
        bus.Read(0x1000).Should().Be(0x5A, "map 1 wrote the RAM under the ROM");
        bus.Area(0xF800).Should().Be(Trs80Model3MemoryArea.Ram);

        bus.Out(0x84, 0x02);
        bus.Area(0x3C00).Should().Be(Trs80Model3MemoryArea.Ram);
        bus.Area(0xF400).Should().Be(Trs80Model3MemoryArea.Keyboard);
        bus.Area(0xF800).Should().Be(Trs80Model3MemoryArea.Video);
        bus.Write(0xFC00, (byte)'Z');
        bus.Video.Read(0x400).Should().Be((byte)'Z', "map 2 shows all 2K");

        // Back in map 0, port $84 bit 7 shows the second 1K page at $3C00.
        bus.Out(0x84, 0x80);
        bus.Read(0x3C00).Should().Be((byte)'Z');
        bus.Out(0x84, 0x00);
        bus.Read(0x3C00).Should().NotBe((byte)'Z');
    }

    /// <summary>
    ///  With 128K, port <c>$84</c>'s paging bits swap a 32K half of the second 64K into either half of the address
    ///  space.
    /// </summary>
    [TestMethod]
    public void Model4PagesTheSecondBank()
    {
        Trs80Model3Bus bus = Create(new() { Variant = Trs80Model3Variant.Model4, RamKilobytes = 128 }).Bus;
        bus.Out(0x84, 0x03);
        bus.Write(0x9000, 0x11);
        bus.Write(0x1000, 0x22);

        // ENPAGE with SRCPAGE clear: the upper half shows the second bank's lower 32K.
        bus.Out(0x84, 0x23);
        bus.Read(0x9000).Should().Be(0x00);
        bus.Write(0x9000, 0x33);
        bus.Read(0x1000).Should().Be(0x22, "the lower half is unchanged");

        // ENPAGE with DESPAGE: the lower half shows it instead.
        bus.Out(0x84, 0x63);
        bus.Read(0x1000).Should().Be(0x33);
        bus.Read(0x9000).Should().Be(0x11);

        // SRCPAGE picks the second bank's upper 32K.
        bus.Out(0x84, 0x73);
        bus.Read(0x1000).Should().Be(0x00);
        bus.Out(0x84, 0x03);
        bus.Read(0x1000).Should().Be(0x22);
        bus.Read(0x9000).Should().Be(0x11);
    }

    /// <summary>
    ///  The 4P's boot ROM fills only <c>$0000</c>-<c>$0FFF</c> and port <c>$9C</c> switches it out; it has no
    ///  cassette.
    /// </summary>
    [TestMethod]
    public void Model4PBootRomSwitchesOut()
    {
        byte[] boot = new byte[Trs80Model3Roms.BootSize];
        boot[0] = 0xC9;
        Trs80Model3Machine machine = Create(new() { Variant = Trs80Model3Variant.Model4P, RamKilobytes = 64 }, boot);
        Trs80Model3Bus bus = machine.Bus;
        machine.Cassette.Should().BeNull();
        bus.Area(0x0000).Should().Be(Trs80Model3MemoryArea.Rom);
        bus.Area(0x1000).Should().Be(Trs80Model3MemoryArea.Ram);
        bus.Out(0x84, 0x01);
        bus.Write(0x0000, 0x77);
        bus.Read(0x0000).Should().Be(0xC9);
        bus.Out(0x9C, 0x00);
        bus.Read(0x0000).Should().Be(0x77);
        bus.BootRomEnabled.Should().BeFalse();
    }

    /// <summary>
    ///  Port <c>$EC</c> bit 6 runs a Model 4 at 4 MHz, with the devices still counting 2 MHz time.
    /// </summary>
    [TestMethod]
    public void Model4RunsFast()
    {
        Trs80Model3Machine machine = Create(new() { Variant = Trs80Model3Variant.Model4, RamKilobytes = 64 });
        machine.ClockHertz.Should().Be(Trs80Model3Timing.ClockHertz);
        machine.Bus.Out(0xEC, 0x40);
        machine.ClockHertz.Should().Be(Trs80Model3Timing.FastClockHertz);
        ulong frames = machine.Bus.Video.Frames;
        machine.Run(Trs80Model3Timing.CyclesPerFrame * 2);
        (machine.Bus.Video.Frames - frames).Should().Be(1, "two frames of T-states at 4 MHz are one frame of time");
    }

    /// <summary>
    ///  The 80x24 display shows from the 6845's start address, 8 pixels a character and 10 lines a row; the 64x16
    ///  display is centered on the Model 4's screen.
    /// </summary>
    [TestMethod]
    public void Model4Shows80Columns()
    {
        Trs80Model3Bus bus = Create(new() { Variant = Trs80Model3Variant.Model4, RamKilobytes = 64 }).Bus;
        Trs80Model3Video video = bus.Video;
        video.Width.Should().Be(640);
        video.Height.Should().Be(240);
        bus.Out(0x84, 0x04);
        video.Columns.Should().Be(80);
        video.Rows.Should().Be(24);
        bus.Out(0x88, 12);
        bus.Out(0x89, 0x00);
        bus.Out(0x88, 13);
        bus.Out(0x89, 0x10);
        video.StartAddress.Should().Be(0x10);
        video.Write(0x10, 0xBF);
        video.Displayed(0, 0).Should().Be(0xBF);

        byte[] pixels = new byte[video.Width * video.Height * 4];
        video.Render(pixels, scanned: false);
        Lit(pixels, video, 0, 0).Should().BeTrue("a full graphics block");
        Lit(pixels, video, 7, 9).Should().BeTrue();
        Lit(pixels, video, 8, 0).Should().BeFalse("the next cell is empty");

        bus.Out(0x84, 0x00);
        video.Write(0, 0xBF);
        video.Render(pixels, scanned: false);
        Lit(pixels, video, 0, 0).Should().BeFalse("the 64x16 picture is centered");
        Lit(pixels, video, 64, 24).Should().BeTrue();
    }

    /// <summary>
    ///  The FD1793 reads a double-density sector; its INTRQ raises an NMI where port <c>$E4</c> enables it, and a
    ///  drive select with wait holds the Z80 until the controller asks for data. INTRQ ends the wait, so the NMI
    ///  handler's read of the status, which clears INTRQ, is not held, as the ROM's boot needs.
    /// </summary>
    [TestMethod]
    public void ReadsSectorsThroughTheFd1793()
    {
        Trs80Model3Machine machine = Create(new() { DiskController = true });
        Trs80Model3Bus bus = machine.Bus;
        FloppyDisk disk = new();
        for (int sector = 0; sector < 18; sector++)
        {
            byte[] data = new byte[256];
            for (int index = 0; index < data.Length; index++) { data[index] = (byte)(sector + index); }
            disk.Add(0, 0, new FloppySector(0, 0, (byte)sector, data, doubleDensity: true));
        }

        machine.Drives[0].Insert(disk, "test", "JV3");
        bus.Out(0xE4, 0x80);
        bus.Out(0xF4, 0x81);
        bus.Out(0xF2, 5);
        bus.Out(0xF0, 0x80);
        bus.Out(0xF4, 0xC1);
        bus.WaitRequested.Should().BeTrue("wait holds the Z80 until DRQ");
        List<byte> read = [];
        for (int cycle = 0; cycle < Trs80Model3Timing.ClockHertz && !bus.NmiRequested; cycle++)
        {
            bus.Tick();
            if (bus.Disks.DataRequest)
            {
                bus.WaitRequested.Should().BeFalse();
                read.Add(bus.In(0xF3));
            }
        }

        read.Should().HaveCount(256);
        read[0].Should().Be(5);
        read[255].Should().Be(4);
        bus.NmiRequested.Should().BeTrue("INTRQ raises the NMI");
        bus.In(0xE4).Should().Be(0x7F, "bit 7, active low, is INTRQ");
        bus.In(0xF0).Should().Be(0x00, "success, and reading status clears INTRQ");
        bus.NmiRequested.Should().BeFalse();
        bus.WaitRequested.Should().BeFalse("INTRQ ended the wait, until drive select sets it again");
        bus.Out(0xF4, 0xC1);
        bus.WaitRequested.Should().BeTrue();
    }

    /// <summary>
    ///  The reset button raises an NMI with port <c>$E4</c> bit 5 showing why, whatever the mask.
    /// </summary>
    [TestMethod]
    public void ResetRaisesNmi()
    {
        Trs80Model3Machine machine = Create(new());
        machine.Run(Trs80Model3Timing.CyclesPerFrame);
        machine.Reset();
        machine.Run(2000);
        machine.Bus.Peek(0x4003).Should().Be(1);
        machine.Bus.Peek(0x4002).Should().Be(0xDF, "bit 5, active low, is reset");
    }

    /// <summary>
    ///  The cassette's 500 baud input latch reads in port <c>$FF</c> bit 7, and port <c>$EC</c> bit 1 runs the motor.
    /// </summary>
    [TestMethod]
    public void CassetteMotorIsOnPortEC()
    {
        Trs80Model3Machine machine = Create(new());
        (machine.Cassette ?? throw new InvalidOperationException()).Play(new CassetteImage([0xFF, 0xFF]), "tape");
        machine.Bus.Out(0xEC, 0x02);
        machine.Bus.Cassette.MotorOn.Should().BeTrue();
        machine.Bus.Tick();
        (machine.Bus.In(0xFF) & 0x80).Should().Be(0x80, "the first clock pulse");
        machine.Bus.Out(0xFF, 0x00);
        (machine.Bus.In(0xFF) & 0x80).Should().Be(0, "writing $FF clears the latch");
        machine.Bus.Out(0xEC, 0x00);
        machine.Bus.Cassette.MotorOn.Should().BeFalse();
    }

    /// <summary>
    ///  The machine describes itself through <see cref="IMachine"/>.
    /// </summary>
    [TestMethod]
    public void IdentifiesItself()
    {
        Trs80Model3Machine model3 = Create(new() { DiskController = false });
        model3.Id.Should().Be("trs80-model3");
        ((IMachine)model3).Devices.Should().HaveCount(1, "the cassette, and no drives without the controller");
        Trs80Model3Machine model4 = Create(new()
        {
            Variant = Trs80Model3Variant.Model4,
            RamKilobytes = 128,
            DiskController = true
        });

        model4.Id.Should().Be("trs80-model4");
        model4.Devices.Should().HaveCount(5);
        FluentActions.Invoking(() => Create(new() { Variant = Trs80Model3Variant.Model4, RamKilobytes = 48 }))
            .Should().Throw<ArgumentException>();
    }

    /// <summary>
    ///  Assembles a 14K test ROM.
    /// </summary>
    /// <param name="source">The native Z80 source.</param>
    /// <returns>The ROM.</returns>
    internal static byte[] AssembleRom(string source)
    {
        AssemblyResult result = new NativeAssembler().Assemble(
            new AssemblySource(source, "rom.asm"),
            new AssemblyOptions(Z80Isa.Name, 0, Trs80Model3Roms.SystemSize));

        result.Diagnostics.Should().BeEmpty();
        return result.Sections[0].Bytes.ToArray();
    }

    private static Trs80Model3Machine Create(Trs80Model3Configuration configuration, byte[]? rom = null)
    {
        byte[] font = new byte[Trs80Model3Roms.CharacterGeneratorSize];
        for (int index = 0; index < font.Length; index++) { font[index] = (byte)(index >> 3); }
        return new(configuration, new Trs80Model3Roms(rom ?? AssembleRom(TestRom), font));
    }

    private static string Text(Trs80Model3Machine machine, int offset, int length) =>
        new([.. Enumerable.Range(offset, length).Select(index => (char)machine.Bus.Video.Read(index))]);

    private static bool Lit(byte[] pixels, Trs80Model3Video video, int x, int y) => pixels[((y * video.Width) + x) * 4] > 0x80;
}
