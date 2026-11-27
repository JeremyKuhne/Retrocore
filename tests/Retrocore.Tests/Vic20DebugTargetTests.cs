// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Basic;
using Retrocore.Debug;
using Retrocore.Machines.Commodore.Vic20;
using System.Text.Json.Nodes;

namespace Retrocore.Tests;

/// <summary>
///  The VIC-20 under the debugger, with its ROMs built from the SDK's sources: its launch options, the keys that type
///  nothing, its BASIC's page zero, its errors and screen, and what the Machine view says.
/// </summary>
/// <remarks>
///  <para>
///   With <c>RETROCORE_VIC20_ROMS</c> set, the launches run the dumps instead, which are the same bytes.
///   <c>tools/Test-Vic20Dap.mjs</c> and <c>tools/Test-Vic20BasicDap.mjs</c> run the target through the debug adapter.
///  </para>
/// </remarks>
[TestClass]
public sealed class Vic20DebugTargetTests
{
    /// <summary>
    ///  A launch refuses a video standard, expansion, sound or drive it does not know, and a cartridge it cannot read.
    /// </summary>
    [TestMethod]
    public void LaunchRefusesWhatItDoesNotKnow()
    {
        Refuses(new() { ["video"] = "secam" }, "video must be ntsc or pal.");
        Refuses(new() { ["ramExpansion"] = "64k" }, "ramExpansion must be none, 3k, 8k, 16k, 24k or 32k.");
        Refuses(new() { ["sound"] = "loud" }, "sound must be speaker or off.");
        Refuses(new() { ["diskModel"] = "1571" }, "diskModel is 1541 or 1540.");
        Refuses(new() { ["cartridge"] = 5 }, "cartridge is a file path or a list of them.");
        string missing = Path.Join(Path.GetTempPath(), $"retrocore-vic20-{Guid.NewGuid():N}.a0");
        Refuses(new() { ["cartridge"] = missing }, "The cartridge cannot be loaded:*");

        static void Refuses(JsonObject args, string message)
        {
            Action launch = () => Launch(args);
            launch.Should().Throw<ArgumentException>().WithMessage(message);
        }
    }

    /// <summary>
    ///  Above PETSCII, RESTORE, RUN/STOP with RESTORE, and SHIFT with the Commodore key are held for a tenth of a
    ///  second and let go; nothing above them is a key.
    /// </summary>
    [TestMethod]
    public void KeysThatTypeNothingAreHeldBriefly()
    {
        Vic20DebugTarget target = Launch([]);
        target.MaximumKey.Should().Be(Vic20DebugTarget.CommodoreShiftKey);
        target.Key(Vic20DebugTarget.CommodoreShiftKey + 1).Should().BeFalse();
        target.Key(Vic20DebugTarget.CommodoreShiftKey).Should().BeTrue();
        Vic20Keyboard keyboard = target.Machine.Keyboard;
        keyboard.IsPressed(Vic20Key.LeftShift).Should().BeTrue();
        keyboard.IsPressed(Vic20Key.Commodore).Should().BeTrue();

        // Another such key lets go of the first.
        target.Key(Vic20DebugTarget.StopRestoreKey).Should().BeTrue();
        keyboard.IsPressed(Vic20Key.Commodore).Should().BeFalse();
        keyboard.IsPressed(Vic20Key.LeftShift).Should().BeFalse();
        keyboard.IsPressed(Vic20Key.Stop).Should().BeTrue();
        keyboard.Restore.Should().BeTrue();
        target.RunCycles((target.ClockHertz / 10) + 1);
        keyboard.IsPressed(Vic20Key.Stop).Should().BeFalse();
        keyboard.Restore.Should().BeFalse();

        // RESTORE alone.
        target.Key(Vic20DebugTarget.RestoreKey).Should().BeTrue();
        keyboard.Restore.Should().BeTrue();
        keyboard.IsPressed(Vic20Key.Stop).Should().BeFalse();
        target.RunCycles((target.ClockHertz / 10) + 1);
        keyboard.Restore.Should().BeFalse();
    }

    /// <summary>
    ///  The VIC-20's BASIC is the PET's BASIC 2 with its pointers three bytes higher, and its programs start at
    ///  <c>$1001</c> unexpanded.
    /// </summary>
    [TestMethod]
    public void BasicKeepsItsPointersAboveThePets()
    {
        BasicDialect vic20 = BasicDialect.Vic20Basic;
        vic20.Keywords.Should().Equal(BasicDialect.PetBasic.Keywords);
        vic20.Pointers.ProgramStart.Should().Be(BasicDialect.PetBasic.Pointers.ProgramStart + 3);
        vic20.Pointers.DataPointer.Should().Be(BasicDialect.PetBasic.Pointers.DataPointer + 3);
        vic20.DefaultLoadAddress.Should().Be(0x1001);
        vic20.InputLimit.Should().Be(88);
        vic20.DisplayName.Should().Be("Commodore BASIC 2 (VIC-20)");
        Launch([]).Basic.Should().BeSameAs(vic20);
    }

    /// <summary>
    ///  Booted, the screen reads as text through the target's character set, and an error number reads as BASIC's
    ///  message through its table of addresses.
    /// </summary>
    [TestMethod]
    public void BootedScreenAndErrorsRead()
    {
        Vic20DebugTarget target = Launch([]);
        target.Boot(3);
        target.ShowsReady.Should().BeTrue();
        target.DisplayState(running: false)["columns"]?.GetValue<int>().Should().Be(22);
        Machines.ICharacterSet characters = target.CharacterSet ?? throw new InvalidOperationException("No character set.");
        characters.Character(0x01).Should().Be('A');
        characters.Character(0x81).Should().Be('A', "reversed characters read as their own");
        characters.Character(0x66).Should().Be('\0', "graphics read as nothing");

        ProcessorRegisters registers = target.Machine.Processor.Registers;
        registers.X = 11;
        target.Machine.Processor.Registers = registers;
        target.BasicError().Message.Should().Be("?SYNTAX ERROR");
        registers.X = 4;
        target.Machine.Processor.Registers = registers;
        target.BasicError().Message.Should().Be("?FILE NOT FOUND ERROR", "the kernal's errors share the table");
        registers.X = 30;
        target.Machine.Processor.Registers = registers;
        target.BasicError().Message.Should().Be("?BREAK ERROR", "BREAK's NUL and shifted space read as one space");
    }

    /// <summary>
    ///  The Machine view names the video standard, the ROMs, the memory with each expansion, and the empty cartridge
    ///  slot and serial-bus numbers.
    /// </summary>
    [TestMethod]
    public void MachineViewDescribesTheMachine()
    {
        Dictionary<string, string> rows = Rows(new() { ["video"] = "pal", ["ramExpansion"] = "16k" });
        rows["video"].Should().Be("PAL, the 6561");
        rows["rom"].Should().StartWith("BASIC 2 and kernal 901486-07", "from the SDK's sources, or the dumps in RETROCORE_VIC20_ROMS");
        rows["memory"].Should().Be("21 KB: 5 KB and block 1, block 2");
        rows["cartridge"].Should().Be("empty");
        rows["serial8"].Should().Be("empty");
        Rows([])["memory"].Should().Be("5 KB, unexpanded");
        Rows(new() { ["ramExpansion"] = "3k" })["memory"].Should().Be("8 KB: 5 KB and 3K at $0400");

        static Dictionary<string, string> Rows(JsonObject args) =>
            Launch(args).Hardware().ToDictionary(row => row.Id, row => row.Value);
    }

    /// <summary>
    ///  A BASIC <c>.prg</c> loaded before the kernal has set where BASIC's program starts is refused, not written over
    ///  page zero.
    /// </summary>
    [TestMethod]
    public void BasicProgramWaitsForTheKernal()
    {
        Vic20DebugTarget target = Launch([]);
        Action early = () => target.LoadPrg([0x01, 0x10, 0x00, 0x00, 0x00], run: false, entry: null);
        early.Should().Throw<ArgumentException>().WithMessage("*bootSeconds*");
    }

    /// <summary>
    ///  The expansion's RAM is in the program's area, as the built-in 5K is, so a program in block 1 maps to its source.
    /// </summary>
    [TestMethod]
    public void ExpansionRamIsProgramRam()
    {
        Vic20DebugTarget target = Launch(new() { ["ramExpansion"] = "32k" });
        foreach (ushort address in (ushort[])[0x0000, 0x0400, 0x1400, 0x2000, 0x7FFF])
        {
            target.ReadArea(address).Should().Be(target.ProgramArea, $"${address:X4} is RAM");
        }

        target.ReadArea(0xC000).Should().Be(Vic20MemoryArea.Basic);
        target.ReadArea(0xA000).Should().Be(Vic20MemoryArea.None, "block 5 is empty without a cartridge or its RAM");
    }

    private static Vic20DebugTarget Launch(JsonObject args) => Vic20DebugTarget.Launch(args);
}
