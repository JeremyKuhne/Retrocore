// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Coco;
using Retrocore.Media.Trs80;

namespace Retrocore.Tests;

/// <summary>
///  The Color Computer's cassette, joysticks, sound and cartridge port, driven through Color BASIC.
/// </summary>
[TestClass]
public class CocoPeripheralTests
{
    /// <summary>
    ///  CSAVE records a program that CLOAD reads back after NEW, through BASIC's own tape routines.
    /// </summary>
    [TestMethod]
    public void CassetteRoundTripsAProgram()
    {
        CocoMachine machine = Boot();
        CocoMachineTests.Type(machine, "10 print \"taped\"\r");
        CassetteImage tape = new();
        machine.Cassette.Record(tape, "test");
        CocoMachineTests.Type(machine, "csave \"prog\"\r");
        RunSeconds(machine, 8);
        tape.Bytes.Count.Should().BeGreaterThan(128 + 3 + 10, "the leader, header and program reached the tape");
        machine.Cassette.Eject();

        CocoMachineTests.Type(machine, "new\r");
        machine.Cassette.Play(tape, "test");
        CocoMachineTests.Type(machine, "cload\r");
        RunSeconds(machine, 8);
        CocoMachineTests.Type(machine, "run\r");
        CocoMachineTests.Screen(machine).Should().Contain("F PROG").And.Contain("TAPED");
    }

    /// <summary>
    ///  JOYSTK reads each axis through the DAC and comparator.
    /// </summary>
    [TestMethod]
    public void JoystickReadsThroughTheComparator()
    {
        CocoMachine machine = Boot();
        machine.Bus.Joysticks.Set(left: false, 10, 50);
        machine.Bus.Joysticks.Set(left: true, 63, 0);
        CocoMachineTests.Type(machine, "print joystk(0);joystk(1);joystk(2);joystk(3)\r");
        CocoMachineTests.Screen(machine).Should().Contain(" 10  50  63  0 ");
    }

    /// <summary>
    ///  A joystick button pulls PIA 0's PA0 low, as the keyboard's rows do; a program sees it while it is held.
    /// </summary>
    [TestMethod]
    public void JoystickButtonPullsPortALow()
    {
        CocoMachine machine = Boot();
        CocoMachineTests.Type(machine, "10 poke 1024,peek(65280) and 3:goto 10\rrun\r");
        machine.Bus.Peek(0x0400).Should().Be(3);
        machine.Bus.Joysticks.SetButton(left: false, second: false, pressed: true);
        RunSeconds(machine, 0.2);
        machine.Bus.Peek(0x0400).Should().Be(2);
    }

    /// <summary>
    ///  SOUND plays a tone through the DAC.
    /// </summary>
    [TestMethod]
    public void SoundPlaysThroughTheDac()
    {
        CocoMachine machine = Boot();
        PeakAudioSink sink = new();
        machine.Bus.Audio.Sink = sink;
        CocoMachineTests.Type(machine, "sound 100,10\r");
        machine.Bus.Audio.Flush();
        sink.Peak.Should().BeGreaterThan(0.2f);
    }

    /// <summary>
    ///  A ROM pack ties CART to Q, so Color BASIC's FIRQ handler starts it at <c>$C000</c>.
    /// </summary>
    [TestMethod]
    public void CartridgeStartsItself()
    {
        // $C000: LDA #$2A (an inverse * glyph), STA $0400, BRA *.
        byte[] rom = [0x86, 0x2A, 0xB7, 0x04, 0x00, 0x20, 0xFE];
        CocoMachine machine = CocoMachineTests.Create(CocoModel.Coco2, 12, 11, 64);
        machine.Bus.Cartridge = new(rom);

        // The FIRQ handler waits about a second, then initializes again before it jumps.
        RunSeconds(machine, 4);
        machine.Bus.Peek(0x0400).Should().Be(0x2A);
        machine.Processor.Registers.PC.Should().BeInRange(0xC005, 0xC006);
    }

    private static CocoMachine Boot()
    {
        CocoMachine machine = CocoMachineTests.Create(CocoModel.Coco2, 12, 11, 64);
        RunSeconds(machine, 2);
        return machine;
    }

    private static void RunSeconds(CocoMachine machine, double seconds) =>
        machine.Run((ulong)(seconds * CocoTiming.ClockHertz));
}
