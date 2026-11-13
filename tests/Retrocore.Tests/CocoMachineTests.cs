// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Coco;

namespace Retrocore.Tests;

/// <summary>
///  The Color Computer 1 and 2 booting their ROM dumps and running BASIC.
/// </summary>
[TestClass]
public class CocoMachineTests
{
    /// <summary>
    ///  Each Color BASIC and Extended Color BASIC pairing boots to its sign-on and OK.
    /// </summary>
    /// <param name="model">The model.</param>
    /// <param name="color">Color BASIC's version.</param>
    /// <param name="extended">Extended Color BASIC's version, or 0 for none.</param>
    /// <param name="kilobytes">The RAM.</param>
    /// <param name="signOn">Text the sign-on shows.</param>
    [TestMethod]
    [DataRow(CocoModel.Coco1, 10, 0, 4, "COLOR BASIC 1.0")]
    [DataRow(CocoModel.Coco1, 11, 0, 16, "COLOR BASIC 1.1")]
    [DataRow(CocoModel.Coco1, 12, 11, 16, "EXTENDED COLOR BASIC 1.1")]
    [DataRow(CocoModel.Coco1, 12, 11, 64, "EXTENDED COLOR BASIC 1.1")]
    [DataRow(CocoModel.Coco2, 12, 11, 64, "EXTENDED COLOR BASIC 1.1")]
    [DataRow(CocoModel.Coco2, 13, 11, 64, "EXTENDED COLOR BASIC 1.1")]
    [DataRow(CocoModel.Coco2, 13, 0, 16, "COLOR BASIC 1.3")]
    public void BootsToBasic(CocoModel model, int color, int extended, int kilobytes, string signOn)
    {
        CocoMachine machine = Create(model, color, extended, kilobytes);
        machine.Run(2 * (ulong)CocoTiming.ClockHertz);
        string screen = Screen(machine);
        screen.Should().Contain(signOn).And.Contain("OK");
    }

    /// <summary>
    ///  The CoCo 3 boots its 32 KB ROM to Extended Color BASIC 2.0 in the 32-column screen, then switches to the
    ///  GIME's 40 and 80 columns.
    /// </summary>
    /// <param name="kilobytes">The RAM.</param>
    [TestMethod]
    [DataRow(128)]
    [DataRow(512)]
    public void Coco3BootsAndChangesWidth(int kilobytes)
    {
        CocoMachine machine = Create(CocoModel.Coco3, 0, 0, kilobytes);
        machine.Run(3 * (ulong)CocoTiming.ClockHertz);
        Screen(machine).Should().Contain("EXTENDED COLOR BASIC 2.0").And.Contain("OK");
        CocoGime gime = machine.Bus.Gime ?? throw new AssertFailedException("A CoCo 3 has a GIME.");
        gime.CompatibleVideo.Should().BeTrue();

        Type(machine, "width 40\rprint 6*7\r");
        gime.CompatibleVideo.Should().BeFalse();
        Screen(machine).Should().Contain("42");

        Type(machine, "width 80\rprint mem\r");
        Screen(machine).Should().Contain("OK");
        machine.Bus.Coco3Video.TextRows()[0].Length.Should().Be(80);
    }

    /// <summary>
    ///  Typed lines run: PRINT shows a sum and MEM reports the RAM BASIC has.
    /// </summary>
    [TestMethod]
    public void RunsTypedBasic()
    {
        CocoMachine machine = Create(CocoModel.Coco2, 12, 11, 64);
        machine.Run(2 * (ulong)CocoTiming.ClockHertz);
        Type(machine, "PRINT 2+3\r10 FOR I=1 TO 3:PRINT I*I;:NEXT\rRUN\r");
        Screen(machine).Should().Contain(" 5 ").And.Contain(" 1  4  9 ");
    }

    /// <summary>
    ///  The 60 Hz field sync interrupt counts BASIC's TIMER up by about 60 a second.
    /// </summary>
    [TestMethod]
    public void FieldSyncDrivesTheTimer()
    {
        CocoMachine machine = Create(CocoModel.Coco2, 12, 11, 64);
        machine.Run(2 * (ulong)CocoTiming.ClockHertz);
        Type(machine, "TIMER=0:FOR I=1 TO 300:NEXT:PRINT TIMER\r");
        string screen = Screen(machine);
        screen.Should().MatchRegex(@"\n *[1-9][0-9]* *\n");
    }

    /// <summary>
    ///  Builds a machine on the ROM dumps, or without them on the ROMs built from the SDK's sources.
    /// </summary>
    /// <param name="model">The model.</param>
    /// <param name="color">Color BASIC's version.</param>
    /// <param name="extended">Extended Color BASIC's version, or 0 for none.</param>
    /// <param name="kilobytes">The RAM.</param>
    /// <returns>The machine, reset.</returns>
    internal static CocoMachine Create(CocoModel model, int color, int extended, int kilobytes)
    {
        CocoRoms roms = CocoTestRoms.Load(model, color, extended);
        return new(new() { Model = model, RamKilobytes = kilobytes, LowercaseVdg = color == 13 }, roms);
    }

    /// <summary>
    ///  Types text and runs until it has been typed and half a second more.
    /// </summary>
    /// <param name="machine">The machine.</param>
    /// <param name="text">The text.</param>
    internal static void Type(CocoMachine machine, string text)
    {
        foreach (char character in text)
        {
            machine.Bus.Keyboard.Type((byte)character);
        }

        ulong limit = machine.Processor.CycleCount + (ulong)(text.Length * 200 * CocoTiming.CyclesPerMillisecond);
        while (machine.Bus.Keyboard.IsTyping && machine.Processor.CycleCount < limit)
        {
            machine.Run(1000);
        }

        machine.Run((ulong)(500 * CocoTiming.CyclesPerMillisecond));
    }

    /// <summary>
    ///  Reads the text screen.
    /// </summary>
    /// <param name="machine">The machine.</param>
    /// <returns>Its 16 rows, joined by newlines.</returns>
    internal static string Screen(CocoMachine machine) => string.Join('\n', machine.Bus.TextRows());
}
