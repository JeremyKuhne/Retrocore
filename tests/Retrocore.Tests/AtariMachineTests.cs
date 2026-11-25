// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Atari;

namespace Retrocore.Tests;

/// <summary>
///  The Atari 400 and 800 on their own ROMs, which need the dumps: MAME's <c>a800</c> set, unzipped, in
///  <c>RETROCORE_ATARI_ROMS</c> or <c>%USERPROFILE%\Retrocore\atari8-roms\extract\a800</c>, and Atari BASIC in
///  <c>%USERPROFILE%\Retrocore\atari8-media\basic</c>.
/// </summary>
[TestClass]
public class AtariMachineTests
{
    /// <summary>
    ///  Gets the folder holding MAME's <c>a800</c> set's chips.
    /// </summary>
    internal static string RomDirectory => Environment.GetEnvironmentVariable("RETROCORE_ATARI_ROMS")
        ?? Path.Join(ExternalTestData.Root, "atari8-roms", "extract", "a800");

    /// <summary>
    ///  Gets the folder holding Atari BASIC's three cartridges, <c>basic-reva.rom</c> to <c>basic-revc.rom</c>.
    /// </summary>
    internal static string BasicDirectory => Path.Join(ExternalTestData.Root, "atari8-media", "basic");

    /// <summary>
    ///  Makes a machine at power-on, or marks the test inconclusive without the dumps.
    /// </summary>
    /// <param name="model">The model.</param>
    /// <param name="basic">The BASIC revision to put in the left slot, or null for none.</param>
    /// <param name="standard">The television standard.</param>
    /// <param name="chip">GTIA or CTIA.</param>
    /// <returns>The machine.</returns>
    internal static AtariMachine Machine(
        AtariModel model = AtariModel.Atari800,
        char? basic = null,
        AtariVideoStandard standard = AtariVideoStandard.Ntsc,
        AtariGraphicsChip chip = AtariGraphicsChip.Gtia)
    {
        string directory = RomDirectory;
        if (standard == AtariVideoStandard.Pal)
        {
            directory = Path.Join(Path.GetDirectoryName(RomDirectory), "a800pal");
        }

        if (!File.Exists(Path.Join(directory, "co12399b.rom")))
        {
            Assert.Inconclusive("Set RETROCORE_ATARI_ROMS to a folder with MAME's a800 set unzipped.");
        }

        AtariCartridge? cartridge = null;
        if (basic is char revision)
        {
            string path = Path.Join(BasicDirectory, $"basic-rev{char.ToLowerInvariant(revision)}.rom");
            if (!File.Exists(path)) { Assert.Inconclusive($"Atari BASIC isn't at {path}."); }
            cartridge = AtariCartridge.Load(path);
        }

        return new(AtariRoms.LoadFromDirectory(directory), model, left: cartridge, standard: standard, chip: chip);
    }

    /// <summary>
    ///  Runs until a line of the screen matches, for up to some emulated seconds.
    /// </summary>
    /// <param name="machine">The machine.</param>
    /// <param name="match">The test for a line.</param>
    /// <param name="seconds">The most emulated seconds to wait.</param>
    /// <returns>The screen.</returns>
    internal static string[] RunUntil(AtariMachine machine, Func<string, bool> match, double seconds = 10)
    {
        for (int tenth = 0; tenth < seconds * 10; tenth++)
        {
            machine.Run(TimeSpan.FromSeconds(0.1));
            string[] screen = machine.ReadTextScreen();
            if (screen.Any(match)) { return screen; }
        }

        return machine.ReadTextScreen();
    }

    /// <summary>
    ///  Runs until BASIC's <c>READY</c>.
    /// </summary>
    /// <param name="machine">The machine.</param>
    /// <returns>The screen.</returns>
    internal static string[] RunToReady(AtariMachine machine) => RunUntil(machine, line => line.Trim() == "READY");

    /// <summary>
    ///  Types text and waits until the keyboard is done, and half a second more.
    /// </summary>
    /// <param name="machine">The machine.</param>
    /// <param name="text">The text, with carriage returns for RETURN.</param>
    internal static void Type(AtariMachine machine, string text)
    {
        foreach (char c in text) { machine.Keyboard.Type((byte)c).Should().BeTrue($"the Atari has a key for {c}"); }
        while (machine.Keyboard.IsTyping) { machine.Run(TimeSpan.FromSeconds(0.05)); }
        machine.Run(TimeSpan.FromSeconds(0.5));
    }

    private static string Text(string[] screen) => string.Join('\n', screen.Select(line => line.TrimEnd()));

    /// <summary>
    ///  With no cartridge and no disk drive, each model gives up on booting a disk and opens Memo Pad.
    /// </summary>
    /// <param name="model">The model.</param>
    [TestMethod]
    [DataRow(AtariModel.Atari800)]
    [DataRow(AtariModel.Atari400)]
    public void PowerOnWithoutCartridgeOpensMemoPad(AtariModel model)
    {
        AtariMachine machine = Machine(model);
        string[] screen = RunUntil(machine, line => line.Contains("MEMO PAD", StringComparison.Ordinal), seconds: 20);
        screen.Should().Contain(line => line.Contains("ATARI COMPUTER - MEMO PAD", StringComparison.Ordinal), Text(screen));
    }

    /// <summary>
    ///  With BASIC, each revision starts to <c>READY</c>.
    /// </summary>
    /// <param name="revision">The BASIC revision.</param>
    [TestMethod]
    [DataRow('A')]
    [DataRow('B')]
    [DataRow('C')]
    public void PowerOnWithBasicIsReady(char revision)
    {
        AtariMachine machine = Machine(basic: revision);
        string[] screen = RunToReady(machine);
        screen.Should().Contain(line => line.Trim() == "READY", Text(screen));
    }

    /// <summary>
    ///  A typed program runs.
    /// </summary>
    [TestMethod]
    public void TypedProgramRuns()
    {
        AtariMachine machine = Machine(basic: 'C');
        RunToReady(machine);
        Type(machine, "10 FOR I=1 TO 3:PRINT I*7;\"X\":NEXT I\r");
        Type(machine, "RUN\r");
        string[] screen = machine.ReadTextScreen();
        string text = Text(screen);
        screen.Should().Contain(line => line.Trim() == "7X", text);
        screen.Should().Contain(line => line.Trim() == "21X", text);
    }

    /// <summary>
    ///  Each of BASIC's graphics modes draws: a full-screen line in colour 1 shows that colour register's colour, on
    ///  the background, and GTIA modes 9 to 11 show their 16 shades or hues.
    /// </summary>
    /// <param name="mode">The <c>GRAPHICS</c> mode.</param>
    [TestMethod]
    [DataRow(1)]
    [DataRow(2)]
    [DataRow(3)]
    [DataRow(4)]
    [DataRow(5)]
    [DataRow(6)]
    [DataRow(7)]
    [DataRow(8)]
    [DataRow(9)]
    [DataRow(10)]
    [DataRow(11)]
    public void GraphicsModesDraw(int mode)
    {
        AtariMachine machine = Machine(basic: 'C');
        RunToReady(machine);
        string draw = mode switch
        {
            1 or 2 => "? #6;\"ATARI\"",
            >= 9 => "FOR I=1 TO 8:COLOR I:PLOT I*4,0:DRAWTO I*4,20:NEXT I",
            _ => "COLOR 1:PLOT 0,0:DRAWTO 20,0"
        };

        Type(machine, $"10 GR.{mode}+16:{draw}\r");
        Type(machine, "20 GOTO 20\r");
        Type(machine, "RUN\r");
        machine.Run(TimeSpan.FromSeconds(2));
        machine.RunFrame();
        HashSet<uint> colors = Colors(machine);
        uint background = machine.Gtia.Rgba(machine.Gtia.Color(8));
        if (mode != 11)
        {
            // Mode 11 forces luminance 0 for pixel value 0, so COLBK's own colour never shows.
            colors.Should().Contain(background, "the background shows");
        }

        if (mode >= 9)
        {
            colors.Count.Should().BeGreaterThanOrEqualTo(5, "GTIA modes show many shades or hues");
        }
        else
        {
            // Text modes 1 and 2 draw ATARI in PF0; the bitmap modes' colour 1 is PF0 too, except 6 and 8 (PF1
            // luminance on PF2 in mode 8, PF0 in mode 6).
            byte register = mode == 8 ? (byte)((machine.Gtia.Color(6) & 0xF0) | (machine.Gtia.Color(5) & 0x0E)) : machine.Gtia.Color(4);
            colors.Should().Contain(machine.Gtia.Rgba(register), $"colour 1 shows in mode {mode}");
        }
    }

    /// <summary>
    ///  The CTIA ignores <c>PRIOR</c> bits 6 and 7, so <c>GRAPHICS 9</c> shows as mode F's two luminances of one hue.
    /// </summary>
    [TestMethod]
    public void CtiaHasNoGtiaModes()
    {
        AtariMachine machine = Machine(basic: 'C', chip: AtariGraphicsChip.Ctia);
        RunToReady(machine);
        Type(machine, "10 GR.9+16:FOR I=1 TO 8:COLOR I:PLOT I*4,0:DRAWTO I*4,20:NEXT I\r");
        Type(machine, "20 GOTO 20\r");
        Type(machine, "RUN\r");
        machine.Run(TimeSpan.FromSeconds(2));
        machine.RunFrame();
        Colors(machine).Count.Should().BeLessThanOrEqualTo(3);
    }

    /// <summary>
    ///  Players show in their colours over the playfield, and GTIA latches their collisions.
    /// </summary>
    [TestMethod]
    public void PlayersShowAndCollide()
    {
        AtariMachine machine = Machine(basic: 'C');
        RunToReady(machine);

        // Players 0 and 1, eight clocks wide, overlapping by four, from the CPU's graphics registers.
        Type(machine, "POKE 704,68:POKE 705,200:POKE 53261,255:POKE 53262,255:POKE 53248,128:POKE 53249,132:POKE 53278,0\r");
        machine.Run(TimeSpan.FromSeconds(0.2));
        HashSet<uint> colors = Colors(machine);
        colors.Should().Contain(machine.Gtia.Rgba(68), "player 0 shows");
        colors.Should().Contain(machine.Gtia.Rgba(200), "player 1 shows where player 0 doesn't");
        (machine.Gtia.Read(0x0C) & 2).Should().Be(2, "P0PL shows player 1");
        (machine.Gtia.Read(0x0D) & 1).Should().Be(1, "P1PL shows player 0");
    }

    /// <summary>
    ///  <c>SOUND</c> sets POKEY's channel and the machine makes a tone.
    /// </summary>
    [TestMethod]
    public void SoundPlays()
    {
        AtariMachine machine = Machine(basic: 'C');
        RunToReady(machine);
        Type(machine, "SOUND 0,121,10,8\r");
        machine.Bus.Pokey.Frequency(0).Should().Be(121);
        machine.Bus.Pokey.ChannelControl(0).Should().Be(0xA8);

        PeakAudioSink sink = new();
        machine.Audio.Sink = sink;
        machine.Run(TimeSpan.FromSeconds(0.1));
        machine.Audio.Flush();
        sink.Peak.Should().BeGreaterThan(0.05f, "a square wave swings");
    }

    /// <summary>
    ///  The console keys read through <c>CONSOL</c>, the joystick through the PIA and its trigger through GTIA.
    /// </summary>
    [TestMethod]
    public void ConsoleKeysAndJoystickRead()
    {
        AtariMachine machine = Machine(basic: 'C');
        RunToReady(machine);
        machine.Keyboard.ConsoleKeys = AtariConsoleKeys.Start;
        machine.Bus.SetJoystick(0, 8);
        machine.Gtia.Triggers = 1;
        Type(machine, "? PEEK(53279);\",\";STICK(0);\",\";STRIG(0)\r");
        string[] screen = machine.ReadTextScreen();
        screen.Should().Contain(line => line.Trim() == "6,7,0", Text(screen));
    }

    /// <summary>
    ///  BREAK stops a running program.
    /// </summary>
    [TestMethod]
    public void BreakStopsAProgram()
    {
        AtariMachine machine = Machine(basic: 'C');
        RunToReady(machine);
        Type(machine, "10 GOTO 10\rRUN\r");
        machine.Keyboard.Break = true;
        machine.Run(TimeSpan.FromSeconds(0.1));
        machine.Keyboard.Break = false;
        string[] screen = RunUntil(machine, line => line.Contains("STOPPED", StringComparison.Ordinal), seconds: 2);
        screen.Should().Contain(line => line.Trim() == "STOPPED  AT LINE 10", Text(screen));
    }

    /// <summary>
    ///  SYSTEM RESET is an NMI on the 400 and 800: the OS warm starts and BASIC keeps its program.
    /// </summary>
    [TestMethod]
    public void SystemResetKeepsTheProgram()
    {
        AtariMachine machine = Machine(basic: 'C');
        RunToReady(machine);
        Type(machine, "10 REM KEPT\r");
        machine.Keyboard.SystemReset = true;
        machine.Run(TimeSpan.FromSeconds(0.1));
        machine.Keyboard.SystemReset = false;
        RunToReady(machine);
        Type(machine, "LIST\r");
        string[] screen = machine.ReadTextScreen();
        screen.Should().Contain(line => line.Trim() == "10 REM KEPT", Text(screen));
    }

    /// <summary>
    ///  The PAL machine: 312 lines, GTIA's <c>PAL</c> register reads 1, and BASIC starts.
    /// </summary>
    [TestMethod]
    public void PalMachineRuns()
    {
        AtariMachine machine = Machine(basic: 'C', standard: AtariVideoStandard.Pal);
        machine.CyclesPerFrame.Should().Be(35_568);
        RunToReady(machine);
        Type(machine, "? PEEK(53268)\r");
        string[] screen = machine.ReadTextScreen();
        screen.Should().Contain(line => line.Trim() == "1", Text(screen));
    }

    // The colours in the frame.
    private static HashSet<uint> Colors(AtariMachine machine)
    {
        byte[] frame = machine.RenderBitmap();
        HashSet<uint> colors = [];
        for (int i = 0; i < frame.Length; i += 4) { colors.Add(BitConverter.ToUInt32(frame, i)); }
        return colors;
    }
}
