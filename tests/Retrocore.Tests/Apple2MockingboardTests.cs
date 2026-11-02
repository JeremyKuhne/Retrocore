// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Apple2;

namespace Retrocore.Tests;

/// <summary>
///  Directed slot address, VIA/AY bus-control and stereo card tests.
/// </summary>
[TestClass]
public class Apple2MockingboardTests
{
    /// <summary>
    ///  Verifies each AY's register bus through the exact 4/7/6/5 control sequence.
    /// </summary>
    /// <param name="offset">The VIA base offset.</param>
    [TestMethod]
    [DataRow(0)]
    [DataRow(128)]
    public void AyBusControlStrobesLatchWriteAndReadRegisters(int offset)
    {
        Mockingboard card = new();
        Initialize(card, offset);
        Initialize(card, 128 - offset);
        WriteAy(card, offset, register: 1, value: 255);
        ReadAy(card, offset, register: 1).Should().Be(15);
        WriteAy(card, offset, register: 8, value: 255);
        ReadAy(card, offset, register: 8).Should().Be(31);
        WriteAy(card, offset, register: 0, value: 0xA5);
        ReadAy(card, offset, register: 0).Should().Be(0xA5);
        ReadAy(card, 128 - offset, register: 0).Should().Be(0);
    }

    /// <summary>
    ///  Verifies controls are strobed on entry rather than ticking or changing data while inactive.
    /// </summary>
    [TestMethod]
    public void InactiveAndHeldControlsDoNotRepeatStrobes()
    {
        Mockingboard card = new();
        Initialize(card, offset: 0);
        card.Write(1, 0);
        card.Write(0, 7);
        card.Write(0, 4);
        card.Write(1, 0x34);
        card.Write(0, 6);
        card.Write(1, 0x56);
        for (int cycle = 0; cycle < 100; cycle++)
        {
            card.Tick();
        }

        card.Write(0, 4);
        card.Write(3, 0);
        card.Write(0, 5);
        card.Peek(1).Should().Be(0x34);
        card.Read(1).Should().Be(0x34);
        card.Write(0, 4);
        card.Read(1).Should().Be(255);
        card.Write(3, 255);
        card.Write(1, 0x78);
        card.Write(0, 6);
        card.Write(0, 4);
        card.Write(3, 0);
        card.Write(0, 5);
        card.Read(1).Should().Be(0x78);
    }

    /// <summary>
    ///  Verifies active-low reset dominates all other control bits and remains held across clocks.
    /// </summary>
    [TestMethod]
    public void ActiveLowResetClearsOnlyTheSelectedPsg()
    {
        Mockingboard card = new();
        Initialize(card, offset: 0);
        Initialize(card, offset: 128);
        WriteAy(card, offset: 0, register: 7, value: 0x3F);
        WriteAy(card, offset: 0, register: 8, value: 15);
        WriteAy(card, offset: 128, register: 7, value: 0x3F);
        WriteAy(card, offset: 128, register: 8, value: 15);
        card.Left.Should().BeApproximately(1f / 3, 0.000001f);
        card.Right.Should().BeApproximately(1f / 3, 0.000001f);
        card.Write(0, 3);
        for (int cycle = 0; cycle < 100; cycle++)
        {
            card.Tick();
        }

        card.Left.Should().Be(0);
        card.Right.Should().BeApproximately(1f / 3, 0.000001f);
        card.Write(0, 4);
        ReadAy(card, offset: 0, register: 8).Should().Be(0);
        card.Reset();
        card.Left.Should().Be(0);
        card.Right.Should().Be(0);
        card.InterruptRequested.Should().BeFalse();
        card.Peek(2).Should().Be(0);
        card.Peek(0x82).Should().Be(0);
    }

    /// <summary>
    ///  Verifies PA/PB direction registers, invalid AY addresses and register mirroring.
    /// </summary>
    [TestMethod]
    public void DirectionRegistersAndAddressDecodeControlThePhysicalBus()
    {
        Mockingboard card = new();
        Initialize(card, offset: 0);
        card.Write(1, 0x17);
        card.Write(0, 7);
        card.Write(0, 4);
        card.Write(1, 0xFF);
        card.Write(0, 6);
        card.Write(0, 4);
        card.Write(3, 0);
        card.Write(0, 5);
        card.Read(1).Should().Be(255);
        ReadAy(card, offset: 0, register: 7).Should().Be(0);
        card.Write(3, 0);
        card.Write(1, 0x12);
        card.Read(1).Should().Be(255);
        card.Write(3, 255);
        card.Read(1).Should().Be(0x12);
        card.Write(0x73, 0xF0);
        card.Peek(3).Should().Be(0xF0);
        card.Peek(0x83).Should().Be(0);
        card.Write(2, 0);
        card.Write(0, 0);
        card.Left.Should().Be(0);
        card.Write(2, 255);
        ReadAy(card, offset: 0, register: 7).Should().Be(0);
    }

    /// <summary>
    ///  Verifies both timer interrupts combine and peeks never acknowledge them.
    /// </summary>
    [TestMethod]
    public void BothViaInterruptsCombineAndPeeksAreSideEffectFree()
    {
        Mockingboard card = new();
        card.Write(14, 192);
        card.Write(0x8E, 160);
        card.Write(4, 0);
        card.Write(5, 0);
        card.Write(0x88, 1);
        card.Write(0x89, 0);
        card.Tick();
        card.InterruptRequested.Should().BeFalse();
        card.Tick();
        card.InterruptRequested.Should().BeTrue();
        card.Tick();
        card.Peek(13).Should().Be(192);
        card.Peek(0x8D).Should().Be(160);
        for (int offset = 0; offset < 256; offset++)
        {
            _ = card.Peek((byte)offset);
        }

        card.Peek(13).Should().Be(192);
        card.Peek(0x8D).Should().Be(160);
        card.Read(4);
        card.InterruptRequested.Should().BeTrue();
        card.Read(0x88);
        card.InterruptRequested.Should().BeFalse();
    }

    /// <summary>
    ///  Without the Mockingboard mixed in, the mixer hears only the speaker: the same samples as silent AYs, though
    ///  the card is sounding.
    /// </summary>
    [TestMethod]
    public void SpeakerOnlyMixLeavesTheCardOut()
    {
        Mockingboard card = new();
        Initialize(card, offset: 0);
        WriteAy(card, offset: 0, register: 0, value: 1);
        WriteAy(card, offset: 0, register: 7, value: 0x3E);
        WriteAy(card, offset: 0, register: 8, value: 15);
        RecordingAudioTests speakerOnly = new();
        RecordingAudioTests silent = new();
        RecordingAudioTests mixed = new();
        Apple2Audio speakerAudio = new() { Sink = speakerOnly, MixMockingboard = false };
        Apple2Audio silentAudio = new() { Sink = silent };
        Apple2Audio mixedAudio = new() { Sink = mixed };
        for (int cycle = 0; cycle < 20000; cycle++)
        {
            card.Tick();
            bool speaker = (cycle & 512) != 0;
            speakerAudio.Tick(speaker, card);
            silentAudio.Tick(speaker, 0, 0);
            mixedAudio.Tick(speaker, card);
        }

        speakerAudio.Flush();
        silentAudio.Flush();
        mixedAudio.Flush();
        silent.Frames.Should().BeGreaterThan(900);
        speakerOnly.Samples.SequenceEqual(silent.Samples).Should().BeTrue();
        mixed.Samples.SequenceEqual(silent.Samples).Should().BeFalse("the card is sounding");
    }

    /// <summary>
    ///  Verifies independent stereo tone clocks through real VIA strobes.
    /// </summary>
    [TestMethod]
    public void CardToneOutputsRemainStereoAndAdvanceAtTheCpuClock()
    {
        Mockingboard card = new();
        Initialize(card, offset: 0);
        Initialize(card, offset: 128);
        WriteAy(card, offset: 0, register: 0, value: 1);
        WriteAy(card, offset: 0, register: 7, value: 0x3E);
        WriteAy(card, offset: 0, register: 8, value: 15);
        WriteAy(card, offset: 128, register: 0, value: 2);
        WriteAy(card, offset: 128, register: 7, value: 0x3E);
        WriteAy(card, offset: 128, register: 8, value: 15);
        for (int cycle = 0; cycle < 7; cycle++)
        {
            card.Tick();
        }

        card.Left.Should().Be(0);
        card.Right.Should().Be(0);
        card.Tick();
        card.Left.Should().BeApproximately(1f / 3, 0.000001f);
        card.Right.Should().Be(0);
        for (int cycle = 0; cycle < 8; cycle++)
        {
            card.Tick();
        }

        card.Left.Should().Be(0);
        card.Right.Should().BeApproximately(1f / 3, 0.000001f);
    }

    private static void Initialize(Mockingboard card, int offset)
    {
        card.Write((byte)(offset + 2), 255);
        card.Write((byte)offset, 0);
        card.Write((byte)(offset + 3), 255);
        card.Write((byte)offset, 4);
    }

    private static void WriteAy(Mockingboard card, int offset, byte register, byte value)
    {
        card.Write((byte)offset, 4);
        card.Write((byte)(offset + 3), 255);
        card.Write((byte)(offset + 1), register);
        card.Write((byte)offset, 7);
        card.Write((byte)offset, 4);
        card.Write((byte)(offset + 1), value);
        card.Write((byte)offset, 6);
        card.Write((byte)offset, 4);
    }

    private static byte ReadAy(Mockingboard card, int offset, byte register)
    {
        card.Write((byte)offset, 4);
        card.Write((byte)(offset + 3), 255);
        card.Write((byte)(offset + 1), register);
        card.Write((byte)offset, 7);
        card.Write((byte)offset, 4);
        card.Write((byte)(offset + 3), 0);
        card.Write((byte)offset, 5);
        byte value = card.Read((byte)(offset + 1));
        card.Write((byte)offset, 4);
        return value;
    }
}
