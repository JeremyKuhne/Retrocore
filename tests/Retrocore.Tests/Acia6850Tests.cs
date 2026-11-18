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
