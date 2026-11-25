// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug;
using Retrocore.Machines.Apple2;

namespace Retrocore.Tests;

/// <summary>
///  The Apple II Plus: its ROMs, the hardware it lacks next to the IIe, its slot 0 language card and its keyboard.
/// </summary>
[TestClass]
public class Apple2PlusTests
{
    private static readonly string s_inputs = Path.Join(AppContext.BaseDirectory, "Inputs");

    /// <summary>
    ///  The II Plus's character generator, a dot per set bit with bit 6 leftmost, becomes the IIe's form: inverse
    ///  glyphs below $40, normal ones from $80, a dot lit where its bit is clear and bit 0 leftmost.
    /// </summary>
    [TestMethod]
    public void CharacterGeneratorTakesTheIIesForm()
    {
        byte[] characters = new byte[2048];
        characters[0x01 * 8 + 1] = 0b010_0000;
        characters[0x81 * 8 + 1] = 0b010_0000;
        Apple2Roms roms = Apple2Roms.FromBoardChips(new byte[12288], characters);

        // The dot is the second from the left: x = 1.
        int normal = roms.Characters[0x81 * 8 + 1] & 0x7F;
        int inverse = roms.Characters[0x01 * 8 + 1] & 0x7F;
        normal.Should().Be(0b111_1101, "a normal glyph lights its dot, a clear bit");
        inverse.Should().Be(0b000_0010, "an inverse glyph lights everything but its dot");
        roms.System[0x1000].Should().Be(0, "the 12 KiB ROM is at $D000");
    }

    /// <summary>
    ///  The IIe's own switches, status reads, built-in firmware and slot 3 firmware are not on a II Plus's bus.
    /// </summary>
    [TestMethod]
    public void TheIIesOwnHardwareIsNotThere()
    {
        Apple2Bus bus = Bus();
        bus.Write(0xC001, value: 0);
        bus.Write(0xC00D, value: 0);
        bus.Write(0xC007, value: 0);
        bus.Switches.Should().Be(Apple2Switches.Text, "80STORE, 80COL and INTCXROM are the IIe's");
        bus.Write(0xC05E, value: 0);
        bus.Switches.Should().Be(Apple2Switches.Text, "annunciator 3 is not double hi-res here");
        bus.Write(0xC057, value: 0);
        bus.Switches.Should().HaveFlag(Apple2Switches.HiRes, "the display's switches are the same");

        bus.ReadArea(0xC300).Should().Be(Apple2MemoryArea.None, "slot 3 is an empty slot, not the 80-column firmware");
        bus.ReadArea(0xC800).Should().Be(Apple2MemoryArea.None);
        bus.IsSlotFree(3).Should().BeTrue();
        bus.PeekArea(Apple2MemoryArea.SystemRom, 0xC100, out _).Should().BeFalse("the system ROM starts at $D000");
        bus.PeekArea(Apple2MemoryArea.SystemRom, 0xD000, out _).Should().BeTrue();
    }

    /// <summary>
    ///  Reading $C011-$C01F clears the keyboard strobe as $C010 does, and a lowercase key arrives as its capital.
    /// </summary>
    [TestMethod]
    public void TheKeyboardHasNoLowercaseAndAnyStrobeAddressClearsIt()
    {
        Apple2Bus bus = Bus();
        bus.QueueKey((byte)'a');
        bus.Read(0xC000).Should().Be((byte)('A' | 0x80));
        bus.Read(0xC018);
        bus.Read(0xC000).Should().Be((byte)'A', "$C018 cleared the strobe");
    }

    /// <summary>
    ///  Without the slot 0 language card, $C080-$C08F do nothing and $D000-$FFFF is always ROM; with it, the card's
    ///  RAM answers as the IIe's does.
    /// </summary>
    [TestMethod]
    public void TheLanguageCardIsACardInSlot0()
    {
        byte[] system = new byte[12288];
        system[0] = 0x5A;
        Apple2Bus bus = new(Apple2Model.IIPlus, Apple2Roms.FromBoardChips(system, new byte[2048]));
        bus.LanguageCardInstalled.Should().BeFalse();
        bus.Read(0xC083);
        bus.Read(0xC083);
        bus.Write(0xD000, value: 0x11);
        bus.Read(0xD000).Should().Be(0x5A, "with no card the ROM answers");

        bus.InstallLanguageCard();
        bus.Read(0xC083);
        bus.Read(0xC083);
        bus.Write(0xD000, value: 0x11);
        bus.Read(0xD000).Should().Be(0x11, "the card reads and writes its RAM");
        bus.RemoveLanguageCard();
        bus.Read(0xD000).Should().Be(0x5A);

        Apple2Bus iie = new(Apple2Model.IIeEnhanced, Apple2Roms.FromBoardChips(system, new byte[2048]));
        Action builtIn = iie.RemoveLanguageCard;
        builtIn.Should().Throw<InvalidOperationException>("the IIe's language card is built in");
    }

    /// <summary>
    ///  A board with less than 48 KiB has nothing past its RAM: writes go nowhere and reads see the floating bus, and
    ///  AppleSoft finds the top of memory there.
    /// </summary>
    /// <param name="kilobytes">The RAM on the board.</param>
    [TestMethod]
    [DataRow(16)]
    [DataRow(32)]
    public void SmallerBoardsEndTheirRam(int kilobytes)
    {
        Apple2Bus bus = Bus();
        bus.RamKilobytes = kilobytes;
        ushort top = (ushort)(kilobytes * 1024);
        bus.Write((ushort)(top - 1), value: 0x5A);
        bus.Write(top, value: 0x5A);
        bus.Peek((ushort)(top - 1)).Should().Be(0x5A);
        bus.ReadArea(top).Should().Be(Apple2MemoryArea.None);

        Apple2Machine machine = new(Apple2Model.IIPlus, SdkModules.BuildRoms(Apple2Model.IIPlus, s_inputs));
        machine.Bus.RamKilobytes = kilobytes;
        machine.Run(cycles: 2_000_000);
        int himem = machine.Bus.Peek(0x73) | (machine.Bus.Peek(0x74) << 8);
        himem.Should().Be(top, "AppleSoft's HIMEM is the top of the RAM it found");

        Apple2Bus iieBus = new(Apple2Model.IIe, Apple2Roms.FromBoardChips(new byte[12288], new byte[2048]));
        Action iie = () => iieBus.RamKilobytes = 32;
        iie.Should().Throw<ArgumentOutOfRangeException>("the IIe always has 48 KiB");
    }

    /// <summary>
    ///  The II and II Plus's character generator has no lowercase: its $E0-$FF draw the symbols and digits of
    ///  $A0-$BF, so they read as those, while the IIe's read as lowercase. With the IIe's alternate character set on,
    ///  $60-$7F are inverse lowercase; the II and II Plus have no alternate set, so they still flash symbols.
    /// </summary>
    /// <param name="model">The model.</param>
    /// <param name="lowercase">Whether its character generator has lowercase.</param>
    [TestMethod]
    [DataRow(Apple2Model.II, false)]
    [DataRow(Apple2Model.IIPlus, false)]
    [DataRow(Apple2Model.IIe, true)]
    [DataRow(Apple2Model.IIeEnhanced, true)]
    public void TopCodesReadAsTheGlyphsTheyDraw(Apple2Model model, bool lowercase)
    {
        const string Symbols = " !\"#$%&'()*+,-./0123456789:;<=>?";
        const string Lowercase = "`abcdefghijklmnopqrstuvwxyz{|}~\u007F";
        Apple2Machine machine = new(model, SdkModules.BuildRoms(model, s_inputs));
        Read(0xE0).Should().Be(lowercase ? Lowercase : Symbols);

        // ALTCHARSET on.
        machine.Bus.Write(0xC00F, value: 0);
        Read(0x60).Should().Be(lowercase ? Lowercase : Symbols);
        Read(0xE0).Should().Be(lowercase ? Lowercase : Symbols);

        string Read(int first) =>
            new([.. Enumerable.Range(first, 32).Select(code => machine.Bus.Video.Character((byte)code))]);
    }

    /// <summary>
    ///  From its chip dumps, the II Plus powers on to AppleSoft's prompt, and a line typed in lowercase runs.
    /// </summary>
    [TestMethod]
    public void BootsToAppleSoftAndRunsALine()
    {
        string directory = Environment.GetEnvironmentVariable("RETROCORE_IIPLUS_ROMS")
            ?? Path.Join(ExternalTestData.Root, "apple2-roms", "APPLE II+");

        if (!File.Exists(Path.Join(directory, "APPLE II+ - 341-0020 - APPLESOFT BASIC AUTOSTART MONITOR F800 - 2716.bin")))
        {
            Assert.Inconclusive("Set RETROCORE_IIPLUS_ROMS to the II Plus's chip dumps.");
        }

        Apple2Machine machine = new(Apple2Model.IIPlus, Apple2Roms.LoadFromDirectory(Apple2Model.IIPlus, directory));
        machine.Bus.InstallLanguageCard();
        machine.Run(cycles: 2_000_000);
        Screen(machine).Should().Contain("APPLE ][").And.Contain("]");

        foreach (char key in "print 6*7\r") { machine.Bus.QueueKey((byte)key); }
        machine.Run(cycles: 1_000_000);
        Screen(machine).Should().Contain("PRINT 6*7").And.Contain("42");
    }

    /// <summary>
    ///  The debugger's text rows read the II Plus's screen as it shows: its cursor, a flashing space, reads as a
    ///  space, so the prompt row is a bare <c>]</c>, and a program typed through the debugger's keyboard lists back.
    /// </summary>
    [TestMethod]
    public void TheDebuggersTextRowsReadThePromptAndATypedProgram()
    {
        Apple2Machine machine = new(Apple2Model.IIPlus, SdkModules.BuildRoms(Apple2Model.IIPlus, s_inputs));
        machine.Bus.InstallLanguageCard();
        using Apple2DebugTarget target = new(machine, Apple2Model.IIPlus);
        machine.Run(cycles: 2_000_000);

        string[] rows = Rows(target);
        int prompt = Array.FindIndex(rows, row => row.StartsWith(']'));
        prompt.Should().BeGreaterThan(0, $"AppleSoft's prompt is below the banner:\n{string.Join("\n", rows)}");
        machine.Bus.TextByte(prompt, 1).Should().Be(0x60, "the II Plus's cursor is a flashing space");
        rows[prompt].TrimEnd().Should().Be("]", "the cursor reads as the space it flashes, not as ` ($60's ASCII)");

        // Flashing and inverse text read as their characters: FLASH's digits are $70-$79, its letters $41-$5A, and
        // INVERSE's letters $01-$1A. With no lowercase, $E0-$FF show $A0-$BF's symbols.
        machine.Bus.Write(0x0400, 0x71);
        machine.Bus.Write(0x0401, 0x41);
        machine.Bus.Write(0x0402, 0x01);
        machine.Bus.Write(0x0403, 0xE1);
        Rows(target)[0][..4].Should().Be("1AA!");
        new string([.. Enumerable.Range(0xE0, 32).Select(code => machine.Bus.Video.Character((byte)code))])
            .Should().Be(" !\"#$%&'()*+,-./0123456789:;<=>?");

        foreach (char key in "10 print \"hi\"\r20 end\rlist\r") { target.Key(key); }
        machine.Run(cycles: 2_000_000);
        string screen = string.Join("\n", Rows(target));
        screen.Should().Contain("]10 PRINT \"HI\"").And.Contain("10  PRINT \"HI\"").And.Contain("20  END");
        Rows(target).Last(row => row.StartsWith(']')).TrimEnd().Should().Be("]", "LIST ends at a bare prompt");
    }

    /// <summary>
    ///  The enhanced IIe's rows read its flashing text as the II Plus's do, and otherwise as before: lowercase,
    ///  inverse lowercase in the alternate character set, and MouseText, which has no character and keeps its
    ///  seven-bit code's letter.
    /// </summary>
    [TestMethod]
    public void TheIIesTextRowsReadFlashingTextAndKeepLowercaseAndMouseText()
    {
        Apple2Machine machine = new(Apple2Model.IIeEnhanced, SdkModules.BuildRoms(Apple2Model.IIeEnhanced, s_inputs));
        using Apple2DebugTarget target = new(machine, Apple2Model.IIeEnhanced);
        machine.Bus.Write(0x0400, 0xE1);
        machine.Bus.Write(0x0401, 0x61);
        machine.Bus.Write(0x0402, 0x41);
        machine.Bus.Write(0x0403, 0x71);
        Rows(target)[0][..4].Should().Be("a!A1", "without the alternate set, $61 and $71 are a flashing ! and 1");

        machine.Bus.Write(0xC00F, value: 0);
        Rows(target)[0][..4].Should().Be("aaAq", "the alternate set's $61 and $71 are inverse lowercase, $41 MouseText");
    }

    private static string[] Rows(Apple2DebugTarget target) =>
        [.. (target.DisplayState(running: false)["rows"]?.AsArray() ?? throw new InvalidOperationException("No rows."))
            .Select(row => row?.GetValue<string>() ?? "")];

    private static Apple2Bus Bus() =>
        new(Apple2Model.IIPlus, Apple2Roms.FromBoardChips(new byte[12288], new byte[2048]));

    private static string Screen(Apple2Machine machine) => string.Join(
        "\n",
        Enumerable.Range(0, 24).Select(row => new string([.. Enumerable.Range(0, 40)
            .Select(column => (char)(machine.Bus.TextByte(row, column) & 0x7F))
            .Select(character => character < 32 ? (char)(character + 64) : character)])));
}
