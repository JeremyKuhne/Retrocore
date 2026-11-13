// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug;
using Retrocore.Machines;
using Retrocore.Machines.Apple1;
using Retrocore.Machines.Devices;

namespace Retrocore.Tests;

/// <summary>
///  The Apple-1 running the SDK's Monitor and cassette interface sources: the PIA, the terminal, the keyboard, the
///  memory map and the cassette.
/// </summary>
[TestClass]
public sealed class Apple1MachineTests
{
    private static Apple1Roms? s_roms;

    /// <summary>
    ///  Gets the ROMs assembled from the SDK's sources, once.
    /// </summary>
    internal static Apple1Roms Roms => s_roms ??= new(
        Apple1RomTests.Image(Apple1SdkModules.AssembleMonitor(Apple1RomTests.Source("WozMonitor.asm"))),
        Apple1RomTests.Image(Apple1SdkModules.AssembleCharacterGenerator(Apple1RomTests.Source("CharacterGenerator.asm"))),
        Apple1RomTests.Image(Apple1SdkModules.AssembleCassette(Apple1RomTests.Source("Aci.asm"))));

    /// <summary>
    ///  Power-up runs the Monitor, which sets up the PIA and shows its backslash prompt.
    /// </summary>
    [TestMethod]
    public void MonitorShowsItsPromptAtPowerUp()
    {
        Apple1Machine machine = Boot();
        machine.Terminal.Line(0).TrimEnd().Should().Be("\\");
        machine.Terminal.CursorRow.Should().Be(1);
        machine.Terminal.CursorColumn.Should().Be(0);
        machine.Bus.Pia.ControlA.Should().Be(0x27, "the Monitor writes $A7, and the flags are read-only");
        (machine.Bus.Pia.ControlB & 0x3F).Should().Be(0x27);
        ((IMachine)machine).Id.Should().Be("apple1");
    }

    /// <summary>
    ///  The Monitor examines a range of memory, here its own first eight bytes.
    /// </summary>
    [TestMethod]
    public void MonitorExaminesMemory()
    {
        Apple1Machine machine = Boot();
        TypeLine(machine, "FF00.FF07");
        // The Return that ends the line and the one the Monitor sends before the address each fill a line, so a
        // blank line comes between.
        Screen(machine)[..5].Should().Equal("\\", "FF00.FF07", "", "FF00: D8 58 A0 7F 8C 12 D0 A9", "");
        machine.Terminal.CursorRow.Should().Be(4);
    }

    /// <summary>
    ///  The Monitor stores a program and runs it; the program prints through the Monitor's ECHO and returns to its
    ///  command line.
    /// </summary>
    [TestMethod]
    public void MonitorStoresAndRunsAProgram()
    {
        Apple1Machine machine = Boot();

        // LDA #'H' | $80, JSR ECHO, LDA #'I' | $80, JSR ECHO, JMP GETLINE
        TypeLine(machine, "300: A9 C8 20 EF FF A9 C9 20 EF FF 4C 1F FF");
        machine.Bus.Peek(0x300).Should().Be(0xA9);
        machine.Bus.Peek(0x30C).Should().Be(0xFF);
        TypeLine(machine, "300R");
        // A store line first examines its address, showing the byte it replaces.
        // The line wraps at 40 characters.
        Screen(machine)[1..9].Should().Equal("300: A9 C8 20 EF FF A9 C9 20 EF FF 4C 1F", " FF", "", "0300: 00", "300R", "", "0300: A9HI", "");
        machine.Terminal.CursorRow.Should().Be(8);
    }

    /// <summary>
    ///  The terminal takes one character a frame, as the beam passes the cursor.
    /// </summary>
    [TestMethod]
    public void TerminalTakesOneCharacterAFrame()
    {
        Apple1Machine machine = Boot();

        // LDY #120; loop: LDA #'A' | $80, JSR ECHO, DEY, BNE loop; JMP GETLINE
        TypeLine(machine, "300: A0 78 A9 C1 20 EF FF 88 D0 F8 4C 1F FF");
        machine.Keyboard.Type("300R\n");
        RunUntil(machine, () => machine.Terminal.Line(7).StartsWith("0300: A0", StringComparison.Ordinal));
        ulong start = machine.Terminal.Frames;
        RunUntil(machine, () => machine.Terminal.CursorRow == 11);
        int frames = (int)(machine.Terminal.Frames - start);
        machine.Terminal.Line(8).Should().Be(new string('A', 40));
        frames.Should().BeInRange(110, 122, "120 characters take about two seconds");
    }

    /// <summary>
    ///  The terminal stores six bits a character: lowercase shows as uppercase, and control characters other than
    ///  Return are dropped.
    /// </summary>
    [TestMethod]
    public void TerminalShowsSixBitCharacters()
    {
        Apple1Terminal.Code('A').Should().Be(1);
        Apple1Terminal.Code('a').Should().Be(1);
        Apple1Terminal.Code('@').Should().Be(0);
        Apple1Terminal.Code(' ').Should().Be(32);
        Apple1Terminal.Code('?').Should().Be(63);
        Apple1Terminal.Code('A' | 0x80).Should().Be(1);
        Apple1Terminal.Ascii(1).Should().Be('A');
        Apple1Terminal.Ascii(33).Should().Be('!');

        Apple1Machine machine = Boot();

        // Prints "ab", a bell and "c", then returns to the Monitor.
        TypeLine(machine, "300: A9 E1 20 EF FF A9 E2 20 EF FF A9 87 20 EF FF A9 E3 20 EF FF 4C 1F FF");
        TypeLine(machine, "300R");
        Screen(machine).Should().Contain("0300: A9ABC");
    }

    /// <summary>
    ///  The keyboard types uppercase, and holds each key until the program has read the last.
    /// </summary>
    [TestMethod]
    public void KeyboardWaitsForEachKeyToBeRead()
    {
        Apple1Machine machine = Boot();
        machine.Keyboard.Type("ff00");
        machine.Keyboard.Pending.Should().Be(4);
        machine.Run(Apple1Timing.CyclesPerFrame * 10);
        machine.Keyboard.Pending.Should().Be(0);
        machine.Terminal.Line(1).TrimEnd().Should().Be("FF00");
        machine.Bus.Peek(0x200).Should().Be((byte)('F' | 0x80));
    }

    /// <summary>
    ///  The memory map: RAM, the high bank, the PIA and the Monitor through their mirrors, and the cassette
    ///  interface.
    /// </summary>
    [TestMethod]
    public void MemoryMapDecodesAsTheBoardDoes()
    {
        Apple1Machine machine = new(new() { RamKilobytes = 8 }, Roms);
        Apple1Bus bus = machine.Bus;
        bus.Area(0x0000).Should().Be(Apple1MemoryArea.Ram);
        bus.Area(0x1FFF).Should().Be(Apple1MemoryArea.Ram);
        bus.Area(0x2000).Should().Be(Apple1MemoryArea.Unmapped);
        bus.Area(0xE000).Should().Be(Apple1MemoryArea.Ram);
        bus.Area(0xEFFF).Should().Be(Apple1MemoryArea.Ram);
        bus.Area(0xC000).Should().Be(Apple1MemoryArea.CassetteInterface);
        bus.Area(0xC1FF).Should().Be(Apple1MemoryArea.CassetteRom);
        bus.Area(0xD010).Should().Be(Apple1MemoryArea.Pia);
        bus.Area(0xD0F3).Should().Be(Apple1MemoryArea.Pia);
        bus.Area(0xD000).Should().Be(Apple1MemoryArea.Unmapped);
        bus.Area(0xF000).Should().Be(Apple1MemoryArea.Monitor);

        bus.Read(0xA123).Should().Be(0xA1, "nothing drives the bus, which holds the address's high byte");
        bus.Read(0xF000).Should().Be(0xD8, "the Monitor's PROMs see only the low byte");
        bus.Read(0xFFFC).Should().Be(0x00);
        bus.Read(0xFFFD).Should().Be(0xFF);
        bus.Read(0xC100).Should().Be(0xA9);
        bus.Write(0xE123, 0x5A);
        bus.Read(0xE123).Should().Be(0x5A);

        // Without the cards and the bank, those addresses are empty.
        Apple1Machine bare = new(new() { HighRam = false, CassetteInterface = false }, Roms);
        bare.Bus.Area(0x1000).Should().Be(Apple1MemoryArea.Unmapped);
        bare.Bus.Area(0xE000).Should().Be(Apple1MemoryArea.Unmapped);
        bare.Bus.Area(0xC100).Should().Be(Apple1MemoryArea.Unmapped);
        bare.Devices.Should().BeEmpty();
        machine.Devices.Should().ContainSingle().Which.Kind.Should().Be(DeviceKind.TapeDrive);

        Action badRam = () => _ = new Apple1Machine(new() { RamKilobytes = 16 }, Roms);
        badRam.Should().Throw<ArgumentException>();
        Action noProm = () => _ = new Apple1Machine(new(), new(Roms.Monitor.Span, Roms.CharacterGenerator.Span));
        noProm.Should().Throw<ArgumentException>();
    }

    /// <summary>
    ///  RESET restarts the Monitor and keeps RAM and the screen; CLEAR SCREEN blanks the screen.
    /// </summary>
    [TestMethod]
    public void ResetKeepsMemoryAndClearScreenBlanksIt()
    {
        Apple1Machine machine = Boot();
        TypeLine(machine, "300: 12 34");
        machine.Reset();
        machine.Run(Apple1Timing.CyclesPerFrame * 4);
        machine.Bus.Peek(0x301).Should().Be(0x34);
        Screen(machine)[..6].Should().Equal("\\", "300: 12 34", "", "0300: 00", "\\", "");

        machine.ClearScreen();
        machine.Terminal.Line(0).Trim().Should().BeEmpty();
        machine.Terminal.CursorRow.Should().Be(0);
        TypeLine(machine, "301");
        Screen(machine)[..3].Should().Equal("301", "", "0301: 34");
    }

    /// <summary>
    ///  Output past the last line scrolls the screen up.
    /// </summary>
    [TestMethod]
    public void TerminalScrollsAtTheBottom()
    {
        Apple1Machine machine = Boot();
        TypeLine(machine, "FF00.FFFF", seconds: 30);
        machine.Terminal.CursorRow.Should().Be(Apple1Terminal.Rows - 1);
        machine.Terminal.Line(Apple1Terminal.Rows - 2).TrimEnd().Should().Be("FFF8: 00 00 00 0F 00 FF 00 00");
    }

    /// <summary>
    ///  The video renders the 2513's dots, with the cursor's @ blinking.
    /// </summary>
    [TestMethod]
    public void VideoRendersTheCharacters()
    {
        Apple1Machine machine = Boot();
        Apple1Terminal video = machine.Terminal;
        video.Width.Should().Be(280);
        video.Height.Should().Be(192);
        byte[] pixels = new byte[video.Width * video.Height * 4];
        video.Render(pixels, scanned: true);

        // The backslash's first dot is on its second row, in the leftmost of its five columns.
        Lit(pixels, video.Width, x: 1, y: 1).Should().BeTrue();
        Lit(pixels, video.Width, x: 2, y: 1).Should().BeFalse();
        Lit(pixels, video.Width, x: 1, y: 0).Should().BeFalse();

        // The cursor's @ at the start of line 1 shows in one half of the blink and not the other.
        bool shown = machine.Terminal.CursorShown;
        Lit(pixels, video.Width, x: 2, y: 8).Should().Be(shown);
        machine.Run(Apple1Timing.CyclesPerFrame * 16);
        machine.Terminal.CursorShown.Should().Be(!shown);
        video.Render(pixels, scanned: true);
        Lit(pixels, video.Width, x: 2, y: 8).Should().Be(!shown);
    }

    /// <summary>
    ///  The cassette interface writes memory to tape and reads it back, through a WAV file.
    /// </summary>
    [TestMethod]
    public void CassetteRoundTripsMemory()
    {
        Apple1Machine machine = Boot();
        TypeLine(machine, "300: 00 01 7F 80 FF 55 AA 12 34 56 78 9A BC DE F0 C3");

        Apple1Tape recording = new();
        Apple1CassetteDrive drive = machine.CassetteDrive ?? throw new InvalidOperationException("No cassette interface.");
        drive.Record(recording, "test.wav");
        drive.Activity.Should().Be(DeviceActivity.Writing);
        TypeLine(machine, "C100R");
        Screen(machine).Should().Contain("C100: A9*", "the Monitor examines C100 before running it");
        TypeLine(machine, "300.30FW", seconds: 20);
        drive.Eject().Should().BeSameAs(recording);

        // Leader, sync, then 16 bytes of two half cycles a bit.
        recording.HalfCycles.Count.Should().BeGreaterThan(256 * 0x40);
        byte[] wave = recording.ToWave();
        Apple1Tape played = Apple1Tape.FromWave(wave);
        played.HalfCycles.Count.Should().BeInRange(recording.HalfCycles.Count - 2, recording.HalfCycles.Count + 1);

        // Clear the bytes, then read them back from the tape.
        TypeLine(machine, "\u001B");
        TypeLine(machine, "300: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00");
        drive.Play(played, "test.wav");
        TypeLine(machine, "C100R");
        TypeLine(machine, "300.30FR", seconds: 20);
        Bytes(machine, 0x300, 16).Should().Equal(0x00, 0x01, 0x7F, 0x80, 0xFF, 0x55, 0xAA, 0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC, 0xDE, 0xF0, 0xC3);
    }

    /// <summary>
    ///  A tape made from bytes reads into memory with the cassette interface's R command.
    /// </summary>
    [TestMethod]
    public void CassetteReadsATapeMadeFromData()
    {
        Apple1Machine machine = Boot();
        byte[] data = [.. Enumerable.Range(0, 64).Select(value => (byte)(value * 37))];
        Apple1CassetteDrive drive = machine.CassetteDrive ?? throw new InvalidOperationException("No cassette interface.");
        drive.Play(Apple1Tape.FromData(data), "data");
        TypeLine(machine, "C100R");
        TypeLine(machine, "E000.E03FR", seconds: 20);
        Bytes(machine, 0xE000, 64).Should().Equal(data);
        Screen(machine).Last(line => line.Length > 0).Should().Be("\\", "Return in the cassette line goes back to the Monitor");
    }

    /// <summary>
    ///  Makes a machine with the default configuration and runs it until the Monitor waits for a key.
    /// </summary>
    /// <returns>The machine.</returns>
    internal static Apple1Machine Boot()
    {
        Apple1Machine machine = new(new(), Roms);
        machine.Run(Apple1Timing.CyclesPerFrame * 4);
        return machine;
    }

    /// <summary>
    ///  Types a line and runs until the program has read it and the terminal has caught up.
    /// </summary>
    /// <param name="machine">The machine.</param>
    /// <param name="line">The line, without its Return.</param>
    /// <param name="seconds">The most seconds to run for.</param>
    internal static void TypeLine(Apple1Machine machine, string line, int seconds = 5)
    {
        machine.Keyboard.Type(line + "\n");
        RunUntil(machine, () => machine.Keyboard.Pending == 0, seconds);

        // The Monitor waits for a key in NEXTCHAR once the line has run.
        RunUntil(machine, () => machine.Processor.Registers.ProgramCounter is >= 0xFF29 and < 0xFF2E or >= 0xC10D and < 0xC112, seconds);
        machine.Run(Apple1Timing.CyclesPerFrame * 2);
    }

    private static void RunUntil(Apple1Machine machine, Func<bool> done, int seconds = 5)
    {
        long limit = (long)seconds * Apple1Timing.ClockHertz;
        for (long cycle = 0; !done(); cycle += Apple1Timing.CyclesPerLine)
        {
            cycle.Should().BeLessThan(limit, "the machine should get there within {0} seconds", seconds);
            machine.Run(Apple1Timing.CyclesPerLine);
        }
    }

    private static string[] Screen(Apple1Machine machine) =>
        [.. Enumerable.Range(0, Apple1Terminal.Rows).Select(row => machine.Terminal.Line(row).TrimEnd())];

    private static byte[] Bytes(Apple1Machine machine, ushort address, int count) =>
        [.. Enumerable.Range(address, count).Select(at => machine.Bus.Peek((ushort)at))];

    private static bool Lit(byte[] pixels, int width, int x, int y) => pixels[((y * width) + x) * 4] > 0x80;
}
