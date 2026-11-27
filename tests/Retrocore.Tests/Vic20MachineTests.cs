// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Chips;
using Retrocore.Machines.Commodore;
using Retrocore.Machines.Commodore.Vic20;

namespace Retrocore.Tests;

/// <summary>
///  The VIC-20 on its own ROMs, which need the dumps: MAME's <c>vic20</c> and <c>vic20p</c> sets, unzipped, in
///  <c>RETROCORE_VIC20_ROMS</c> (a folder holding them) or <c>%USERPROFILE%\Retrocore\vic20-roms\extract</c>.
/// </summary>
[TestClass]
public class Vic20MachineTests
{
    /// <summary>
    ///  Gets the folder holding each MAME set's chips in a folder named for the set.
    /// </summary>
    internal static string RomRoot => Environment.GetEnvironmentVariable("RETROCORE_VIC20_ROMS")
        ?? Path.Join(ExternalTestData.Root, "vic20-roms", "extract");

    /// <summary>
    ///  Gets the folder of a standard's MAME set.
    /// </summary>
    /// <param name="standard">The standard.</param>
    /// <returns>The folder.</returns>
    internal static string RomDirectory(VicVideoStandard standard) =>
        Path.Join(RomRoot, standard == VicVideoStandard.Ntsc ? "vic20" : "vic20p");

    /// <summary>
    ///  Makes a machine at power-on, or marks the test inconclusive without the dumps.
    /// </summary>
    /// <param name="standard">The video standard.</param>
    /// <param name="expansion">The expansion RAM.</param>
    /// <param name="cartridge">A cartridge, or null.</param>
    /// <returns>The machine.</returns>
    internal static Vic20Machine Machine(
        VicVideoStandard standard = VicVideoStandard.Ntsc,
        Vic20Expansion expansion = Vic20Expansion.None,
        Vic20Cartridge? cartridge = null)
    {
        string directory = RomDirectory(standard);
        string[] chips = ["901486-01.ue11", Vic20Roms.KernalFile(standard), "901460-03.ud7"];
        if (!chips.All(file => File.Exists(Path.Join(directory, file))))
        {
            Assert.Inconclusive("Set RETROCORE_VIC20_ROMS to a folder with MAME's vic20 and vic20p sets unzipped.");
        }

        return new(Vic20Roms.LoadFromDirectory(directory, standard), standard, expansion, cartridge);
    }

    /// <summary>
    ///  Runs until the screen shows <c>READY.</c>, for up to ten emulated seconds.
    /// </summary>
    /// <param name="machine">The machine.</param>
    /// <returns>The screen.</returns>
    internal static string[] RunToReady(Vic20Machine machine)
    {
        for (int tenth = 0; tenth < 100; tenth++)
        {
            machine.Run(TimeSpan.FromSeconds(0.1));
            string[] screen = machine.ReadTextScreen();
            if (screen.Any(line => line.StartsWith("READY.", StringComparison.Ordinal))) { return screen; }
        }

        return machine.ReadTextScreen();
    }

    /// <summary>
    ///  Types text and waits until the keyboard is done, and half a second more.
    /// </summary>
    /// <param name="machine">The machine.</param>
    /// <param name="text">The text, with carriage returns for RETURN.</param>
    internal static void Type(Vic20Machine machine, string text)
    {
        foreach (char c in text) { machine.Keyboard.Type((byte)c).Should().BeTrue($"the VIC-20 has a key for {c}"); }
        while (machine.Keyboard.IsTyping) { machine.Run(TimeSpan.FromSeconds(0.05)); }
        machine.Run(TimeSpan.FromSeconds(0.5));
    }

    /// <summary>
    ///  Both standards start with the banner and the bytes free for each expansion. With RAM in block 1 the kernal
    ///  starts BASIC at <c>$1201</c>, past the screen it moves to <c>$1000</c>, so the 3K is not counted.
    /// </summary>
    /// <param name="standard">The video standard.</param>
    /// <param name="expansion">The expansion RAM.</param>
    /// <param name="free">The bytes free line.</param>
    [TestMethod]
    [DataRow(VicVideoStandard.Ntsc, Vic20Expansion.None, "3583 BYTES FREE")]
    [DataRow(VicVideoStandard.Pal, Vic20Expansion.None, "3583 BYTES FREE")]
    [DataRow(VicVideoStandard.Ntsc, Vic20Expansion.Ram3K, "6655 BYTES FREE")]
    [DataRow(VicVideoStandard.Ntsc, Vic20Expansion.Ram8K, "11775 BYTES FREE")]
    [DataRow(VicVideoStandard.Pal, Vic20Expansion.Ram16K, "19967 BYTES FREE")]
    [DataRow(VicVideoStandard.Ntsc, Vic20Expansion.Ram24K, "28159 BYTES FREE")]
    [DataRow(VicVideoStandard.Ntsc, Vic20Expansion.All, "28159 BYTES FREE")]
    public void BootsToReady(VicVideoStandard standard, Vic20Expansion expansion, string free)
    {
        Vic20Machine machine = Machine(standard, expansion);
        string[] screen = RunToReady(machine);
        string text = string.Join('\n', screen);
        screen.Should().Contain(line => line.Trim() == "**** CBM BASIC V2 ****", text);
        screen.Should().Contain(line => line.Trim() == free, text);
        screen.Should().Contain(line => line.StartsWith("READY.", StringComparison.Ordinal), text);
    }

    /// <summary>
    ///  The screen is 22 × 23 in the kernal's window; it moves to <c>$1000</c> with RAM in block 1, and the colour RAM
    ///  with it to <c>$9400</c>.
    /// </summary>
    /// <param name="expansion">The expansion RAM.</param>
    /// <param name="screen">The screen's processor address.</param>
    /// <param name="colour">The colour RAM's.</param>
    [TestMethod]
    [DataRow(Vic20Expansion.None, 0x1E00, 0x9600)]
    [DataRow(Vic20Expansion.Ram8K, 0x1000, 0x9400)]
    public void KernalSetsUpTheScreen(Vic20Expansion expansion, int screen, int colour)
    {
        Vic20Machine machine = Machine(expansion: expansion);
        RunToReady(machine);
        machine.Vic.Columns.Should().Be(22);
        machine.Vic.Rows.Should().Be(23);
        int processor = (machine.Vic.ScreenAddress & 0x2000) != 0 ? machine.Vic.ScreenAddress & 0x1FFF : machine.Vic.ScreenAddress | 0x8000;
        processor.Should().Be(screen);
        (0x9400 + (machine.Vic.ScreenAddress & 0x200)).Should().Be(colour);
        machine.Bus.Peek(0x0288).Should().Be((byte)(screen >> 8), "HIBASE, the kernal's screen page");
    }

    /// <summary>
    ///  A program typed at the keyboard is stored and runs, with every typed symbol.
    /// </summary>
    /// <param name="standard">The video standard.</param>
    [TestMethod]
    [DataRow(VicVideoStandard.Ntsc)]
    [DataRow(VicVideoStandard.Pal)]
    public void TypedProgramRuns(VicVideoStandard standard)
    {
        Vic20Machine machine = Machine(standard);
        RunToReady(machine);

        Type(machine, "10 PRINT \"HI\";2+3*4;\"<=>?!#$%&'()+-/:;@[]\\\"\rRUN\r");
        string[] screen = machine.ReadTextScreen();
        string text = string.Join('\n', screen);
        text.Replace("\n", string.Empty, StringComparison.Ordinal).Should().Contain(
            "HI 14 <=>?!#$%&'()+-/:;@[]\\",
            text);
    }

    /// <summary>
    ///  The kernal's colours, white characters' background and cyan border, are what the VIC draws: the scanned frame
    ///  has the border at its edge and the background inside the text window, with a character of the banner in blue.
    /// </summary>
    [TestMethod]
    public void FrameShowsTheKernalsColours()
    {
        Vic20Machine machine = Machine();
        RunToReady(machine);
        machine.Run((ulong)machine.Vic.CyclesPerFrame);

        machine.Bus.Peek(0x900F).Should().Be(0x1B, "white background, normal characters, cyan border");
        machine.Vic.ScannedColour(0, 0).Should().Be(3, "the border is cyan");
        machine.Vic.ScannedColour(machine.Vic.Width / 2, machine.Vic.Height - 30).Should().Be(1, "the background is white");

        // Some dot of the banner's first row is the kernal's blue.
        int top = (machine.Bus.Peek(0x9001) * 2) - 12;
        int left = (machine.Bus.Peek(0x9000) * 4) - 8;
        Enumerable.Range(0, 8).SelectMany(y => Enumerable.Range(0, 22 * 8).Select(x => machine.Vic.ScannedColour(left + x, top + y)))
            .Should().Contain(6);
    }

    /// <summary>
    ///  POKE 36869,242 points the VIC at the character ROM's second half, the set with lowercase, and 240 back.
    /// </summary>
    [TestMethod]
    public void Poke36869ChoosesTheCharacterSet()
    {
        Vic20Machine machine = Machine();
        RunToReady(machine);
        machine.Vic.CharacterAddress.Should().Be(0x0000);

        Type(machine, "POKE 36869,242\r");
        machine.Vic.CharacterAddress.Should().Be(0x0800);

        Type(machine, "POKE 36869,240\r");
        machine.Vic.CharacterAddress.Should().Be(0x0000);
    }

    /// <summary>
    ///  RUN/STOP with RESTORE, through VIA 1's CA1 and the NMI, stops a running program and returns to <c>READY.</c>.
    /// </summary>
    [TestMethod]
    public void StopAndRestoreBreakIn()
    {
        Vic20Machine machine = Machine();
        RunToReady(machine);
        Type(machine, "10 GOTO 10\rRUN\r");
        Type(machine, "\x93");

        machine.Keyboard.Set(Vic20Key.Stop, pressed: true);
        machine.Run(TimeSpan.FromSeconds(0.1));
        machine.Keyboard.Restore = true;
        machine.Run(TimeSpan.FromSeconds(0.1));
        machine.Keyboard.Restore = false;
        machine.Keyboard.Set(Vic20Key.Stop, pressed: false);
        machine.Run(TimeSpan.FromSeconds(1));

        string[] screen = machine.ReadTextScreen();
        screen.Should().Contain(line => line.StartsWith("READY.", StringComparison.Ordinal), string.Join('\n', screen));
    }

    /// <summary>
    ///  The joystick reads through VIA 1's port A and VIA 2's PB7, low while a switch is closed.
    /// </summary>
    [TestMethod]
    public void JoystickReadsThroughTheVias()
    {
        Vic20Machine machine = Machine();
        RunToReady(machine);
        machine.Bus.Joystick = CommodoreJoystick.Up | CommodoreJoystick.Fire;
        Type(machine, "POKE 37139,0:PRINT PEEK(37137)AND 60\r");
        // Up (PA2) and fire (PA5) read low; down (PA3, 8) and left (PA4, 16) high.
        machine.ReadTextScreen().Should().Contain(line => line.TrimEnd() == " 24");

        machine.Bus.Joystick = CommodoreJoystick.Right;
        Type(machine, "POKE 37154,127:J=PEEK(37152)AND 128:POKE 37154,255:PRINT J\r");
        machine.ReadTextScreen().Should().Contain(line => line.TrimEnd() == " 0");
    }

    /// <summary>
    ///  A voice switched on with the volume up makes a tone.
    /// </summary>
    [TestMethod]
    public void VoiceMakesATone()
    {
        Vic20Machine machine = Machine();
        RunToReady(machine);
        PeakAudioSink sink = new();
        machine.Vic.AudioSink = sink;
        Type(machine, "POKE 36878,15:POKE 36876,200\r");
        machine.Run(TimeSpan.FromSeconds(0.2));
        machine.Vic.FlushAudio();
        sink.Peak.Should().BeGreaterThan(0.1f);
    }
}
