// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Chips;

namespace Retrocore.Tests;

/// <summary>
///  The 6850's bit-clocked receiver and transmitter, and its modem lines.
/// </summary>
[TestClass]
public class Acia6850Tests
{
    // Divide by 1, 8 data bits, no parity, 1 stop bit (format 5).
    private const byte EightNone = 0x14;

    private static Acia6850 Ready(byte control = EightNone)
    {
        Acia6850 acia = new();
        acia.Write(0, 3);
        acia.Write(0, control);
        return acia;
    }

    // Clocks a character in at divide by 1: start bit, 8 data bits from bit 0, stop bit.
    private static void Send(Acia6850 acia, byte value)
    {
        acia.ClockReceive(data: false);
        for (int bit = 0; bit < 8; bit++) { acia.ClockReceive((value & (1 << bit)) != 0); }
        acia.ClockReceive(data: true);
    }

    /// <summary>
    ///  A character lost to an overrun shows only once the one before it has been read; RDRF stays set until the next
    ///  read.
    /// </summary>
    [TestMethod]
    public void OverrunShowsAfterTheValidCharacterIsRead()
    {
        Acia6850 acia = Ready();
        Send(acia, 0x41);
        Send(acia, 0x42);
        (acia.Status & Acia6850.Overrun).Should().Be(0);
        acia.Read(0);
        acia.Read(1).Should().Be(0x41);
        (acia.Status & (Acia6850.Overrun | Acia6850.ReceiveFull)).Should().Be(Acia6850.Overrun | Acia6850.ReceiveFull);
        acia.Read(0);
        acia.Read(1);
        (acia.Status & (Acia6850.Overrun | Acia6850.ReceiveFull)).Should().Be(0);
    }

    /// <summary>
    ///  DCD high holds the receiver idle; RDRF is hidden by the input, not by the latched rise.
    /// </summary>
    [TestMethod]
    public void CarrierLossHoldsTheReceiver()
    {
        Acia6850 acia = Ready();
        acia.DataCarrierDetect = true;
        acia.CanReceive.Should().BeFalse("a sender should hold its characters while the carrier is lost");
        Send(acia, 0x41);
        acia.Receive(0x42);
        acia.DataCarrierDetect = false;
        acia.CanReceive.Should().BeTrue("nothing arrives while the carrier is lost");

        Send(acia, 0x43);
        (acia.Status & (Acia6850.CarrierLost | Acia6850.ReceiveFull))
            .Should().Be(Acia6850.CarrierLost | Acia6850.ReceiveFull, "the rise is still latched, but the input is low");
    }

    /// <summary>
    ///  A rise of DCD interrupts, with the receive interrupt on, until the status and then the data are read: the data
    ///  alone, the status alone or a peek leave it, and a new rise between the two reads needs a new status read.
    /// </summary>
    /// <param name="carrierStaysLost">Whether DCD is still high when the interrupt is acknowledged.</param>
    [TestMethod]
    [DataRow(data: false)]
    [DataRow(data: true)]
    public void CarrierInterruptNeedsStatusThenData(bool carrierStaysLost)
    {
        Acia6850 acia = Ready(EightNone | 0x80);
        acia.DataCarrierDetect = true;
        acia.Interrupt.Should().BeTrue();
        if (!carrierStaysLost) { acia.DataCarrierDetect = false; }

        acia.Read(1);
        acia.Interrupt.Should().BeTrue("the data alone does not acknowledge it");
        acia.Peek(0);
        acia.Peek(1);
        acia.Interrupt.Should().BeTrue("a peek changes nothing");
        acia.Read(0);
        acia.Interrupt.Should().BeTrue("the status alone does not acknowledge it");
        acia.Read(1);
        acia.Interrupt.Should().BeFalse();
        ((acia.Status & Acia6850.CarrierLost) != 0).Should().Be(carrierStaysLost, "the bit then follows the input");

        // A new rise between the status and the data needs the status read again.
        acia.DataCarrierDetect = false;
        acia.DataCarrierDetect = true;
        acia.Read(0);
        acia.DataCarrierDetect = false;
        acia.DataCarrierDetect = true;
        acia.Read(1);
        acia.Interrupt.Should().BeTrue();
        acia.Read(0);
        acia.Read(1);
        acia.Interrupt.Should().BeFalse();
    }

    /// <summary>
    ///  Parity is checked in seven- and eight-bit formats, even and odd: a right parity bit gives the character with
    ///  no error, a wrong one the character with the parity error.
    /// </summary>
    /// <param name="format">The word format: 2 is 7E1, 3 7O1, 6 8E1 and 7 8O1.</param>
    /// <param name="value">The character.</param>
    [TestMethod]
    [DataRow(2, 0x41)]
    [DataRow(3, 0x41)]
    [DataRow(6, 0xC3)]
    [DataRow(7, 0xC3)]
    [DataRow(6, 0x80)]
    [DataRow(3, 0x00)]
    public void ParityIsChecked(int format, int value)
    {
        int dataBits = format < 4 ? 7 : 8;
        bool odd = format is 3 or 7;
        int ones = System.Numerics.BitOperations.PopCount((uint)value);
        bool right = ((ones & 1) != 0) ^ odd;
        foreach (bool parity in (bool[])[right, !right])
        {
            Acia6850 acia = Ready((byte)(format << 2));
            acia.ClockReceive(data: false);
            for (int bit = 0; bit < dataBits; bit++) { acia.ClockReceive((value & (1 << bit)) != 0); }
            acia.ClockReceive(parity);
            acia.ClockReceive(data: true);
            (acia.Status & Acia6850.ParityError).Should().Be(parity == right ? (byte)0 : Acia6850.ParityError);
            acia.Read(1).Should().Be((byte)value);
        }
    }

    /// <summary>
    ///  A carrier loss between receive clocks still drops the character being assembled.
    /// </summary>
    [TestMethod]
    public void CarrierPulseDropsAPartCharacter()
    {
        Acia6850 acia = Ready();
        acia.ClockReceive(data: false);
        for (int bit = 0; bit < 4; bit++) { acia.ClockReceive(data: true); }
        acia.DataCarrierDetect = true;
        acia.DataCarrierDetect = false;
        for (int bit = 0; bit < 5; bit++) { acia.ClockReceive(data: true); }
        acia.CanReceive.Should().BeTrue("the rest of the old frame is idle line, not a character");
    }

    /// <summary>
    ///  A format with fewer data bits, chosen while a character is under way, still lets it finish.
    /// </summary>
    [TestMethod]
    public void ShorterFormatMidCharacterFinishes()
    {
        Acia6850 acia = Ready();
        acia.ClockReceive(data: false);
        for (int bit = 0; bit < 7; bit++) { acia.ClockReceive(data: true); }
        acia.Write(0, 0x04);                    // format 1: 7 data bits, odd parity, 2 stop bits
        acia.ClockReceive(data: true);          // the eighth bit, past the new count: then parity
        acia.ClockReceive(data: true);          // the parity bit
        acia.ClockReceive(data: true);          // the stop bit
        acia.CanReceive.Should().BeFalse("the character finished");

        List<byte> sent = [];
        acia.Transmitted = sent.Add;
        acia.Write(0, EightNone);
        acia.Write(1, 0xFF);
        for (int clock = 0; clock < 8; clock++) { acia.ClockTransmit(); }
        acia.Write(0, 0x04);
        for (int clock = 0; clock < 6; clock++) { acia.ClockTransmit(); }
        sent.Should().HaveCount(1, "the character finished under the new format");
    }

    /// <summary>
    ///  A character from the line clears the errors of the one before it, whichever way it arrives.
    /// </summary>
    [TestMethod]
    public void ReceiveClearsTheLastErrors()
    {
        Acia6850 acia = Ready();
        acia.ClockReceive(data: false);
        for (int bit = 0; bit < 8; bit++) { acia.ClockReceive(data: true); }
        acia.ClockReceive(data: false);
        (acia.Status & Acia6850.FramingError).Should().Be(Acia6850.FramingError);
        acia.Read(1);
        acia.Receive(0x41);
        (acia.Status & Acia6850.FramingError).Should().Be(0);
    }

    /// <summary>
    ///  CTS high keeps a waiting character out of the character-at-a-time shift register.
    /// </summary>
    [TestMethod]
    public void ClearToSendHoldsTheTick()
    {
        Acia6850 acia = Ready();
        List<byte> sent = [];
        acia.Transmitted = sent.Add;
        acia.ClearToSend = true;
        acia.Write(1, 0x41);
        for (int i = 0; i < 5; i++) { acia.Tick(); }
        sent.Should().BeEmpty();
        acia.ClearToSend = false;
        for (int i = 0; i < 5; i++) { acia.Tick(); }
        sent.Should().Equal(0x41);
    }

    /// <summary>
    ///  A break holds the line low with a character waiting; the character goes once the break ends, and is reported
    ///  when its stop bit has left the line.
    /// </summary>
    [TestMethod]
    public void BreakHoldsAWaitingCharacter()
    {
        Acia6850 acia = Ready(EightNone | 0x60);
        List<byte> sent = [];
        acia.Transmitted = sent.Add;
        acia.Write(1, 0x55);
        for (int i = 0; i < 20; i++)
        {
            acia.ClockTransmit();
            acia.TransmitLevel.Should().BeFalse();
        }

        acia.Write(0, EightNone);
        acia.ClockTransmit();
        acia.TransmitLevel.Should().BeFalse("the start bit");
        for (int bit = 0; bit < 8; bit++)
        {
            acia.ClockTransmit();
            acia.TransmitLevel.Should().Be((0x55 & (1 << bit)) != 0);
        }

        acia.ClockTransmit();
        acia.TransmitLevel.Should().BeTrue("the stop bit");
        sent.Should().BeEmpty("the stop bit is still on the line");
        acia.ClockTransmit();
        sent.Should().Equal(0x55);
    }
}
