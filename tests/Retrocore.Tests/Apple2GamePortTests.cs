// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Apple2;
using Retrocore.Machines.Devices;

namespace Retrocore.Tests;

/// <summary>
///  The game port: paddle timers started at $C070 and read at $C064-$C067, controller buttons joining the
///  keyboard's at $C061-$C063, and how a controller's stick and buttons drive them.
/// </summary>
[TestClass]
public class Apple2GamePortTests
{
    /// <summary>
    ///  A timer runs for 11 cycles a count plus 8, from the trigger; untriggered, it reads low.
    /// </summary>
    [TestMethod]
    public void TimersRunForTheirValue()
    {
        Apple2GamePort port = new();
        port.Timing(0, 50).Should().BeFalse("no trigger yet");
        port.SetPaddle(0, 100);
        port.Trigger(1000);
        port.Timing(0, 1000 + 100 * 11 + 7).Should().BeTrue();
        port.Timing(0, 1000 + 100 * 11 + 8).Should().BeFalse();
        port.Timing(1, 1000 + 255 * 11 + 7).Should().BeTrue("an unconnected paddle reads 255");
    }

    /// <summary>
    ///  The first controller is the joystick on paddles 0 and 1 with buttons 0 to 2; a second is paddles 2 and 3
    ///  and button 2; without controllers the paddles read 255 and the buttons are up.
    /// </summary>
    [TestMethod]
    public void ControllersDriveTheJoysticks()
    {
        Apple2GamePort port = new();
        ControllerState first = new("first", short.MinValue, short.MaxValue, ControllerButtons.South | ControllerButtons.West);
        ControllerState second = new("second", 0, 0, ControllerButtons.Right | ControllerButtons.Up | ControllerButtons.South);
        port.Apply([first, second]);

        Enumerable.Range(0, 4).Select(port.Paddle).Should().Equal(0, 255, 255, 0);
        Enumerable.Range(0, 3).Select(port.Button).Should().Equal(true, false, true);

        port.Apply([new("centered", 0, 0, ControllerButtons.East)]);
        Enumerable.Range(0, 4).Select(port.Paddle).Should().Equal(128, 128, 255, 255);
        Enumerable.Range(0, 3).Select(port.Button).Should().Equal(false, true, false);

        port.Apply([]);
        Enumerable.Range(0, 4).Select(port.Paddle).Should().Equal(255, 255, 255, 255);
        Enumerable.Range(0, 3).Select(port.Button).Should().Equal(false, false, false);
    }

    /// <summary>
    ///  On the bus, any access to $C070-$C07F starts the timers, bit 7 of $C064-$C067 follows them, and a button
    ///  reads down when the keyboard or a controller holds it.
    /// </summary>
    [TestMethod]
    public void TheBusReadsTheGamePort()
    {
        Apple2Bus bus = new(Apple2Model.IIPlus, Apple2Roms.FromBoardChips(new byte[12288], new byte[2048]));
        bus.GamePort.SetPaddle(2, 3);
        bus.Write(0xC07F, 0);
        (bus.Read(0xC066) & 0x80).Should().Be(0x80);
        for (int cycle = 0; cycle < 3 * 11 + 8; cycle++) { bus.Tick(); }
        (bus.Read(0xC066) & 0x80).Should().Be(0);

        (bus.Read(0xC061) & 0x80).Should().Be(0);
        bus.GamePort.SetButton(0, pressed: true);
        (bus.Read(0xC061) & 0x80).Should().Be(0x80);
        bus.SetButton(0, pressed: true);
        bus.GamePort.SetButton(0, pressed: false);
        (bus.Read(0xC061) & 0x80).Should().Be(0x80, "the keyboard's Open Apple still holds it");
    }

    /// <summary>
    ///  AppleSoft's PDL, through the Monitor's PREAD, reads the stick's positions, so programs see the controller.
    /// </summary>
    [TestMethod]
    public void PdlReadsTheController()
    {
        string directory = Environment.GetEnvironmentVariable("RETROCORE_IIPLUS_ROMS")
            ?? Path.Join(ExternalTestData.Root, "apple2-roms", "APPLE II+");

        if (!File.Exists(Path.Join(directory, "APPLE II+ - 341-0020 - APPLESOFT BASIC AUTOSTART MONITOR F800 - 2716.bin")))
        {
            Assert.Inconclusive("Set RETROCORE_IIPLUS_ROMS to the II Plus's chip dumps.");
        }

        Apple2Machine machine = new(Apple2Model.IIPlus, Apple2Roms.LoadFromDirectory(Apple2Model.IIPlus, directory));
        machine.Run(cycles: 2_000_000);
        machine.Bus.GamePort.Apply([new("pad", -16384, 16383, ControllerButtons.None)]);
        foreach (char key in "PRINT PDL(0);\"/\";PDL(1);\"/\";PDL(2)\r") { machine.Bus.QueueKey((byte)key); }
        machine.Run(cycles: 1_000_000);

        string screen = string.Join(
            "\n",
            Enumerable.Range(0, 24).Select(row => new string([.. Enumerable.Range(0, 40)
                .Select(column => (char)(machine.Bus.TextByte(row, column) & 0x7F))])));

        screen.Should().Contain("64/191/255");
    }
}
