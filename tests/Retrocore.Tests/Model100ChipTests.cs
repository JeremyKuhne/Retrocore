// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Chips;

namespace Retrocore.Tests;

/// <summary>
///  The Model 100's chips, as their data sheets describe them: the 8155's ports and timer, the HD44102's addressing
///  and reads, and the uPD1990AC's shift register, commands and TP.
/// </summary>
[TestClass]
public sealed class Model100ChipTests
{
    /// <summary>
    ///  A continuous square wave of count 6 is high for 3 counts and low for 3, latching TC at each terminal count
    ///  until a status read clears it.
    /// </summary>
    [TestMethod]
    public void TimerMakesASquareWave()
    {
        Pio8155 pio = new();
        pio.Write(4, 6);
        pio.Write(5, 0x40);
        pio.Write(0, 0xC0);
        pio.TimerRunning.Should().BeTrue();

        List<bool> levels = [];
        for (int count = 0; count < 12; count++)
        {
            pio.Tick();
            levels.Add(pio.TimerOutput);
        }

        levels.Should().Equal(true, true, false, false, false, true, true, true, false, false, false, true);
        pio.Peek(0).Should().Be(0x40);
        pio.Read(0).Should().Be(0x40);
        pio.Read(0).Should().Be(0);
    }

    /// <summary>
    ///  A stopped timer's count registers read back the count and mode written, and a running one's the mode it runs.
    /// </summary>
    [TestMethod]
    public void StoppedTimerReadsWhatWasWritten()
    {
        Pio8155 pio = new();
        pio.Write(4, 6);
        pio.Write(5, 0x40);
        pio.Peek(4).Should().Be(6);
        pio.Peek(5).Should().Be(0x40);
        pio.Write(0, 0xC0);
        pio.Write(5, 0x80);
        pio.Peek(5).Should().Be(0x40, "the running timer keeps its mode until the next start");
    }

    /// <summary>
    ///  A start command while a single square wave runs takes the new count and mode at its terminal count, rather
    ///  than stopping there.
    /// </summary>
    [TestMethod]
    public void StartWhileRunningReloadsAtTerminalCount()
    {
        Pio8155 pio = new();
        pio.Write(4, 4);
        pio.Write(5, 0x00);
        pio.Write(0, 0xC0);
        pio.Tick();
        pio.Write(4, 6);
        pio.Write(5, 0x40);
        pio.Write(0, 0xC0);
        for (int count = 0; count < 3; count++) { pio.Tick(); }
        pio.TimerRunning.Should().BeTrue("the start took effect at terminal count");
        pio.Peek(4).Should().Be(6);
        pio.Peek(5).Should().Be(0x40);
        for (int count = 0; count < 12; count++) { pio.Tick(); }
        pio.TimerRunning.Should().BeTrue("the new mode is continuous");
    }

    /// <summary>
    ///  An odd count's square wave is high one count longer than it is low.
    /// </summary>
    [TestMethod]
    public void OddCountIsHighLonger()
    {
        Pio8155 pio = new();
        pio.Write(4, 5);
        pio.Write(5, 0x40);
        pio.Write(0, 0xC0);
        List<bool> levels = [];
        for (int count = 0; count < 5; count++)
        {
            pio.Tick();
            levels.Add(pio.TimerOutput);
        }

        levels.Should().Equal(true, true, false, false, true);
    }

    /// <summary>
    ///  A single square wave stops at its terminal count, and the stop command stops a continuous one at once.
    /// </summary>
    [TestMethod]
    public void TimerStops()
    {
        Pio8155 pio = new();
        pio.Write(4, 4);
        pio.Write(5, 0x00);
        pio.Write(0, 0xC0);
        for (int count = 0; count < 4; count++) { pio.Tick(); }
        pio.TimerRunning.Should().BeFalse();
        pio.TimerOutput.Should().BeTrue();

        pio.Write(5, 0x40);
        pio.Write(0, 0xC0);
        pio.Tick();
        pio.Tick();
        pio.Tick();
        pio.TimerOutput.Should().BeFalse();
        pio.Write(0, 0x40);
        pio.TimerRunning.Should().BeFalse();
        pio.TimerOutput.Should().BeTrue();
    }

    /// <summary>
    ///  Output ports read back their latches, input ports their pins, and port C its pins in its six bits.
    /// </summary>
    [TestMethod]
    public void PortsReadLatchesOrPins()
    {
        Pio8155 pio = new() { PortAInput = 0x5A, PortCInput = 0x15 };
        List<byte> written = [];
        pio.PortAWritten = written.Add;
        pio.Write(1, 0x81);
        pio.Read(1).Should().Be(0x5A, "port A is an input until the command makes it an output");
        pio.Write(0, 0x03);
        pio.Read(1).Should().Be(0x81);
        pio.Read(3).Should().Be(0xD5);
        written.Should().Equal(0x81);
    }

    /// <summary>
    ///  Setting an address and writing moves along the page, wrapping from 49 to 0; down mode moves the other way.
    /// </summary>
    [TestMethod]
    public void LcdWritesMoveAlongThePage()
    {
        Lcd44102 lcd = new();
        lcd.Write(data: false, (byte)(0x80 | 48));
        lcd.Write(data: true, 0x11);
        lcd.Write(data: true, 0x22);
        lcd.Write(data: true, 0x33);
        lcd[2, 48].Should().Be(0x11);
        lcd[2, 49].Should().Be(0x22);
        lcd[2, 0].Should().Be(0x33);

        lcd.Write(data: false, 0x3A);
        lcd.Write(data: false, (byte)(0x40 | 1));
        lcd.Write(data: true, 0x44);
        lcd.Write(data: true, 0x55);
        lcd[1, 1].Should().Be(0x44);
        lcd[1, 0].Should().Be(0x55);
        lcd.Column.Should().Be(49);
    }

    /// <summary>
    ///  The first read after setting an address is a dummy; each read then gives the byte at the address before it.
    /// </summary>
    [TestMethod]
    public void LcdReadsNeedADummy()
    {
        Lcd44102 lcd = new();
        lcd.Write(data: false, 10);
        lcd.Write(data: true, 0xA1);
        lcd.Write(data: true, 0xB2);
        lcd.Write(data: false, 10);
        _ = lcd.Read(data: true);
        lcd.Read(data: true).Should().Be(0xA1);
        lcd.Read(data: true).Should().Be(0xB2);
    }

    /// <summary>
    ///  The display shows nothing until it is turned on; the status shows it off and counting up from reset; the
    ///  start page scrolls the rows.
    /// </summary>
    [TestMethod]
    public void LcdStatusAndStartPage()
    {
        Lcd44102 lcd = new();
        lcd.Read(data: false).Should().Be(0x60);
        lcd.Write(data: false, 0);
        lcd.Write(data: true, 0x01);
        lcd.Dot(0, 0).Should().BeFalse();
        lcd.Write(data: false, 0x39);
        lcd.Read(data: false).Should().Be(0x40);
        lcd.Dot(0, 0).Should().BeTrue("bit 0 is the top dot of the page");
        lcd.Write(data: false, 0x7E);
        lcd.StartPage.Should().Be(1);
        lcd.Dot(24, 0).Should().BeTrue("page 0 is shown below pages 1 to 3");
        lcd.Dot(0, 0).Should().BeFalse();
    }

    /// <summary>
    ///  A time read loads the shift register, and shifting reads the time out from bit 0: BCD seconds, minutes,
    ///  hours and day, then the day of the week and the month.
    /// </summary>
    [TestMethod]
    public void ClockReadsOutItsTime()
    {
        Rtc1990 clock = new(4096);
        clock.SetTime(new DateTime(2026, 11, 26, 9, 30, 45));
        Command(clock, 3);
        Command(clock, 1);
        ulong value = 0;
        for (int bit = 0; bit < 40; bit++)
        {
            if (clock.DataOut) { value |= 1UL << bit; }
            clock.SetInputs(1, clock: true, dataIn: false);
            clock.SetInputs(1, clock: false, dataIn: false);
        }

        value.Should().Be(0xB4_26_09_30_45UL, "Thursday is 4 and November is $B");
    }

    /// <summary>
    ///  A TP command leaves the register mode as it was: after a time read and register shift, setting TP to 256 Hz
    ///  still shifts the time out.
    /// </summary>
    [TestMethod]
    public void TimingPulseCommandKeepsTheRegisterMode()
    {
        Rtc1990 clock = new(4096);
        clock.SetTime(new DateTime(2026, 11, 26, 9, 30, 45));
        Command(clock, 3);
        Command(clock, 1);
        Command(clock, 5);
        clock.TimingPulseHertz.Should().Be(256);
        int seconds = 0;
        for (int bit = 0; bit < 8; bit++)
        {
            if (clock.DataOut) { seconds |= 1 << bit; }
            clock.SetInputs(5, clock: true, dataIn: false);
            clock.SetInputs(5, clock: false, dataIn: false);
        }

        seconds.Should().Be(0x45);
    }

    /// <summary>
    ///  Shifting a time in and a time-set command set the counters, which then count on with the clock.
    /// </summary>
    [TestMethod]
    public void ClockSetsAndKeepsTime()
    {
        Rtc1990 clock = new(4096);
        Command(clock, 1);
        ulong value = 0xC2_31_23_59_58UL;
        for (int bit = 0; bit < 40; bit++)
        {
            bool dataIn = ((value >> bit) & 1) != 0;
            clock.SetInputs(1, clock: false, dataIn);
            clock.SetInputs(1, clock: true, dataIn);
        }

        Command(clock, 2);
        clock.Time(2026).Should().Be(new DateTime(2026, 12, 31, 23, 59, 58));
        clock.Weekday.Should().Be(2);
        for (int tick = 0; tick < 2 * 4096; tick++) { clock.Tick(); }
        clock.Time(2026).Should().Be(new DateTime(2026, 1, 1, 0, 0, 0), "the year is not the chip's");
        clock.Weekday.Should().Be(3);
    }

    /// <summary>
    ///  TP runs at 64 Hz from power-on, and the TP commands set it to 256 and 2048 Hz.
    /// </summary>
    [TestMethod]
    public void ClockTimingPulse()
    {
        Rtc1990 clock = new(Machines.Trs80Model100.Trs80Model100Timing.ClockHertz);
        clock.TimingPulseHertz.Should().Be(64);
        Command(clock, 5);
        clock.TimingPulseHertz.Should().Be(256);
        int rises = 0;
        bool last = clock.TimingPulse;
        for (int tick = 0; tick < Machines.Trs80Model100.Trs80Model100Timing.ClockHertz; tick++)
        {
            clock.Tick();
            if (clock.TimingPulse && !last) { rises++; }
            last = clock.TimingPulse;
        }

        rises.Should().Be(256);
        Command(clock, 6);
        clock.TimingPulseHertz.Should().Be(2048);
    }

    private static void Command(Rtc1990 clock, int command)
    {
        clock.SetInputs(command, clock: false, dataIn: false);
        clock.SetStrobe(strobe: true);
        clock.SetStrobe(strobe: false);
    }
}
