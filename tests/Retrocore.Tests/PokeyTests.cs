// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Chips;

namespace Retrocore.Tests;

/// <summary>
///  POKEY timer, interrupt, noise, keyboard, pot, serial and audio tests, timed against the Altirra Hardware Reference
///  Manual's POKEY chapter.
/// </summary>
[TestClass]
public class PokeyTests
{
    private const int Audf1 = 0;
    private const int Audc1 = 1;
    private const int Audf2 = 2;
    private const int Audf3 = 4;
    private const int Audc3 = 5;
    private const int Audf4 = 6;
    private const int Audc4 = 7;
    private const int Audctl = 8;
    private const int Allpot = 8;
    private const int Stimer = 9;
    private const int Kbcode = 9;
    private const int Random = 10;
    private const int Skres = 10;
    private const int Potgo = 11;
    private const int Serin = 13;
    private const int Serout = 13;
    private const int Irqen = 14;
    private const int Irqst = 14;
    private const int Skctl = 15;
    private const int Skstat = 15;

    /// <summary>
    ///  Verifies an 8-bit 1.79 MHz timer first fires N+8 cycles after STIMER, then every N+4.
    /// </summary>
    /// <param name="audf">The AUDF1 value.</param>
    [TestMethod]
    [DataRow(0)]
    [DataRow(5)]
    [DataRow(255)]
    public void FastTimerFiresAfterNPlusFour(int audf)
    {
        Pokey pokey = Started();
        pokey.Write(Audctl, 0x40);
        pokey.Write(Audf1, (byte)audf);
        pokey.Write(Irqen, Pokey.Timer1Interrupt);
        pokey.Write(Stimer, 0);
        TicksUntilInterrupt(pokey, Pokey.Timer1Interrupt).Should().Be(audf + 8);
        pokey.InterruptRequest.Should().BeTrue();
        for (int period = 0; period < 3; period++)
        {
            Acknowledge(pokey, Pokey.Timer1Interrupt);
            TicksUntilInterrupt(pokey, Pokey.Timer1Interrupt).Should().Be(audf + 4);
        }
    }

    /// <summary>
    ///  Verifies timers on the 64 kHz and 15 kHz clocks fire (N+1)*28 or (N+1)*114 cycles apart, with the first period-0
    ///  firing 24 or 83 cycles after the SKCTL write that ends initialization mode.
    /// </summary>
    /// <param name="audctl">The AUDCTL value: 0 for 64 kHz, 1 for 15 kHz.</param>
    /// <param name="audf">The AUDF1 value.</param>
    /// <param name="first">The cycles from the SKCTL write to the first IRQ.</param>
    /// <param name="period">The cycles between IRQs.</param>
    [TestMethod]
    [DataRow(0, 0, 24, 28)]
    [DataRow(0, 3, 24 + (3 * 28), 4 * 28)]
    [DataRow(1, 0, 83, 114)]
    [DataRow(1, 2, 83 + (2 * 114), 3 * 114)]
    public void SlowTimerPeriodsAndClockPhase(int audctl, int audf, int first, int period)
    {
        Pokey pokey = new();
        pokey.Write(Audctl, (byte)audctl);
        pokey.Write(Audf1, (byte)audf);
        pokey.Write(Irqen, Pokey.Timer1Interrupt);
        pokey.Write(Stimer, 0);
        pokey.Write(Skctl, 0x03);
        TicksUntilInterrupt(pokey, Pokey.Timer1Interrupt).Should().Be(first);
        Acknowledge(pokey, Pokey.Timer1Interrupt);
        TicksUntilInterrupt(pokey, Pokey.Timer1Interrupt).Should().Be(period);
    }

    /// <summary>
    ///  Verifies linked timers 1+2 at 1.79 MHz count AUDF1 + 256 * AUDF2 with a period of N+7, raising timer 2's IRQ.
    /// </summary>
    [TestMethod]
    public void LinkedTimersCountSixteenBits()
    {
        Pokey pokey = Started();
        pokey.Write(Audctl, 0x50);
        pokey.Write(Audf1, 0x34);
        pokey.Write(Audf2, 0x12);
        pokey.Write(Irqen, Pokey.Timer2Interrupt);
        pokey.Write(Stimer, 0);
        TicksUntilInterrupt(pokey, Pokey.Timer2Interrupt).Should().Be(0x1234 + 11);
        Acknowledge(pokey, Pokey.Timer2Interrupt);
        TicksUntilInterrupt(pokey, Pokey.Timer2Interrupt).Should().Be(0x1234 + 7);
    }

    /// <summary>
    ///  Verifies the low timer of a linked pair fires AUDF2+1 times per high timer period.
    /// </summary>
    [TestMethod]
    public void LinkedLowTimerFiresEvery256()
    {
        Pokey pokey = Started();
        pokey.Write(Audctl, 0x50);
        pokey.Write(Audf1, 0x40);
        pokey.Write(Audf2, 0x01);
        pokey.Write(Irqen, Pokey.Timer1Interrupt | Pokey.Timer2Interrupt);
        pokey.Write(Stimer, 0);
        int lowFirings = 0;
        for (int cycle = 0; cycle < 0x140 + 11; cycle++)
        {
            pokey.Tick();
            if ((pokey.InterruptStatus & Pokey.Timer1Interrupt) == 0)
            {
                lowFirings++;
                Acknowledge(pokey, Pokey.Timer1Interrupt);
            }
        }

        lowFirings.Should().Be(2);
        (pokey.InterruptStatus & Pokey.Timer2Interrupt).Should().Be(0);
    }

    /// <summary>
    ///  Verifies disabled interrupts never latch, clearing IRQEN clears IRQST, and the serial output complete status
    ///  shows while idle even when disabled.
    /// </summary>
    [TestMethod]
    public void IrqenMasksAndClearsStatus()
    {
        Pokey pokey = Started();
        pokey.Write(Audctl, 0x40);
        pokey.Write(Stimer, 0);
        Advance(pokey, 20);
        pokey.Read(Irqst).Should().Be(0xF7);
        pokey.InterruptRequest.Should().BeFalse();

        pokey.Write(Irqen, Pokey.Timer1Interrupt);
        Advance(pokey, 4);
        pokey.Read(Irqst).Should().Be(0xF6);
        pokey.InterruptRequest.Should().BeTrue();
        pokey.Write(Irqen, 0);
        pokey.Read(Irqst).Should().Be(0xF7);
        pokey.InterruptRequest.Should().BeFalse();

        pokey.Write(Irqen, Pokey.SerialOutputCompleteInterrupt);
        pokey.InterruptRequest.Should().BeTrue();
    }

    /// <summary>
    ///  Verifies STIMER written four cycles after a previous STIMER preempts the AUDF1=0 timer's first IRQ.
    /// </summary>
    [TestMethod]
    public void StimerPreemptsUnderflow()
    {
        Pokey pokey = Started();
        pokey.Write(Audctl, 0x40);
        pokey.Write(Irqen, Pokey.Timer1Interrupt);
        pokey.Write(Stimer, 0);
        Advance(pokey, 4);
        pokey.Write(Stimer, 0);
        TicksUntilInterrupt(pokey, Pokey.Timer1Interrupt).Should().Be(8);

        pokey.Write(Stimer, 0);
        Advance(pokey, 5);
        pokey.Write(Stimer, 0);
        TicksUntilInterrupt(pokey, Pokey.Timer1Interrupt, acknowledgeFirst: true).Should().Be(3);
    }

    /// <summary>
    ///  Verifies RANDOM reads $FF in initialization mode and $1F four cycles after leaving it in 9-bit mode.
    /// </summary>
    [TestMethod]
    public void RandomHeldInInitializationMode()
    {
        Pokey pokey = new();
        pokey.Write(Audctl, 0x80);
        Advance(pokey, 50);
        pokey.Read(Random).Should().Be(0xFF);
        pokey.Write(Skctl, 0x03);
        Advance(pokey, 4);
        pokey.Read(Random).Should().Be(0x1F);
        pokey.Write(Skctl, 0x00);
        pokey.Read(Random).Should().Be(0xFF);
        Advance(pokey, 10);
        pokey.Read(Random).Should().Be(0xFF);
    }

    /// <summary>
    ///  Verifies RANDOM shifts right one bit per cycle in 17-bit mode and runs through 2^17-1 states.
    /// </summary>
    [TestMethod]
    public void RandomShiftsEveryCycle()
    {
        Pokey pokey = Started();
        byte previous = pokey.Read(Random);
        int changes = 0;
        for (int cycle = 0; cycle < 1000; cycle++)
        {
            pokey.Tick();
            byte value = pokey.Read(Random);
            (value & 0x7F).Should().Be(previous >> 1);
            if (value != previous) { changes++; }
            previous = value;
        }

        changes.Should().BeGreaterThan(900);
    }

    /// <summary>
    ///  Verifies the manual's 9-bit RANDOM sequence sampled once per scan line: 00 DF EE 16 B9.
    /// </summary>
    [TestMethod]
    public void NineBitRandomMatchesScanLineSamples()
    {
        Pokey pokey = new();
        pokey.Write(Audctl, 0x80);
        pokey.Write(Skctl, 0x03);
        byte[] samples = new byte[511 + (4 * 114) + 1];
        for (int cycle = 0; cycle < samples.Length; cycle++)
        {
            samples[cycle] = pokey.Read(Random);
            pokey.Tick();
        }

        byte[] expected = [0x00, 0xDF, 0xEE, 0x16, 0xB9];
        bool found = false;
        for (int start = 0; start < 511; start++)
        {
            int line = 0;
            while (line < expected.Length && samples[start + (line * 114)] == expected[line])
            {
                line++;
            }

            found |= line == expected.Length;
        }

        found.Should().BeTrue();
    }

    /// <summary>
    ///  Verifies a held key is confirmed on the second scan, 64 lines after first seen, latching KBCODE with the
    ///  keyboard IRQ and SKSTAT key down, and that release is debounced over two scans.
    /// </summary>
    [TestMethod]
    public void KeyPressLatchesAfterDebounce()
    {
        Pokey pokey = Started();
        pokey.Write(Irqen, Pokey.KeyboardInterrupt);
        pokey.SetKey(0x3F, pressed: true);

        // The scan reaches $3F on the 64th 15 kHz pulse (the first is 80 cycles after SKCTL) and confirms it 64 later.
        Advance(pokey, 80 + (126 * 114));
        pokey.InterruptRequest.Should().BeFalse();
        (pokey.Read(Skstat) & 0x04).Should().Be(0x04);
        Advance(pokey, 114);
        pokey.InterruptRequest.Should().BeTrue();
        pokey.Read(Irqst).Should().Be(0xB7);
        pokey.Read(Kbcode).Should().Be(0x3F);
        (pokey.Read(Skstat) & 0x04).Should().Be(0);

        pokey.SetKey(0x3F, pressed: false);
        Advance(pokey, 64 * 114);
        (pokey.Read(Skstat) & 0x04).Should().Be(0);
        Advance(pokey, 64 * 114);
        (pokey.Read(Skstat) & 0x04).Should().Be(0x04);
    }

    /// <summary>
    ///  Verifies Shift and Control set KBCODE bits 6 and 7, and Shift shows in SKSTAT bit 3.
    /// </summary>
    /// <param name="shift">Whether Shift is down.</param>
    /// <param name="control">Whether Control is down.</param>
    /// <param name="expected">The expected KBCODE.</param>
    [TestMethod]
    [DataRow(false, false, 0x2A)]
    [DataRow(true, false, 0x6A)]
    [DataRow(false, true, 0xAA)]
    public void ModifiersSetKbcodeBits(bool shift, bool control, int expected)
    {
        Pokey pokey = Started();
        pokey.Write(Irqen, Pokey.KeyboardInterrupt);
        pokey.Shift = shift;
        pokey.Control = control;
        pokey.SetKey(0x2A, pressed: true);
        Advance(pokey, 3 * 64 * 114);
        pokey.InterruptRequest.Should().BeTrue();
        pokey.Read(Kbcode).Should().Be((byte)expected);
        (pokey.Read(Skstat) & 0x08).Should().Be(shift ? 0 : 0x08);
    }

    /// <summary>
    ///  Verifies Control and Shift with a key in row $00-$07 form a phantom key, so debounce rejects the press.
    /// </summary>
    [TestMethod]
    public void ControlShiftPhantomBlocksKey()
    {
        Pokey pokey = Started();
        pokey.Write(Irqen, Pokey.KeyboardInterrupt);
        pokey.Shift = true;
        pokey.Control = true;
        pokey.SetKey(0x01, pressed: true);
        Advance(pokey, 4 * 64 * 114);
        pokey.InterruptRequest.Should().BeFalse();
    }

    /// <summary>
    ///  Verifies a second key latched while the keyboard IRQ is active signals an overrun, cleared by SKRES.
    /// </summary>
    [TestMethod]
    public void KeyboardOverrun()
    {
        Pokey pokey = Started();
        pokey.Write(Irqen, Pokey.KeyboardInterrupt);
        pokey.SetKey(0x3F, pressed: true);
        Advance(pokey, 3 * 64 * 114);
        pokey.SetKey(0x3F, pressed: false);
        Advance(pokey, 3 * 64 * 114);
        pokey.SetKey(0x15, pressed: true);
        Advance(pokey, 3 * 64 * 114);
        pokey.Read(Kbcode).Should().Be(0x15);
        (pokey.Read(Skstat) & 0x40).Should().Be(0);
        pokey.Write(Skres, 0);
        (pokey.Read(Skstat) & 0x40).Should().Be(0x40);
    }

    /// <summary>
    ///  Verifies Break raises IRQST bit 7 once per press, not again while held.
    /// </summary>
    [TestMethod]
    public void BreakRaisesInterruptOnPress()
    {
        Pokey pokey = Started();
        pokey.Write(Irqen, Pokey.BreakInterrupt);
        pokey.Break = true;
        Advance(pokey, 80 + (48 * 114));
        pokey.Read(Irqst).Should().Be(0x77);
        pokey.Write(Irqen, 0);
        pokey.Write(Irqen, Pokey.BreakInterrupt);
        Advance(pokey, 2 * 64 * 114);
        pokey.InterruptRequest.Should().BeFalse();
        pokey.Break = false;
        Advance(pokey, 64 * 114);
        pokey.Break = true;
        Advance(pokey, 64 * 114);
        pokey.InterruptRequest.Should().BeTrue();
    }

    /// <summary>
    ///  Verifies the slow pot scan counts once per 15 kHz pulse, latches each pot at its count, clears ALLPOT bits and
    ///  ends at 228.
    /// </summary>
    [TestMethod]
    public void SlowPotScan()
    {
        Pokey pokey = Started();
        for (int pot = 0; pot < 8; pot++)
        {
            pokey.SetPot(pot, 100);
        }

        pokey.SetPot(0, 5);
        pokey.SetPot(1, 0);
        pokey.SetPot(2, 250);
        pokey.Write(Potgo, 0);
        pokey.Read(Allpot).Should().Be(0xFD);
        pokey.Read(1).Should().Be(0);

        Advance(pokey, 80 + (3 * 114));
        pokey.Read(0).Should().Be(4);
        (pokey.Read(Allpot) & 1).Should().Be(1);
        Advance(pokey, 114);
        pokey.Read(0).Should().Be(5);
        (pokey.Read(Allpot) & 1).Should().Be(0);

        Advance(pokey, 222 * 114);
        pokey.Read(Allpot).Should().Be(0x04);
        Advance(pokey, 114);
        pokey.Read(Allpot).Should().Be(0);
        pokey.Read(0).Should().Be(5);
        pokey.Read(2).Should().Be(228);
        pokey.Read(3).Should().Be(100);
    }

    /// <summary>
    ///  Verifies fast pot scan counts each cycle and overruns to 229.
    /// </summary>
    [TestMethod]
    public void FastPotScan()
    {
        Pokey pokey = new();
        pokey.Write(Skctl, 0x07);
        pokey.SetPot(0, 5);
        pokey.SetPot(1, 250);
        pokey.Write(Potgo, 0);
        Advance(pokey, 5);
        (pokey.Read(Allpot) & 3).Should().Be(2);
        pokey.Read(0).Should().Be(5);
        Advance(pokey, 223);
        pokey.Read(Allpot).Should().Be(2);
        pokey.Tick();
        pokey.Read(Allpot).Should().Be(0);
        pokey.Read(1).Should().Be(229);
    }

    /// <summary>
    ///  Verifies SIO transmission at 19,040 baud (AUDF3=$28, AUDF4=$00 linked at 1.79 MHz, 94 cycles a bit): the
    ///  output ready IRQ when the shift register loads, the frame's bits on the line, then the complete status and
    ///  <see cref="Pokey.SerialByteSent"/> ten bit cells later.
    /// </summary>
    [TestMethod]
    public void SerialTransmitFrame()
    {
        Pokey pokey = new();
        List<(byte Value, int Cycle)> sent = [];
        int cycle = 0;
        pokey.SerialByteSent = value => sent.Add((value, cycle + 1));
        pokey.Write(Skctl, 0x23);
        pokey.Write(Audctl, 0x28);
        pokey.Write(Audf3, 0x28);
        pokey.Write(Audf4, 0x00);
        pokey.Write(Irqen, Pokey.SerialOutputReadyInterrupt);
        pokey.Write(Stimer, 0);
        pokey.Write(Serout, 0x4F);
        pokey.SerialOutputLevel.Should().BeTrue();

        while ((pokey.Read(Irqst) & Pokey.SerialOutputReadyInterrupt) != 0 && cycle < 1000)
        {
            pokey.Tick();
            cycle++;
        }

        int loaded = cycle;
        (pokey.Read(Irqst) & Pokey.SerialOutputCompleteInterrupt).Should().NotBe(0);
        loaded.Should().BeLessThanOrEqualTo(4 + (2 * 47));

        // Sample the middle of each bit cell: start, $4F least significant bit first, stop.
        bool[] expected = [false, true, true, true, true, false, false, true, false, true];
        for (int bit = 0; bit < 10; bit++)
        {
            for (int i = 0; i < (bit == 0 ? 47 : 94); i++)
            {
                pokey.Tick();
                cycle++;
            }

            pokey.SerialOutputLevel.Should().Be(expected[bit], $"bit {bit}");
        }

        while (sent.Count == 0 && cycle < 3000)
        {
            pokey.Tick();
            cycle++;
        }

        sent.Should().ContainSingle();
        sent[0].Value.Should().Be(0x4F);
        sent[0].Cycle.Should().Be(loaded + (10 * 94));
        (pokey.Read(Irqst) & Pokey.SerialOutputCompleteInterrupt).Should().Be(0);
        pokey.SerialOutputLevel.Should().BeTrue();
    }

    /// <summary>
    ///  Verifies back-to-back bytes: SEROUT reloaded after the ready IRQ goes out with no idle gap.
    /// </summary>
    [TestMethod]
    public void SerialTransmitBackToBack()
    {
        Pokey pokey = new();
        List<(byte Value, int Cycle)> sent = [];
        int cycle = 0;
        pokey.SerialByteSent = value => sent.Add((value, cycle + 1));
        pokey.Write(Skctl, 0x23);
        pokey.Write(Audctl, 0x28);
        pokey.Write(Audf3, 0x28);
        pokey.Write(Irqen, Pokey.SerialOutputReadyInterrupt);
        pokey.Write(Stimer, 0);
        pokey.Write(Serout, 0x31);
        byte next = 0x52;
        bool idleSeen = false;
        while (sent.Count < 2 && cycle < 5000)
        {
            pokey.Tick();
            cycle++;
            if (pokey.InterruptRequest)
            {
                pokey.Write(Irqen, 0);
                pokey.Write(Irqen, Pokey.SerialOutputReadyInterrupt);
                pokey.Write(Serout, next);
                next = 0;
            }

            if (sent.Count == 1 && (pokey.Read(Irqst) & Pokey.SerialOutputCompleteInterrupt) == 0)
            {
                idleSeen = true;
            }
        }

        sent.Select(s => s.Value).Should().Equal(0x31, 0x52);
        (sent[1].Cycle - sent[0].Cycle).Should().Be(10 * 94);
        idleSeen.Should().BeFalse();
    }

    /// <summary>
    ///  Verifies <see cref="Pokey.ReceiveByte"/> latches SERIN with IRQST bit 5, and that a second byte before the
    ///  interrupt is acknowledged overruns until SKRES.
    /// </summary>
    [TestMethod]
    public void ReceiveByteAndOverrun()
    {
        Pokey pokey = Started();
        pokey.Write(Irqen, Pokey.SerialInputReadyInterrupt);
        pokey.ReceiveByte(0x41);
        pokey.Read(Serin).Should().Be(0x41);
        (pokey.Read(Irqst) & Pokey.SerialInputReadyInterrupt).Should().Be(0);
        pokey.InterruptRequest.Should().BeTrue();
        (pokey.Read(Skstat) & 0x20).Should().Be(0x20);

        pokey.ReceiveByte(0x42);
        pokey.Read(Serin).Should().Be(0x42);
        (pokey.Read(Skstat) & 0x20).Should().Be(0);

        Acknowledge(pokey, Pokey.SerialInputReadyInterrupt);
        pokey.ReceiveByte(0x43);
        (pokey.Read(Skstat) & 0x20).Should().Be(0);
        pokey.Write(Skres, 0);
        (pokey.Read(Skstat) & 0x20).Should().Be(0x20);
        pokey.Read(Serin).Should().Be(0x43);
    }

    /// <summary>
    ///  Verifies a pure tone on channel 1 at 1.79 MHz toggles the output every N+4 cycles.
    /// </summary>
    [TestMethod]
    public void PureToneTogglesAtTimerPeriod()
    {
        Pokey pokey = Started();
        pokey.Write(Audctl, 0x40);
        pokey.Write(Audf1, 10);
        pokey.Write(Audc1, 0xAF);
        pokey.Write(Stimer, 0);

        // STIMER sets the output flip-flop, which channel 1's high-pass XOR inverts to silence.
        pokey.Output.Should().Be(0);
        int lastChange = -1;
        float level = pokey.Output;
        List<int> intervals = [];
        for (int cycle = 1; cycle <= 200; cycle++)
        {
            pokey.Tick();
            if (pokey.Output != level)
            {
                level = pokey.Output;
                level.Should().BeOneOf(0f, 15f);
                if (lastChange >= 0) { intervals.Add(cycle - lastChange); }
                lastChange = cycle;
            }
        }

        intervals.Should().HaveCountGreaterThan(5);
        intervals.Should().AllSatisfy(interval => interval.Should().Be(14));
    }

    /// <summary>
    ///  Verifies STIMER turns channels 1 and 2 off and 3 and 4 on with the high-pass filters off, and that volume-only
    ///  mode always sounds.
    /// </summary>
    [TestMethod]
    public void StimerAndVolumeOnlyLevels()
    {
        Pokey pokey = Started();
        pokey.Write(Audc1, 0xA1);
        pokey.Write(Audc3, 0xA4);
        pokey.Write(Audc4, 0xA8);
        pokey.Write(Stimer, 0);
        pokey.Output.Should().Be(12);
        pokey.Write(Audc1, 0x13);
        pokey.Output.Should().Be(15);
    }

    /// <summary>
    ///  Verifies two-tone mode: with a mark on the line timer 1 drives the output tone; force break selects timer 2.
    /// </summary>
    /// <param name="skctl">The SKCTL value.</param>
    /// <param name="expected">The expected cycles between output toggles.</param>
    [TestMethod]
    [DataRow(0x0B, 6 * 28)]
    [DataRow(0x8B, 8 * 28)]
    public void TwoToneSelectsTimer(int skctl, int expected)
    {
        Pokey pokey = Started();
        pokey.Write(Audf1, 5);
        pokey.Write(Audf2, 7);
        pokey.Write(Skctl, (byte)skctl);
        pokey.Write(Stimer, 0);
        bool level = pokey.SerialOutputLevel;
        int lastChange = -1;
        List<int> intervals = [];
        for (int cycle = 1; cycle <= 3000; cycle++)
        {
            pokey.Tick();
            if (pokey.SerialOutputLevel != level)
            {
                level = pokey.SerialOutputLevel;
                if (lastChange >= 0) { intervals.Add(cycle - lastChange); }
                lastChange = cycle;
            }
        }

        intervals.Should().HaveCountGreaterThan(5);
        intervals.Should().AllSatisfy(interval => interval.Should().Be(expected));
    }

    /// <summary>
    ///  Verifies unassigned registers read $FF and reads have no side effects.
    /// </summary>
    [TestMethod]
    public void UnassignedRegistersReadFF()
    {
        Pokey pokey = Started();
        pokey.Read(11).Should().Be(0xFF);
        pokey.Read(12).Should().Be(0xFF);
        pokey.Read(0x1C).Should().Be(0xFF);
        pokey.Peek(Skstat).Should().Be(pokey.Read(Skstat));
    }

    /// <summary>
    ///  Asynchronous receive at 600 baud, as the cassette handler sets it up (channels 3+4 linked at 1.79 MHz, $05CC,
    ///  SKCTL $13): the start bit's edge starts the timers, each bit is sampled near its middle, SERIN takes the
    ///  byte with IRQST bit 5, and a stop bit sampled low is a framing error until SKRES.
    /// </summary>
    /// <param name="value">The byte sent.</param>
    /// <param name="stop">The stop bit's level.</param>
    [TestMethod]
    [DataRow(0xA5, true)]
    [DataRow(0x00, true)]
    [DataRow(0xFF, true)]
    [DataRow(0x5A, false)]
    public void ReceivesBitsAsynchronously(int value, bool stop)
    {
        Pokey pokey = Started();
        pokey.Write(8, 0x28);
        pokey.Write(4, 0xCC);
        pokey.Write(6, 0x05);
        pokey.Write(Skctl, 0x13);
        pokey.Write(Irqen, Pokey.SerialInputReadyInterrupt);
        Advance(pokey, 5_000);
        (pokey.Read(Skstat) & 0x02).Should().Be(0x02, "the input isn't busy before a start bit");

        // One bit at 600 baud: 2,983 cycles; a frame of start, eight data bits LSB first, stop.
        const int bitCycles = 2_983;
        bool[] frame = new bool[10];
        frame[9] = stop;
        for (int bit = 0; bit < 8; bit++) { frame[bit + 1] = ((value >> bit) & 1) != 0; }
        foreach (bool level in frame)
        {
            pokey.SerialInputLevel = level;
            Advance(pokey, bitCycles);
        }

        pokey.SerialInputLevel = true;
        Advance(pokey, bitCycles);
        (pokey.Read(Irqst) & Pokey.SerialInputReadyInterrupt).Should().Be(0, "the byte is in");
        pokey.Read(13).Should().Be((byte)value);
        (pokey.Read(Skstat) & 0x80).Should().Be(stop ? 0x80 : 0, "a low stop bit is a framing error");
        pokey.Write(10, 0);
        (pokey.Read(Skstat) & 0x80).Should().Be(0x80, "SKRES clears it");
    }

    private static Pokey Started()
    {
        Pokey pokey = new();
        pokey.Write(Skctl, 0x03);
        return pokey;
    }

    private static void Advance(Pokey pokey, int cycles)
    {
        for (int i = 0; i < cycles; i++)
        {
            pokey.Tick();
        }
    }

    private static void Acknowledge(Pokey pokey, byte bit)
    {
        byte enable = pokey.InterruptEnable;
        pokey.Write(Irqen, (byte)(enable & ~bit));
        pokey.Write(Irqen, enable);
    }

    private static int TicksUntilInterrupt(Pokey pokey, byte bit, bool acknowledgeFirst = false)
    {
        if (acknowledgeFirst) { Acknowledge(pokey, bit); }
        for (int cycles = 1; cycles < 0x20000; cycles++)
        {
            pokey.Tick();
            if ((pokey.Read(Irqst) & bit) == 0) { return cycles; }
        }

        return -1;
    }
}
