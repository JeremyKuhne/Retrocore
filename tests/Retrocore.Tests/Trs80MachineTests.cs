// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Cpu.Z80;
using Retrocore.Machines;
using Retrocore.Machines.Trs80;
using NativeAssembler = Retrocore.Assembler.Assembler;

namespace Retrocore.Tests;

/// <summary>
///  The Model I's memory map, clock interrupt, keyboard and video, run with a test ROM in native Z80 source.
/// </summary>
[TestClass]
public class Trs80MachineTests
{
    // Clears the screen, shows READY, counts clock interrupts at $4001 and copies keyboard row 0 to $4000.
    private const string TestRom = """
        .cpu Z80
                .org 0
                DI
                JP   Start
                .org $38
        Tick:   PUSH AF
                LD   A,[$37E0]          ; reading the latch acknowledges the clock
                LD   A,[$4001]
                INC  A
                LD   [$4001],A
                POP  AF
                EI
                RETI
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
                EI
        Loop:   LD   A,[$3801]
                LD   [$4000],A
                JR   Loop
        Ready:  .byte "READY"
        """;

    /// <summary>
    ///  The test ROM boots, shows READY, takes the 40 Hz interrupt and reads the keyboard.
    /// </summary>
    [TestMethod]
    public void TestRomRunsOnTheMachine()
    {
        Trs80Machine machine = Create(new() { RamKilobytes = 16 });
        machine.Run(Trs80Timing.CyclesPerFrame * 2);
        Text(machine, 0, 6).Should().Be("READY ");

        ulong start = machine.Processor.CycleCount;
        machine.Run(Trs80Timing.CyclesPerTick * 10);
        int ticks = machine.Bus.Peek(0x4001);
        ticks.Should().BeInRange(10, 11);

        machine.Bus.Keyboard.Set(Trs80Key.A, pressed: true);
        machine.Run(200);
        machine.Bus.Peek(0x4000).Should().Be(0x02, "A is row 0, bit 1");
        machine.Processor.CycleCount.Should().Be(start + (ulong)(Trs80Timing.CyclesPerTick * 10) + 200);
    }

    /// <summary>
    ///  ROM, RAM, unmapped space and the Expansion Interface's absence read as the hardware does.
    /// </summary>
    [TestMethod]
    public void MemoryMapFollowsTheConfiguration()
    {
        Trs80Machine small = Create(new() { RamKilobytes = 16, ExpansionInterface = false });
        Trs80Bus bus = small.Bus;
        bus.Read(0x0000).Should().Be(0xF3, "DI");
        bus.Read(0x37EC).Should().Be(0xFF, "no disk controller");
        bus.Write(0x7FFF, 0x5A);
        bus.Read(0x7FFF).Should().Be(0x5A);
        bus.Read(0x8000).Should().Be(0xFF);
        bus.Area(0x8000).Should().Be(Trs80MemoryArea.Unmapped);
        bus.Area(0x3C10).Should().Be(Trs80MemoryArea.Video);
        bus.Area(0x37E0).Should().Be(Trs80MemoryArea.Unmapped);
        bus.Write(0x0000, 0x00);
        bus.Read(0x0000).Should().Be(0xF3, "ROM ignores writes");

        Trs80Machine full = Create(new());
        full.Bus.Write(0xFFFF, 0xA5);
        full.Bus.Read(0xFFFF).Should().Be(0xA5);
        full.Bus.Area(0x37EC).Should().Be(Trs80MemoryArea.ExpansionInterface);
        ((IMachine)full).Id.Should().Be("trs80-model1");
        Action invalid = () => Create(new() { RamKilobytes = 48, ExpansionInterface = false });
        invalid.Should().Throw<ArgumentException>();
    }

    /// <summary>
    ///  A stock machine has no bit 6 in video RAM, which reads as the inverse of bit 5; the modification keeps it.
    /// </summary>
    [TestMethod]
    public void VideoBitSixNeedsTheLowercaseModification()
    {
        Trs80Bus stock = Create(new()).Bus;
        stock.Write(0x3C00, (byte)'A');
        stock.Read(0x3C00).Should().Be((byte)'A');
        stock.Write(0x3C00, (byte)'a');
        stock.Read(0x3C00).Should().Be((byte)'!', "'a' loses bit 6, and bit 5 set reads bit 6 clear");

        Trs80Bus modified = Create(new() { LowercaseModification = true }).Bus;
        modified.Write(0x3C00, (byte)'a');
        modified.Read(0x3C00).Should().Be((byte)'a');
    }

    /// <summary>
    ///  Characters come from the character generator, graphics from bits 0-5, and port $FF bit 3 widens them.
    /// </summary>
    [TestMethod]
    public void VideoRendersCharactersGraphicsAndWideMode()
    {
        Trs80Bus bus = Create(new()).Bus;
        Trs80Video video = bus.Video;
        video.Width.Should().Be(384);
        video.Height.Should().Be(192);
        bus.Write(0x3C00, 0x41);
        bus.Write(0x3C01, 0x80 | 0x01 | 0x20);
        byte[] pixels = new byte[video.Width * video.Height * 4];
        video.Render(pixels, scanned: false);

        // The test font's row r of character c is (c + r) & $3F: $01 then $02 for 'A', bit 5 leftmost.
        Lit(pixels, video, x: 5, y: 0).Should().BeTrue();
        Lit(pixels, video, x: 0, y: 0).Should().BeFalse();
        Lit(pixels, video, x: 4, y: 1).Should().BeTrue();
        Lit(pixels, video, x: 0, y: 8).Should().BeFalse("rows 8-11 are blank");
        Lit(pixels, video, x: 6, y: 0).Should().BeTrue("block 0, top left");
        Lit(pixels, video, x: 9, y: 0).Should().BeFalse("block 1, top right");
        Lit(pixels, video, x: 9, y: 11).Should().BeTrue("block 5, bottom right");

        bus.Out(0x00FF, 0x08);
        video.WideCharacters.Should().BeTrue();
        video.Render(pixels, scanned: false);
        Lit(pixels, video, x: 10, y: 0).Should().BeTrue("'A''s lit pixel 5 spans 10 and 11");
        Lit(pixels, video, x: 11, y: 0).Should().BeTrue();
        Lit(pixels, video, x: 12, y: 0).Should().BeFalse("column 1's graphics are hidden; column 2 is blank");
    }

    /// <summary>
    ///  Scanned rendering shows each character row as it was when the beam reached it.
    /// </summary>
    [TestMethod]
    public void ScannedVideoLatchesRowsAsTheBeamPasses()
    {
        // Clearing the screen takes most of two frames; the third shows READY throughout.
        Trs80Machine machine = Create(new());
        machine.Run(Trs80Timing.CyclesPerFrame * 3);
        Trs80Video video = machine.Bus.Video;
        byte[] scanned = new byte[video.Width * video.Height * 4];
        byte[] live = new byte[scanned.Length];
        video.Render(scanned, scanned: true);
        video.Render(live, scanned: false);
        scanned.Should().Equal(live, "the screen has not changed for a frame");
        video.Frames.Should().Be(3);
    }

    /// <summary>
    ///  With snow, a CPU write while the beam draws a character shows the written byte on that scanline only, and
    ///  the next frame's scanline is clean again.
    /// </summary>
    /// <param name="snow">Whether the machine shows snow.</param>
    [TestMethod]
    [DataRow(data: true)]
    [DataRow(data: false)]
    public void CpuAccessDuringDisplaySnows(bool snow)
    {
        Trs80Bus bus = Create(new() { VideoSnow = snow }).Bus;
        Trs80Video video = bus.Video;
        bus.Write(0x3C05, 0xBF);

        // The first visible scanline starts 36 lines into the frame; its sixth character is drawn at T-state 5.
        int target = (36 * Trs80Timing.CyclesPerLine) + 5;
        while (video.CycleInFrame != target) { bus.Tick(); }
        bus.Write(0x3C10, 0x80);
        byte[] pixels = new byte[video.Width * video.Height * 4];
        video.Render(pixels, scanned: true);
        Lit(pixels, video.Width, x: 5 * 6, y: 0).Should().Be(!snow, "the CPU's $80 is a blank block");
        Lit(pixels, video.Width, x: 5 * 6, y: 1).Should().BeTrue("the next scanline shows the stored $BF");

        for (int cycle = 0; cycle < Trs80Timing.CyclesPerFrame; cycle++) { bus.Tick(); }
        video.Render(pixels, scanned: true);
        Lit(pixels, video.Width, x: 5 * 6, y: 0).Should().BeTrue("the next frame redraws the scanline");
    }

    private static bool Lit(byte[] pixels, int width, int x, int y) => pixels[((y * width) + x) * 4] > 0x80;

    /// <summary>
    ///  Typed characters press their keys, with SHIFT for shifted ones, long enough to be scanned.
    /// </summary>
    [TestMethod]
    public void TypingPressesAndReleasesKeys()
    {
        Trs80Machine machine = Create(new());
        Trs80Keyboard keyboard = machine.Bus.Keyboard;
        ((IMachine)machine).QueueKey((byte)'!');
        machine.Bus.Tick();
        keyboard.IsPressed(Trs80Key.D1).Should().BeTrue();
        keyboard.IsPressed(Trs80Key.Shift).Should().BeTrue();
        machine.Bus.Read(0x3810).Should().Be(0x02, "row 4 holds 1");
        machine.Bus.Read(0x3880).Should().Be(0x01, "row 7 holds SHIFT");
        machine.Bus.Read(0x3890).Should().Be(0x03, "rows 4 and 7 together");
        machine.Run(45 * Trs80Timing.CyclesPerMillisecond);
        keyboard.IsPressed(Trs80Key.D1).Should().BeFalse();
        keyboard.Type(0x7F).Should().BeFalse("DEL has no key");
    }

    /// <summary>
    ///  The reset button raises one non-maskable interrupt, taken even with interrupts disabled, which runs the
    ///  handler at <c>$0066</c> once.
    /// </summary>
    [TestMethod]
    public void ResetButtonRaisesOneNonMaskableInterrupt()
    {
        const string Source = """
            .cpu Z80
                    .org 0
                    DI
                    LD   SP,$5000
            Spin:   JR   Spin
                    .org $66
                    LD   A,[$4000]
                    INC  A
                    LD   [$4000],A
                    RETN
            """;

        Trs80Machine machine = Create(new() { RamKilobytes = 16 }, AssembleRom(Source));
        machine.Run(1000);
        machine.Bus.Peek(0x4000).Should().Be(0);
        machine.Reset();
        bool handled = false;
        for (int cycle = 0; cycle < 100 && !handled; cycle++)
        {
            machine.StepCycle();
            handled = machine.Processor.IsInstructionBoundary
                && machine.Processor.Registers.PC == Trs80Machine.ResetHandler;
        }

        handled.Should().BeTrue("the press reaches the handler within an instruction and the interrupt's entry");
        machine.Run(1000);
        machine.Bus.Peek(0x4000).Should().Be(1, "one press runs the handler once");
        machine.Processor.Registers.PC.Should().Be(4, "RETN returns to the spin loop");
    }

    /// <summary>
    ///  Assembles the test ROM into a 12K Level II-sized image.
    /// </summary>
    /// <param name="source">The ROM's source.</param>
    /// <returns>The image.</returns>
    internal static byte[] AssembleRom(string source)
    {
        AssemblyResult result = new NativeAssembler().Assemble(
            new AssemblySource(source, "rom.asm"),
            new AssemblyOptions(Z80Isa.Name, 0, 0x3000));

        result.Diagnostics.Should().BeEmpty();
        return result.Sections[0].Bytes.ToArray();
    }

    /// <summary>
    ///  Creates a machine with the test ROM and a font whose row r of character c is (c + r) &amp; $3F.
    /// </summary>
    /// <param name="configuration">The configuration.</param>
    /// <param name="rom">A ROM to use instead.</param>
    /// <returns>The machine.</returns>
    internal static Trs80Machine Create(Trs80Configuration configuration, byte[]? rom = null)
    {
        byte[] font = new byte[Trs80Roms.CharacterGeneratorSize];
        for (int index = 0; index < font.Length; index++) { font[index] = (byte)(((index >> 3) + (index & 7)) & 0x3F); }
        return new(configuration, new Trs80Roms(rom ?? AssembleRom(TestRom), font));
    }

    private static string Text(Trs80Machine machine, int offset, int length) =>
        new([.. Enumerable.Range(offset, length).Select(index => (char)machine.Bus.Video.Read(index))]);

    private static bool Lit(byte[] pixels, Trs80Video video, int x, int y) => pixels[((y * video.Width) + x) * 4] > 0x80;
}
