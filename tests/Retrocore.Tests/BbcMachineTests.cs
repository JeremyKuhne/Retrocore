// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Acorn;

namespace Retrocore.Tests;

/// <summary>
///  The BBC Micro on its own ROMs, which need the dumps: MAME's <c>bbcb</c> set, unzipped, in
///  <c>RETROCORE_BBC_ROMS</c> or <c>%USERPROFILE%\Retrocore\bbc-roms\extract\bbcb</c>.
/// </summary>
[TestClass]
public class BbcMachineTests
{
    /// <summary>
    ///  Gets the folder holding MAME's <c>bbcb</c> set's chips.
    /// </summary>
    internal static string RomDirectory => Environment.GetEnvironmentVariable("RETROCORE_BBC_ROMS")
        ?? Path.Join(ExternalTestData.Root, "bbc-roms", "extract", "bbcb");

    /// <summary>
    ///  Makes a machine at power-on, or marks the test inconclusive without the dumps.
    /// </summary>
    /// <param name="model">The model.</param>
    /// <param name="filingSystem">The filing system ROM for socket 0, or null for none.</param>
    /// <param name="diskInterface">Whether the 8271 is fitted; by default with the Model B.</param>
    /// <returns>The machine.</returns>
    internal static BbcMachine Machine(
        BbcModel model = BbcModel.ModelB,
        string? filingSystem = null,
        bool? diskInterface = null)
    {
        if (!File.Exists(Path.Join(RomDirectory, "os12.rom")))
        {
            Assert.Inconclusive("Set RETROCORE_BBC_ROMS to a folder with MAME's bbcb set unzipped.");
        }

        return new(BbcRoms.LoadFromDirectory(RomDirectory, filingSystem), model, diskInterface);
    }

    /// <summary>
    ///  Runs until the screen shows BASIC's <c>&gt;</c> prompt, for up to five emulated seconds.
    /// </summary>
    /// <param name="machine">The machine.</param>
    /// <returns>The screen.</returns>
    internal static string[] RunToPrompt(BbcMachine machine)
    {
        for (int tenth = 0; tenth < 50; tenth++)
        {
            machine.Run(TimeSpan.FromSeconds(0.1));
            string[] screen = machine.ReadTextScreen();
            if (screen.Any(line => line.StartsWith('>'))) { return screen; }
        }

        return machine.ReadTextScreen();
    }

    /// <summary>
    ///  Types text and waits until the keyboard is done, and half a second more.
    /// </summary>
    /// <param name="machine">The machine.</param>
    /// <param name="text">The text, with carriage returns for RETURN.</param>
    internal static void Type(BbcMachine machine, string text)
    {
        foreach (char c in text) { machine.Keyboard.Type((byte)c).Should().BeTrue($"the BBC has a key for {c}"); }
        while (machine.Keyboard.IsTyping) { machine.Run(TimeSpan.FromSeconds(0.05)); }
        machine.Run(TimeSpan.FromSeconds(0.5));
    }

    /// <summary>
    ///  Each model starts in mode 7 with its banner, its RAM, BASIC and the prompt.
    /// </summary>
    /// <param name="model">The model.</param>
    /// <param name="banner">The first line.</param>
    [TestMethod]
    [DataRow(BbcModel.ModelB, "BBC Computer 32K")]
    [DataRow(BbcModel.ModelA, "BBC Computer 16K")]
    public void PowerOnShowsBannerAndPrompt(BbcModel model, string banner)
    {
        BbcMachine machine = Machine(model);
        string[] screen = RunToPrompt(machine);
        string text = string.Join('\n', screen);
        machine.Video.Teletext.Should().BeTrue(text);
        screen[1].TrimEnd().Should().Be(banner, text);
        screen.Should().Contain(line => line.TrimEnd() == "BASIC", text);
        screen.Should().Contain(line => line.TrimEnd() == ">", text);
    }

    /// <summary>
    ///  A typed program runs.
    /// </summary>
    [TestMethod]
    public void TypedProgramRuns()
    {
        BbcMachine machine = Machine();
        RunToPrompt(machine);
        Type(machine, "10 FOR I%=1 TO 3:PRINT I%*7;\"x\":NEXT\r");
        Type(machine, "RUN\r");
        string[] screen = machine.ReadTextScreen();
        string text = string.Join('\n', screen);
        screen.Should().Contain(line => line.TrimEnd() == "         7x", text);
        screen.Should().Contain(line => line.TrimEnd() == "        21x", text);
    }

    /// <summary>
    ///  BREAK keeps RAM, so OLD brings the program back; CTRL-BREAK starts afresh, as after power-on.
    /// </summary>
    [TestMethod]
    public void BreakKeepsTheProgramAndControlBreakClearsIt()
    {
        BbcMachine machine = Machine();
        RunToPrompt(machine);
        Type(machine, "10 PRINT \"KEPT\"\r");
        machine.PressBreak();
        RunToPrompt(machine);
        Type(machine, "OLD\rLIST\r");
        machine.ReadTextScreen().Should().Contain(line => line.TrimEnd() == "   10 PRINT \"KEPT\"");

        machine.Keyboard.Press(BbcKey.Control);
        machine.PressBreak();
        machine.Run(TimeSpan.FromSeconds(0.1));
        machine.Keyboard.Release(BbcKey.Control);
        string[] screen = RunToPrompt(machine);
        string text = string.Join('\n', screen);
        screen[1].TrimEnd().Should().Be("BBC Computer 32K", text);
        machine.Bus.Peek(0x0E00).Should().Be(0x0D, "NEW leaves an empty program at PAGE");
        machine.Bus.Peek(0x0E01).Should().Be(0xFF);
    }

    /// <summary>
    ///  ADVAL reads the analogue channels and the fire buttons.
    /// </summary>
    [TestMethod]
    public void AdvalReadsTheJoystick()
    {
        BbcMachine machine = Machine();
        RunToPrompt(machine);
        BbcAnalogue analogue = machine.Bus.Analogue ?? throw new AssertFailedException("The Model B has an analogue port.");
        analogue[0] = 0xC000;
        analogue[1] = 0x2000;
        analogue.Buttons = 1;
        machine.Run(TimeSpan.FromSeconds(0.2));
        Type(machine, "PRINT ADVAL(1) DIV 256;\",\";ADVAL(2) DIV 256;\",\";ADVAL(0) AND 3\r");
        machine.ReadTextScreen().Should().Contain(line => line.Trim() == "192,32,1");
    }

    /// <summary>
    ///  The uPD7002 samples its input as a conversion starts, and a 12-bit conversion keeps all twelve bits.
    /// </summary>
    [TestMethod]
    public void AnalogueSamplesAtTheStartWithTwelveBits()
    {
        BbcAnalogue analogue = new();
        analogue[0] = 0x4230;
        analogue.Write(0, 0x08);                // channel 0, 12 bits
        analogue[0] = 0xC000;                   // moved during the conversion
        for (int cycle = 0; cycle < 10_000; cycle++) { analogue.Tick(); }
        analogue.Read(1).Should().Be(0x42);
        analogue.Read(2).Should().Be(0x30);
    }

    /// <summary>
    ///  Lowercase letters (through CAPS LOCK) and symbols type as the BBC's keyboard makes them; the shifted
    ///  underscore key is the BBC's £, character 96.
    /// </summary>
    [TestMethod]
    public void KeyboardTypesSymbolsAndLowercase()
    {
        BbcMachine machine = Machine();
        RunToPrompt(machine);
        Type(machine, "PRINT \"ab{}|~+*<>?=!#$%&'()@[]\\^_`;:,./\"\r");
        string[] screen = machine.ReadTextScreen();
        string text = string.Join('\n', screen);
        screen.Should().Contain(line => line.TrimEnd() == "ab{}|~+*<>?=!#$%&'()@[]\\^_£;:,./", text);
    }

    /// <summary>
    ///  Each mode's text reads back from screen memory, through the hardware scrolling the MOS uses once the screen is
    ///  full.
    /// </summary>
    /// <param name="mode">The mode.</param>
    /// <param name="columns">Its text columns.</param>
    /// <param name="rows">Its text rows.</param>
    [TestMethod]
    [DataRow(0, 80, 32)]
    [DataRow(1, 40, 32)]
    [DataRow(2, 20, 32)]
    [DataRow(3, 80, 25)]
    [DataRow(4, 40, 32)]
    [DataRow(5, 20, 32)]
    [DataRow(6, 40, 25)]
    [DataRow(7, 40, 25)]
    public void EveryModeShowsText(int mode, int columns, int rows)
    {
        BbcMachine machine = Machine();
        RunToPrompt(machine);
        Type(machine, $"MODE {mode}\r");
        Type(machine, "FOR I%=1 TO 40:PRINT \"L\";I%:NEXT\r");
        string[] screen = machine.ReadTextScreen();
        string text = string.Join('\n', screen);
        screen.Should().HaveCount(rows, text);
        screen.Should().AllSatisfy(line => line.Length.Should().Be(columns));
        screen.Should().Contain(line => line.TrimEnd() == "L40", text);
        screen.Should().Contain(line => line.TrimEnd() == ">", text);
    }

    /// <summary>
    ///  In mode 2 the palette shows logical colours; in mode 7 the teletext codes colour the text.
    /// </summary>
    [TestMethod]
    public void ColoursReachTheFrame()
    {
        BbcMachine machine = Machine();
        RunToPrompt(machine);
        Type(machine, "MODE 2:GCOL 0,129:CLG\r");
        machine.Run(TimeSpan.FromSeconds(0.1));
        CountColour(machine.Video.RenderBitmap(), 0xFF, 0, 0).Should().BeGreaterThan(100_000, "mode 2's red background");

        Type(machine, "MODE 7\r");
        Type(machine, "PRINT CHR$(130);\"GREEN\";CHR$(132);\"BLUE\"\r");
        machine.Run(TimeSpan.FromSeconds(0.1));
        byte[] frame = machine.Video.RenderBitmap();
        CountColour(frame, 0, 0xFF, 0).Should().BeGreaterThan(100, "green teletext");
        CountColour(frame, 0, 0, 0xFF).Should().BeGreaterThan(100, "blue teletext");
    }

    /// <summary>
    ///  A frame drawn from memory, rather than as the beam scanned it, shows the same picture (here with the blinking
    ///  cursor turned off).
    /// </summary>
    [TestMethod]
    public void UnscannedFrameMatchesScanned()
    {
        BbcMachine machine = Machine();
        RunToPrompt(machine);
        Type(machine, "MODE 1:VDU 23,1,0;0;0;0;:PRINT \"HELLO WORLD\"\r");
        machine.Run(TimeSpan.FromSeconds(0.1));
        byte[] drawn = new byte[machine.Video.Width * machine.Video.Height * 4];
        machine.Video.Render(drawn, scanned: false);
        CountColour(drawn, 0xFF, 0xFF, 0xFF).Should().Be(CountColour(machine.Video.RenderBitmap(), 0xFF, 0xFF, 0xFF));
        CountColour(drawn, 0xFF, 0xFF, 0xFF).Should().BeGreaterThan(100);
    }

    /// <summary>
    ///  Turning the cursor off in mode 7, which sets the cursor skew to 3, leaves the text where it was: teletext's
    ///  delay is the hardware's own.
    /// </summary>
    [TestMethod]
    public void Mode7TextStaysWithTheCursorOff()
    {
        BbcMachine machine = Machine();
        RunToPrompt(machine);
        Type(machine, "CLS:PRINT \"HELLO\"\r");
        machine.Run(TimeSpan.FromSeconds(0.1));
        int before = LeftmostLit(machine.Video.RenderBitmap());
        Type(machine, "VDU 23,1,0;0;0;0;\r");
        machine.Run(TimeSpan.FromSeconds(0.1));
        LeftmostLit(machine.Video.RenderBitmap()).Should().Be(before);
    }

    /// <summary>
    ///  An access to a 1 MHz device stretches the CPU's cycle until it ends with a 1 MHz cycle: by one 2 MHz cycle
    ///  when it starts on the 1 MHz clock's phase, by two when it starts off it. FRED, JIM and the slow parts of
    ///  SHEILA stretch; RAM, the ROMs, ROMSEL and the Tube's addresses do not.
    /// </summary>
    [TestMethod]
    public void SlowDevicesStretchTheCycle()
    {
        BbcMachine machine = Machine();
        BbcBus bus = machine.Bus;
        long Extra(ushort address)
        {
            long before = bus.Cycles;
            bus.Read(address);
            return bus.Cycles - before;
        }

        foreach (ushort slow in (ushort[])[0xFC00, 0xFD00, 0xFE00, 0xFE40, 0xFE60, 0xFEC0])
        {
            // Every stretch ends on the 1 MHz edge, an odd count: an access from there is off the phase, and one a
            // cycle later is on it.
            Extra(slow);
            (bus.Cycles & 1).Should().Be(1);
            Extra(slow).Should().Be(2, $"&{slow:X4} off the 1 MHz phase");
            bus.Tick();
            Extra(slow).Should().Be(1, $"&{slow:X4} on the 1 MHz phase");
        }

        foreach (ushort fast in (ushort[])[0x1000, 0x8000, 0xC000, 0xFE30, 0xFEE0, 0xFF00])
        {
            Extra(fast).Should().Be(0, $"&{fast:X4} is on the 2 MHz bus");
        }
    }

    /// <summary>
    ///  The system VIA's CB2 output is the 6845's light pen strobe: only its rising edge latches the address being
    ///  drawn into R16 and R17.
    /// </summary>
    [TestMethod]
    public void Cb2RisingEdgeStrobesTheLightPen()
    {
        BbcMachine machine = Machine();
        RunToPrompt(machine);
        BbcBus bus = machine.Bus;
        int LightPen()
        {
            bus.Write(0xFE00, 16);
            int high = bus.Read(0xFE01);
            bus.Write(0xFE00, 17);
            return (high << 8) | bus.Read(0xFE01);
        }

        int controls = bus.Read(0xFE4C) & 0x1F;
        bus.Write(0xFE4C, (byte)(controls | 0xE0));         // CB2 held high: no edge yet
        int before = LightPen();
        machine.Run(TimeSpan.FromMilliseconds(3));
        bus.Write(0xFE4C, (byte)(controls | 0xE0));         // still high: no edge, nothing latched
        LightPen().Should().Be(before);

        bus.Write(0xFE4C, (byte)(controls | 0xC0));         // CB2 low
        LightPen().Should().Be(before, "a falling edge latches nothing");
        bus.Write(0xFE4C, (byte)(controls | 0xE0));         // CB2 high: the rising edge
        int latched = LightPen();
        latched.Should().NotBe(before, "the beam moved on in 3 ms, and the rising edge latched where it is now");
        latched.Should().BeInRange(0x2000, 0x3FFF, "mode 7's addresses have bit 13 set");
    }

    /// <summary>
    ///  Teletext's steady (&amp;09) is set-at: a held mosaic in its own cell is shown steady while flash hides the
    ///  ones before it.
    /// </summary>
    [TestMethod]
    public void SteadyIsSetAt()
    {
        BbcTeletext teletext = new(TeletextRom());
        teletext.StartField();                              // the flash timer's hidden phase
        teletext.StartLine();
        foreach (int code in (int[])[0x11, 0x1E, 0x08])     // red graphics, hold, flash
        {
            teletext.Character(code, oddField: false);
        }

        teletext.Character(0x7F, oddField: false).Should().Be(0, "flash hides the mosaic");
        teletext.Character(0x09, oddField: false).Should().NotBe(0, "steady shows the held mosaic in its own cell");
    }

    /// <summary>
    ///  A field starts on a top row: double height in the last row of the field before does not make the first row a
    ///  bottom row, which would hide its normal-height text.
    /// </summary>
    [TestMethod]
    public void FieldStartsOnATopRow()
    {
        BbcTeletext teletext = new(TeletextRom());
        teletext.StartField();
        for (int line = 0; line < 10; line++)
        {
            teletext.StartLine();
            teletext.Character(0x0D, oddField: false);      // double height on every line of the row
        }

        teletext.StartField();
        teletext.StartLine();
        teletext.Character('A', oddField: false).Should().NotBe(0);
    }

    /// <summary>
    ///  Concealed text stays hidden until the next colour code: a black background code after conceal does not show
    ///  it, as the BBC has no reveal, and a colour code after the text shows the text after it again.
    /// </summary>
    [TestMethod]
    public void ConcealHoldsUntilAColourCode()
    {
        BbcTeletext teletext = new(TeletextRom());
        teletext.StartField();
        teletext.StartLine();
        foreach (int code in (int[])[0x01, 0x1D, 0x18, 0x1C])  // red, new background, conceal, black background
        {
            teletext.Character(code, oddField: false);
        }

        teletext.Character('A', oddField: false).Should().Be(0, "still concealed");
        teletext.Character(0x02, oddField: false);              // green ends the conceal, after itself
        teletext.Character('A', oddField: false).Should().NotBe(0);
    }

    // A teletext character ROM with every dot lit but the space's.
    private static byte[] TeletextRom()
    {
        byte[] rom = new byte[960];
        rom.AsSpan(10).Fill(0x1F);
        return rom;
    }

    /// <summary>
    ///  A frame drawn from video memory is opaque everywhere, as <see cref="Retrocore.Machines.IVideoSource"/> asks,
    ///  even where the beam does not reach: here a short vertical total leaves the lower rows undrawn.
    /// </summary>
    [TestMethod]
    public void UnscannedFrameIsOpaque()
    {
        BbcMachine machine = Machine();
        RunToPrompt(machine);
        machine.Bus.Write(0xFE00, 4);                       // the 6845's vertical total
        machine.Bus.Write(0xFE01, 10);
        byte[] pixels = new byte[BbcVideo.FrameWidth * BbcVideo.FrameHeight * 4];
        machine.Video.Render(pixels, scanned: false);
        int transparent = 0;
        for (int index = 3; index < pixels.Length; index += 4)
        {
            if (pixels[index] != 0xFF) { transparent++; }
        }

        transparent.Should().Be(0);
    }

    // The first column with a lit pixel, scanning the frame.
    private static int LeftmostLit(byte[] frame)
    {
        int width = BbcVideo.FrameWidth;
        int leftmost = int.MaxValue;
        for (int pixel = 0; pixel < frame.Length / 4; pixel++)
        {
            if (frame[(pixel * 4) + 1] > 0x80) { leftmost = Math.Min(leftmost, pixel % width); }
        }

        return leftmost;
    }

    /// <summary>
    ///  SOUND and ENVELOPE reach the SN76489, and the output carries the tone.
    /// </summary>
    [TestMethod]
    public void SoundPlaysTheTone()
    {
        BbcMachine machine = Machine();
        RunToPrompt(machine);
        PeakAudioSink sink = new();
        machine.Audio.Sink = sink;
        Type(machine, "ENVELOPE 1,1,0,0,0,0,0,0,126,0,0,-126,126,126:SOUND 1,1,101,40\r");
        machine.Run(TimeSpan.FromSeconds(0.2));
        machine.Audio.Flush();

        // Pitch 101 is the C above middle C, a period of about 239 (4 MHz / 32 / 523 Hz).
        machine.Audio.Chip.Period(2).Should().BeInRange(225, 245);
        machine.Audio.Chip.Attenuation(2).Should().BeLessThan(15);
        sink.Peak.Should().BeGreaterThan(0.05f);
    }

    private static int CountColour(byte[] frame, byte red, byte green, byte blue)
    {
        int count = 0;
        for (int index = 0; index < frame.Length; index += 4)
        {
            if (frame[index] == red && frame[index + 1] == green && frame[index + 2] == blue) { count++; }
        }

        return count;
    }

    /// <summary>
    ///  With DNFS 1.20 in socket 0, the MOS finds it as a service ROM; without a disk controller it says nothing, and
    ///  BASIC still starts.
    /// </summary>
    [TestMethod]
    public void PowerOnWithDnfsFindsTheRom()
    {
        BbcMachine machine = Machine(filingSystem: "dnfs120.rom", diskInterface: false);
        string[] screen = RunToPrompt(machine);
        string text = string.Join('\n', screen);
        screen.Should().Contain(line => line.TrimEnd() == ">", text);

        // The MOS's ROM type table: DNFS, a service ROM, in ROM 12 (the highest copy of socket 0), BASIC in 15.
        machine.Bus.Peek(0x2A1 + 12).Should().Be(0x82);
        machine.Bus.Peek(0x2A1 + 15).Should().Be(0x60);
    }
}
