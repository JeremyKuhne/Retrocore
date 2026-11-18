// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Chips;

namespace Retrocore.Tests;

/// <summary>
///  The 6532 RIOT's and 6530 MIOT's timers and interrupts, register by register and clock by clock.
/// </summary>
[TestClass]
public class RiotTests
{
    // The 6532's timer: a write with A4 and A2 set, A0-A1 the prescaler and A3 the interrupt enable; a read with A2
    // set and A0 clear; the flags with A2 and A0 set; PA7's edge control a write with A2 set and A4 clear.
    private const int LoadTimer = 0x14;
    private const int EnableInterrupt = 0x08;
    private const int ReadTimer = 0x04;
    private const int ReadFlags = 0x05;
    private const int EdgeControl = 0x04;

    /// <summary>
    ///  The timer counts its value down at the prescaler's rate, the first count one clock long, and runs out a clock
    ///  after it reaches zero.
    /// </summary>
    /// <param name="prescaler">The address's low two bits.</param>
    /// <param name="clocks">The clocks a count takes.</param>
    [TestMethod]
    [DataRow(0, 1)]
    [DataRow(1, 8)]
    [DataRow(2, 64)]
    [DataRow(3, 1024)]
    public void EachPrescalerCountsAtItsRate(int prescaler, int clocks)
    {
        Riot6532 riot = new();
        riot.Write(LoadTimer | prescaler, 3);
        riot.Peek(ReadTimer).Should().Be(3);
        Advance(riot, 1);
        riot.Peek(ReadTimer).Should().Be(2);
        Advance(riot, (3 * clocks) - 1);
        riot.TimerExpired.Should().BeFalse();
        riot.Tick();
        riot.TimerExpired.Should().BeTrue();
        riot.Peek(ReadFlags).Should().Be(RiotBase.TimerFlag);
    }

    /// <summary>
    ///  A count of zero runs out at the next clock and one of 255 at the 256th; past zero the timer counts every clock
    ///  from 255.
    /// </summary>
    [TestMethod]
    public void ZeroAnd255RunOutAndTheCountGoesOn()
    {
        Riot6532 riot = new();
        riot.Write(LoadTimer, 0);
        riot.Tick();
        riot.TimerExpired.Should().BeTrue();

        riot.Write(LoadTimer, 255);
        Advance(riot, 255);
        riot.TimerExpired.Should().BeFalse();
        riot.Tick();
        riot.TimerExpired.Should().BeTrue();
        riot.Peek(ReadTimer).Should().Be(255);
        riot.Tick();
        riot.Peek(ReadTimer).Should().Be(254);
    }

    /// <summary>
    ///  A read in the clock the timer runs out leaves the flag it sets; a later read clears it and counts on from the
    ///  value read at the prescaler's rate.
    /// </summary>
    [TestMethod]
    public void AReadAfterTheTimeoutRearmsAtThePrescaler()
    {
        Riot6532 riot = new();
        riot.Write(LoadTimer | 1, 2);
        Advance(riot, 17);
        riot.TimerExpired.Should().BeTrue();
        riot.Read(ReadTimer);
        riot.TimerExpired.Should().BeTrue("a read in the clock it runs out does not clear it");

        Advance(riot, 10);
        byte value = riot.Read(ReadTimer);
        riot.TimerExpired.Should().BeFalse();
        riot.Tick();
        riot.Peek(ReadTimer).Should().Be((byte)(value - 1));
        Advance(riot, 7);
        riot.Peek(ReadTimer).Should().Be((byte)(value - 1));
        riot.Tick();
        riot.Peek(ReadTimer).Should().Be((byte)(value - 2));
    }

    /// <summary>
    ///  The timer interrupts only when the access that started it enables it; reading the flags leaves the timer's,
    ///  and reading the timer clears it with the enable its address gives.
    /// </summary>
    [TestMethod]
    public void TheTimerInterruptsOnlyWhenEnabled()
    {
        Riot6532 riot = new();
        riot.Write(LoadTimer, 0);
        riot.Tick();
        riot.InterruptRequested.Should().BeFalse();

        riot.Write(LoadTimer | EnableInterrupt, 0);
        riot.Tick();
        riot.InterruptRequested.Should().BeTrue();
        riot.Read(ReadFlags).Should().Be(RiotBase.TimerFlag);
        riot.InterruptRequested.Should().BeTrue();
        riot.Tick();
        riot.Read(ReadTimer);
        riot.InterruptRequested.Should().BeFalse();
    }

    /// <summary>
    ///  PA7's chosen edge, from outside or from the port's own output, sets its flag, which interrupts when enabled
    ///  and which reading the flags clears.
    /// </summary>
    [TestMethod]
    public void PA7EdgesSetTheirFlag()
    {
        Riot6532 riot = new();
        riot.Write(EdgeControl | 0x02, 0);
        riot.SetPortA(0x7F);
        riot.EdgeSeen.Should().BeTrue("the falling edge is chosen");
        riot.InterruptRequested.Should().BeTrue();
        riot.Read(ReadFlags).Should().Be(RiotBase.EdgeFlag);
        riot.InterruptRequested.Should().BeFalse();

        riot.Write(EdgeControl | 0x02 | 0x01, 0);
        riot.SetPortA(0x7F);
        riot.EdgeSeen.Should().BeFalse("no edge");
        riot.SetPortA(0xFF);
        riot.EdgeSeen.Should().BeTrue("the rising edge is chosen");
        riot.Read(ReadFlags);

        riot.Write(1, 0x80);
        riot.Write(0, 0x00);
        riot.EdgeSeen.Should().BeFalse("a falling edge with the rising one chosen");
        riot.Write(0, 0x80);
        riot.EdgeSeen.Should().BeTrue("the port's own output is the pin");

        riot.Write(EdgeControl, 0);
        riot.Write(0, 0x00);
        riot.Write(0, 0x80);
        riot.InterruptRequested.Should().BeFalse("the edge's interrupt is disabled");
    }

    /// <summary>
    ///  The 6530's timeout pulls PB7 low while PB7 is an input, and reading port B sees the pin.
    /// </summary>
    [TestMethod]
    public void The6530sTimeoutPullsPB7Low()
    {
        Miot6530 miot = new();
        miot.Read(2).Should().Be(0xFF);
        miot.Write(0x04 | EnableInterrupt, 0);
        miot.Tick();
        miot.InterruptRequested.Should().BeTrue();
        miot.PortBOutput.Should().Be(0x7F);
        miot.Read(2).Should().Be(0x7F);
        miot.Peek(2).Should().Be(0x7F);

        miot.Tick();
        miot.Read(0x04);
        miot.InterruptRequested.Should().BeFalse();
        miot.Read(2).Should().Be(0xFF);

        miot.Write(3, 0x80);
        miot.Write(0x04 | EnableInterrupt, 0);
        miot.Tick();
        miot.InterruptRequested.Should().BeFalse("PB7 is an output");
    }

    private static void Advance(RiotBase riot, int clocks)
    {
        for (int i = 0; i < clocks; i++) { riot.Tick(); }
    }
}
