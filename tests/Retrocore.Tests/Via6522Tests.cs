// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Apple2;

namespace Retrocore.Tests;

/// <summary>
///  Directed VIA register, timer, interrupt, handshake and shift tests.
/// </summary>
[TestClass]
public class Apple2ViaTests
{
    /// <summary>
    ///  Verifies timed one-shots expire at N+2 and remain masked until enabled.
    /// </summary>
    /// <param name="timer">The timer number.</param>
    /// <param name="period">The programmed count.</param>
    [TestMethod]
    [DataRow(1, 0)]
    [DataRow(1, 1)]
    [DataRow(1, 255)]
    [DataRow(1, 65535)]
    [DataRow(2, 0)]
    [DataRow(2, 1)]
    [DataRow(2, 255)]
    [DataRow(2, 65535)]
    public void OneShotTimerExpiryMaskingAndAccessClears(int timer, int period)
    {
        Via6522 via = new();
        byte low = timer == 1 ? (byte)4 : (byte)8;
        byte high = (byte)(low + 1);
        byte flag = timer == 1 ? (byte)64 : (byte)32;
        via.Write(low, (byte)period);
        via.Write(high, (byte)(period >> 8));
        via.Peek(low).Should().Be((byte)period);
        Advance(via, period + 1);
        via.Peek(13).Should().Be(0);
        via.Tick();
        via.Peek(13).Should().Be(flag);
        via.InterruptRequested.Should().BeFalse();
        via.Write(14, (byte)(128 | flag));
        via.InterruptRequested.Should().BeTrue();
        via.Peek(13).Should().Be((byte)(128 | flag));
        via.Peek(low).Should().Be(255);
        via.Read(high).Should().Be(255);
        via.InterruptRequested.Should().BeTrue();
        via.Read(low).Should().Be(255);
        via.InterruptRequested.Should().BeFalse();
        Advance(via, 65536);
        via.Peek(13).Should().Be(0);
        via.Write(high, (byte)(period >> 8));
        Advance(via, period + 2);
        via.InterruptRequested.Should().BeTrue();
        via.Write(13, flag);
        via.Peek(13).Should().Be(0);
    }

    /// <summary>
    ///  Verifies continuous T1 cadence, PB7 toggles and a latch update without timer restart.
    /// </summary>
    [TestMethod]
    public void FreeRunningTimerUsesLatchAndExactCadence()
    {
        Via6522 via = new();
        via.Write(2, 128);
        via.Write(11, 192);
        via.Write(14, 192);
        via.Write(4, 2);
        via.Write(5, 0);
        (via.PortB & 128).Should().Be(0);
        for (int expiration = 0; expiration < 6; expiration++)
        {
            Advance(via, 3);
            via.InterruptRequested.Should().BeFalse();
            via.Tick();
            via.InterruptRequested.Should().BeTrue();
            (via.PortB & 128).Should().Be((expiration & 1) == 0 ? 128 : 0);
            via.Read(4);
        }

        via.Write(6, 4);
        via.Write(7, 0);
        Advance(via, 4);
        via.InterruptRequested.Should().BeTrue();
        via.Read(4);
        Advance(via, 5);
        via.InterruptRequested.Should().BeFalse();
        via.Tick();
        via.InterruptRequested.Should().BeTrue();
        via.Write(7, 0);
        via.InterruptRequested.Should().BeFalse();
    }

    /// <summary>
    ///  Verifies T2 pulse counting ignores CPU clocks and rising PB6 edges.
    /// </summary>
    [TestMethod]
    public void Timer2CountsOnlyFallingPb6AndOnlyInterruptsOnce()
    {
        Via6522 via = new();
        via.Write(11, 32);
        via.Write(14, 160);
        via.Write(8, 1);
        via.Write(9, 0);
        Advance(via, 1000);
        via.Peek(8).Should().Be(1);
        via.PortBInput = 191;
        via.Peek(8).Should().Be(0);
        via.InterruptRequested.Should().BeFalse();
        via.PortBInput = 255;
        via.Peek(8).Should().Be(0);
        via.PortBInput = 191;
        via.InterruptRequested.Should().BeTrue();
        via.Read(8);
        for (int pulse = 0; pulse < 65536; pulse++)
        {
            via.PortBInput = 255;
            via.PortBInput = 191;
        }

        via.InterruptRequested.Should().BeFalse();
    }

    /// <summary>
    ///  Verifies T2 observes physical PB6 rather than input state hidden by an output DDR.
    /// </summary>
    [TestMethod]
    public void Timer2PulseCountingHonorsPortBDirection()
    {
        Via6522 via = new();
        via.Write(0, 64);
        via.Write(2, 64);
        via.Write(11, 32);
        via.Write(8, 1);
        via.Write(9, 0);
        via.PortBInput = 191;
        via.Peek(8).Should().Be(1);
        via.Write(0, 0);
        via.Peek(8).Should().Be(0);
        via.Write(0, 64);
        via.Write(2, 0);
        via.Peek(13).Should().Be(32);
    }

    /// <summary>
    ///  Verifies IER set/clear semantics never discard pending flags and IFR bit 7 is computed.
    /// </summary>
    [TestMethod]
    public void InterruptEnableAndFlagWritesAreIndependent()
    {
        Via6522 via = new();
        via.CA1 = false;
        via.CB1 = false;
        via.Peek(13).Should().Be(18);
        via.Peek(14).Should().Be(128);
        via.Write(14, 130);
        via.InterruptRequested.Should().BeTrue();
        via.Write(14, 2);
        via.InterruptRequested.Should().BeFalse();
        via.Peek(13).Should().Be(18);
        via.Write(14, 144);
        via.Write(13, 128);
        via.Peek(13).Should().Be(146);
        via.Write(13, 16);
        via.Peek(13).Should().Be(2);
        via.Write(14, 130);
        via.Write(15, 123);
        via.Read(15);
        via.InterruptRequested.Should().BeTrue();
        via.Read(1);
        via.InterruptRequested.Should().BeFalse();
    }

    /// <summary>
    ///  Verifies DDRs, port latches and capture on the active CA1/CB1 edges.
    /// </summary>
    [TestMethod]
    public void PortsMixDdrsAndCaptureInputOnControlEdges()
    {
        Via6522 via = new();
        via.PortAInput = 0x5A;
        via.PortBInput = 0xA5;
        via.Write(1, 0xC3);
        via.Write(0, 0x3C);
        via.Peek(1).Should().Be(0x5A);
        via.Peek(0).Should().Be(0xA5);
        via.Write(3, 0xF0);
        via.Write(2, 0x0F);
        via.Peek(1).Should().Be(0xCA);
        via.Peek(0).Should().Be(0xAC);
        via.Write(11, 3);
        via.CA1 = false;
        via.CB1 = false;
        via.PortAInput = 0xFF;
        via.PortBInput = 0xFF;
        via.Peek(1).Should().Be(0xCA);
        via.Peek(0).Should().Be(0xAC);
        via.PortA.Should().Be(0xCF);
        via.PortB.Should().Be(0xFC);
        via.Write(12, 17);
        via.CA1 = true;
        via.CB1 = true;
        via.Peek(1).Should().Be(0xCF);
        via.Peek(0).Should().Be(0xFC);
    }

    /// <summary>
    ///  Verifies independent input flags, no-handshake alias and handshake versus pulse outputs.
    /// </summary>
    [TestMethod]
    public void ControlPinsHaveIndependentFlagsAndHandshakeOutputs()
    {
        Via6522 via = new();
        via.Write(12, 0x22);
        via.CA2 = false;
        via.CB2 = false;
        via.Peek(13).Should().Be(9);
        via.Read(1);
        via.Read(0);
        via.Peek(13).Should().Be(9);
        via.Write(13, 9);
        via.Write(12, 0x88);
        via.Write(15, 1);
        via.CA2Output.Should().BeTrue();
        via.Read(15);
        via.CA2Output.Should().BeTrue();
        via.Read(1);
        via.CA2Output.Should().BeFalse();
        via.Read(0);
        via.CB2Output.Should().BeTrue();
        via.Write(0, 1);
        via.CB2Output.Should().BeFalse();
        via.Tick();
        via.CA2Output.Should().BeFalse();
        via.CB2Output.Should().BeFalse();
        via.CA1 = false;
        via.CB1 = false;
        via.CA2Output.Should().BeTrue();
        via.CB2Output.Should().BeTrue();
        via.Write(12, 0xAA);
        via.Write(1, 0);
        via.Write(0, 0);
        via.CA2Output.Should().BeFalse();
        via.CB2Output.Should().BeFalse();
        via.Tick();
        via.CA2Output.Should().BeTrue();
        via.CB2Output.Should().BeTrue();
        via.Write(12, 0xCC);
        via.CA2Output.Should().BeFalse();
        via.CB2Output.Should().BeFalse();
        via.Write(12, 0xEE);
        via.CA2Output.Should().BeTrue();
        via.CB2Output.Should().BeTrue();
    }

    /// <summary>
    ///  Verifies dependent control flags clear on access and positive edges can be selected.
    /// </summary>
    [TestMethod]
    public void ControlInputPositiveEdgesAndDependentClears()
    {
        Via6522 via = new();
        via.CA2 = false;
        via.CB2 = false;
        via.Read(1);
        via.Peek(13).Should().Be(8);
        via.Write(0, 0);
        via.Peek(13).Should().Be(0);
        via.Write(12, 0x44);
        via.CA2 = true;
        via.CB2 = true;
        via.Peek(13).Should().Be(9);
        via.Read(1);
        via.Read(0);
        via.Peek(13).Should().Be(0);
    }

    /// <summary>
    ///  Verifies both external serial modes transfer MSB-first and acknowledge completion.
    /// </summary>
    [TestMethod]
    public void ExternalSerialTransfersInputAndOutputBytes()
    {
        Via6522 input = new();
        input.Write(11, 12);
        input.Write(14, 132);
        input.Write(10, 0);
        const byte Data = 0xA6;
        for (int bit = 7; bit >= 0; bit--)
        {
            input.CB1 = false;
            input.CB2 = (Data & (1 << bit)) != 0;
            input.InterruptRequested.Should().BeFalse();
            input.CB1 = true;
        }

        input.Peek(10).Should().Be(Data);
        input.InterruptRequested.Should().BeTrue();
        input.Read(10).Should().Be(Data);
        input.InterruptRequested.Should().BeFalse();
        Via6522 output = new();
        output.Write(11, 28);
        output.Write(10, Data);
        int received = 0;
        for (int bit = 0; bit < 8; bit++)
        {
            received = (received << 1) | (output.CB2Output ? 1 : 0);
            output.CB1 = false;
            output.CB1 = true;
        }

        received.Should().Be(Data);
        output.Peek(13).Should().Be(4);
        output.Peek(10).Should().Be(Data);
        output.Write(10, 0x51);
        output.Peek(13).Should().Be(0);
    }

    /// <summary>
    ///  Verifies unrelated ACR bits do not terminate an in-progress serial transfer.
    /// </summary>
    [TestMethod]
    public void AuxiliaryControlTimerChangesPreserveActiveSerialMode()
    {
        Via6522 via = new();
        via.Write(11, 8);
        via.CB2 = true;
        via.Write(10, 0);
        Advance(via, 8);
        via.Peek(10).Should().Be(15);
        via.Write(11, 72);
        Advance(via, 8);
        via.Peek(10).Should().Be(255);
        via.Peek(13).Should().Be(4);
    }

    /// <summary>
    ///  Verifies generated serial modes, timer-low clock cadence and mode-four recycling.
    /// </summary>
    /// <param name="mode">The shift mode.</param>
    [TestMethod]
    [DataRow(1)]
    [DataRow(2)]
    [DataRow(4)]
    [DataRow(5)]
    [DataRow(6)]
    public void GeneratedSerialModesUseTheirClockAndCompletionRules(int mode)
    {
        Via6522 via = new();
        via.Write(8, 2);
        via.Write(11, (byte)(mode << 2));
        via.CB2 = true;
        via.Write(10, 0xA5);
        int halfPeriod = mode is 2 or 6 ? 1 : 4;
        for (int bit = 0; bit < 8; bit++)
        {
            Advance(via, halfPeriod);
            via.CB1Output.Should().BeFalse();
            if (bit < 7 || mode < 4)
            {
                via.Peek(13).Should().Be(0);
            }

            Advance(via, halfPeriod);
            via.CB1Output.Should().BeTrue();
        }

        if (mode == 4)
        {
            via.Peek(13).Should().Be(0);
            via.Peek(10).Should().Be(0xA5);
            Advance(via, 128);
            via.Peek(13).Should().Be(0);
            via.Peek(10).Should().Be(0xA5);
        }
        else
        {
            via.Peek(13).Should().Be(4);
            via.Peek(10).Should().Be(mode < 4 ? (byte)255 : (byte)0xA5);
            via.Read(10);
            via.Peek(13).Should().Be(0);
        }
    }

    /// <summary>
    ///  Verifies disabled shifting, peeks without acknowledgement and a complete explicit reset.
    /// </summary>
    [TestMethod]
    public void PeekAndResetDoNotHidePendingState()
    {
        Via6522 via = new();
        via.Write(10, 0x80);
        Advance(via, 100);
        via.CB1 = false;
        via.CB1 = true;
        via.Peek(10).Should().Be(0x80);
        via.CA1 = false;
        via.Write(14, 255);
        byte flags = via.Peek(13);
        for (byte register = 0; register < 16; register++)
        {
            _ = via.Peek(register);
        }

        via.Peek(13).Should().Be(flags);
        via.Reset();
        via.Peek(13).Should().Be(0);
        via.Peek(14).Should().Be(128);
        via.Peek(2).Should().Be(0);
        via.Peek(3).Should().Be(0);
        via.Peek(10).Should().Be(0);
        via.Peek(11).Should().Be(0);
        via.Peek(12).Should().Be(0);
        via.Peek(4).Should().Be(255);
        via.Peek(8).Should().Be(255);
        via.CA2Output.Should().BeTrue();
        via.CB2Output.Should().BeTrue();
        via.InterruptRequested.Should().BeFalse();
    }

    private static void Advance(Via6522 via, int cycles)
    {
        for (int cycle = 0; cycle < cycles; cycle++)
        {
            via.Tick();
        }
    }
}
