// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Apple2;

namespace Retrocore.Tests;

/// <summary>
///  The Apple II of 1977: Integer BASIC with the original or Autostart Monitor, the slot 0 firmware card that holds
///  the other BASIC, and revision 0's hi-res colors.
/// </summary>
[TestClass]
public class Apple2IITests
{
    private static string IIRoms => Environment.GetEnvironmentVariable("RETROCORE_II_ROMS")
        ?? Path.Join(ExternalTestData.Root, "apple2-roms", "APPLE II");

    private static string IIPlusRoms => Environment.GetEnvironmentVariable("RETROCORE_IIPLUS_ROMS")
        ?? Path.Join(ExternalTestData.Root, "apple2-roms", "APPLE II+");

    /// <summary>
    ///  With the original Monitor, the II resets into the Monitor's <c>*</c>; CONTROL-B starts Integer BASIC, whose
    ///  prompt is <c>&gt;</c>, and a line typed in lowercase runs in capitals.
    /// </summary>
    [TestMethod]
    public void OriginalMonitorResetsIntoTheMonitorAndControlBStartsIntegerBasic()
    {
        Apple2Machine machine = II(autostart: false);
        machine.Run(cycles: 1_000_000);
        Screen(machine).Should().Contain("*").And.NotContain(">");

        Type(machine, "\u0002\r");
        Screen(machine).Should().Contain(">");
        Type(machine, "print 6*7\r");
        Screen(machine).Should().Contain("PRINT 6*7").And.Contain("42");
    }

    /// <summary>
    ///  With the Autostart Monitor and no disk, the II starts Integer BASIC at power-on.
    /// </summary>
    [TestMethod]
    public void AutostartMonitorStartsIntegerBasic()
    {
        Apple2Machine machine = II(autostart: true);
        machine.Run(cycles: 2_000_000);
        Screen(machine).Should().Contain("APPLE ][").And.Contain(">");
    }

    /// <summary>
    ///  The AppleSoft firmware card makes a II start like a II Plus, and $C081 and $C080 switch between the board's
    ///  Integer BASIC and the card's AppleSoft, as DOS 3.3 does.
    /// </summary>
    [TestMethod]
    public void TheFirmwareCardHoldsTheOtherBasic()
    {
        Apple2Machine machine = II(autostart: false);
        machine.Bus.InstallFirmwareCard(Apple2Roms.LoadFirmwareCard(Apple2Model.IIPlus, IIPlusRoms));
        machine.Bus.ResetSwitches();
        machine.Processor.Reset();
        machine.Run(cycles: 2_000_000);
        Screen(machine).Should().Contain("]", "the card's AppleSoft and Autostart Monitor start");

        // AppleSoft starts with a JMP, Integer BASIC with a JSR, which is how DOS 3.3 tells them apart.
        machine.Bus.Peek(0xE000).Should().Be(0x4C);
        machine.Bus.Read(0xC081);
        machine.Bus.Peek(0xE000).Should().Be(0x20, "$C081 selects the board's Integer BASIC");
        machine.Bus.Write(0xC080, value: 0);
        machine.Bus.Peek(0xE000).Should().Be(0x4C, "$C080 selects the card");
    }

    /// <summary>
    ///  A revision 0 board ignores hi-res bit 7: a byte with it set draws the same green and violet as one without,
    ///  where later boards draw orange and blue.
    /// </summary>
    [TestMethod]
    public void RevisionZeroHasFourHiresColors()
    {
        byte[] plain = Draw(revision0: false, 0x55);
        byte[] shifted = Draw(revision0: false, 0xD5);
        shifted.Should().NotEqual(plain, "bit 7 shifts a later board's colors");
        Draw(revision0: true, 0xD5).Should().Equal(Draw(revision0: true, 0x55), "revision 0 has no shift");
    }

    private static byte[] Draw(bool revision0, byte value)
    {
        Apple2Bus bus = new(Apple2Model.II, Apple2Roms.FromBoardChips(new byte[12288], new byte[2048]));
        bus.Video.Revision0 = revision0;
        bus.Read(0xC050);
        bus.Read(0xC057);
        for (int column = 0; column < 40; column++) { bus.SetRam(auxiliary: false, (ushort)(0x2000 + column), value); }
        return bus.Video.RenderBitmap()[..(560 * 4)];
    }

    private static Apple2Machine II(bool autostart)
    {
        if (!File.Exists(Path.Join(IIRoms, "APPLE II - 341-0004 - INTEGER BASIC MONITOR F800 - 2716.bin"))
            || !Directory.Exists(IIPlusRoms))
        {
            Assert.Inconclusive("Set RETROCORE_II_ROMS and RETROCORE_IIPLUS_ROMS to the II's and II Plus's chip dumps.");
        }

        return new(Apple2Model.II, Apple2Roms.LoadFromDirectory(Apple2Model.II, IIRoms, autostart));
    }

    private static void Type(Apple2Machine machine, string keys)
    {
        foreach (char key in keys)
        {
            machine.Bus.QueueKey((byte)key);
            machine.Run(cycles: 50_000);
        }

        machine.Run(cycles: 500_000);
    }

    private static string Screen(Apple2Machine machine) => string.Join(
        "\n",
        Enumerable.Range(0, 24).Select(row => new string([.. Enumerable.Range(0, 40)
            .Select(column => (char)(machine.Bus.TextByte(row, column) & 0x7F))
            .Select(character => character < 32 ? (char)(character + 64) : character)])));
}
