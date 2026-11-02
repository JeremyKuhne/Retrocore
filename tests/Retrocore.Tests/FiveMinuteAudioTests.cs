// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Apple2;
using System.Diagnostics;

namespace Retrocore.Tests;

/// <summary>
///  Original synthetic CPU/VIA/speaker/PSG/PCM clock integration, without external firmware.
///  This is not a PT3 player, song fixture, audible comparison or PT3 playback gate.
/// </summary>
[TestClass]
public sealed class FiveMinuteAudioTests
{
    /// <summary>
    ///  Gets or sets the test output context.
    /// </summary>
    public TestContext? TestContext { get; set; }

    /// <summary>
    ///  Runs five minutes of actual NMOS 6502 instructions and IRQ handling with a 50 Hz T1.
    ///  The expiry on the final clock remains pending, so 15,000 expiries yield 14,999 handlers.
    ///  Exact expiry times and bounded handler latency distinguish CPU jitter from timer drift.
    /// </summary>
    [TestMethod]
    [Timeout(240000)]
    public void CpuIrqAndStereoPcmKeepExactTimeForFiveMinutes()
    {
        TestContext context = TestContext ?? throw new InvalidOperationException("The test runner must supply a context.");
        const int Cycles = 306_150_000;
        const int Period = 20_410;
        const int TimerLatch = Period - 2;
        const int ExpectedExpiries = 15_000;
        const int MaximumIrqLatency = 20;
        const int MaximumCadenceError = 4;
        const int LeftTonePeriod = 113;
        const int RightTonePeriod = 257;
        byte[] system = new byte[16384];
        system[0x3FFA] = 0;
        system[0x3FFB] = 3;
        system[0x3FFC] = 0;
        system[0x3FFD] = 2;
        system[0x3FFE] = 0;
        system[0x3FFF] = 3;
        Apple2Machine machine = new(Apple2Model.IIe, new Apple2Roms(system, new byte[4096]));
        Apple2Bus bus = machine.Bus;
        bus.InstallMockingboard();
        Mockingboard card = bus.Mockingboard;
        RecordingAudioTests sink = new();
        bus.Audio.Sink = sink;

        // CLI; loop: NOP; JMP loop. The IRQ handler preserves A, acknowledges T1,
        // increments a 16-bit zero-page counter, toggles the speaker and returns with RTI.
        Load(bus, address: 0x0200, [0x58, 0xEA, 0x4C, 0x01, 0x02]);
        Load(
            bus,
            address: 0x0300,
            [
            0x48,
            0xAD, 0x04, 0xC4,
            0xE6, 0x00,
            0xD0, 0x02,
            0xE6, 0x01,
            0xAD, 0x30, 0xC0,
            0x68, 0x40
        ]);

        InitializeAy(bus, offset: 0);
        InitializeAy(bus, offset: 128);
        WriteAy(bus, offset: 0, register: 0, value: LeftTonePeriod);
        WriteAy(bus, offset: 0, register: 7, value: 0x3E);
        WriteAy(bus, offset: 0, register: 8, value: 10);
        WriteAy(bus, offset: 128, register: 0, value: RightTonePeriod & 255);
        WriteAy(bus, offset: 128, register: 1, value: RightTonePeriod >> 8);
        WriteAy(bus, offset: 128, register: 7, value: 0x3E);
        WriteAy(bus, offset: 128, register: 8, value: 8);
        bus.Write(0xC40B, 0x40);
        bus.Write(0xC40E, 0xC0);
        bus.Write(0xC404, TimerLatch & 255);
        bus.Write(0xC405, TimerLatch >> 8);
        int expiries = 0;
        int acknowledgements = 0;
        int handlerEntries = 0;
        int speakerTransitions = 0;
        int cliFetches = 0;
        int nopFetches = 0;
        int leftTransitions = 0;
        int rightTransitions = 0;
        int maximumCadenceError = 0;
        ulong minimumLatency = ulong.MaxValue;
        ulong maximumLatency = 0;
        ulong previousAcknowledgement = 0;
        bool previousIrq = false;
        bool previousSpeaker = false;
        float previousLeft = card.Left;
        float previousRight = card.Right;
        Stopwatch elapsed = Stopwatch.StartNew();
        for (int index = 0; index < Cycles; index++)
        {
            ProcessorCycle cycle = machine.NextCycle();
            ulong time = bus.CycleCount;
            bool irq = card.InterruptRequested;
            if (irq && !previousIrq)
            {
                expiries++;
                ulong expectedTime = (ulong)expiries * Period;
                if (time != expectedTime)
                {
                    Assert.Fail($"T1 expiry {expiries}: expected clock {expectedTime}, observed {time}.");
                }
            }

            previousIrq = irq;
            if (cycle.IsOpcodeFetch)
            {
                if (cycle.Address == 0x0300) { handlerEntries++; }
                if (cycle.Address == 0x0200 && cycle.Value == 0x58) { cliFetches++; }
                if (cycle.Address == 0x0201 && cycle.Value == 0xEA) { nopFetches++; }
            }

            if (cycle.Operation == BusOperation.Read && cycle.Address == 0xC404)
            {
                acknowledgements++;
                ulong latency = time - ((ulong)acknowledgements * Period);
                minimumLatency = Math.Min(minimumLatency, latency);
                maximumLatency = Math.Max(maximumLatency, latency);
                if (latency is 0 or > MaximumIrqLatency)
                {
                    Assert.Fail($"IRQ acknowledgement {acknowledgements}: latency {latency} clocks.");
                }

                if (previousAcknowledgement != 0)
                {
                    int error = (int)Math.Abs((long)(time - previousAcknowledgement) - Period);
                    maximumCadenceError = Math.Max(maximumCadenceError, error);
                    if (error > MaximumCadenceError)
                    {
                        Assert.Fail($"IRQ acknowledgement {acknowledgements}: cadence error {error} clocks.");
                    }
                }

                previousAcknowledgement = time;
            }

            if (cycle.Operation == BusOperation.Read && cycle.Address == 0xC030)
            {
                if (bus.Speaker == previousSpeaker)
                {
                    Assert.Fail($"Speaker read at clock {time} did not toggle the latch.");
                }

                previousSpeaker = bus.Speaker;
                speakerTransitions++;
            }

            // AY tone edges lie on eight-clock boundaries, so this sampling misses no transitions.
            if ((index & 7) == 7)
            {
                float left = card.Left;
                float right = card.Right;
                if (left != previousLeft) { leftTransitions++; }
                if (right != previousRight) { rightTransitions++; }
                previousLeft = left;
                previousRight = right;
            }

            if ((index & 65535) == 0 && elapsed.ElapsedMilliseconds > 180000)
            {
                Assert.Fail($"Five-minute integration exceeded its 180-second execution budget at clock {time}.");
            }
        }

        elapsed.Stop();
        bus.Audio.Flush();
        bus.CycleCount.Should().Be((ulong)Cycles);
        machine.Processor.CycleCount.Should().Be((ulong)Cycles);
        machine.Processor.Status.Should().Be(ProcessorExecutionStatus.Running);
        cliFetches.Should().Be(1);
        nopFetches.Should().BeGreaterThan(ExpectedExpiries);
        expiries.Should().Be(ExpectedExpiries);
        acknowledgements.Should().Be(ExpectedExpiries - 1);
        handlerEntries.Should().Be(acknowledgements);
        (bus.Peek(0) | (bus.Peek(1) << 8)).Should().Be(acknowledgements);
        speakerTransitions.Should().Be(acknowledgements);
        bus.Speaker.Should().BeTrue();
        card.InterruptRequested.Should().BeTrue();
        card.Peek(13).Should().Be(0xC0);
        maximumLatency.Should().BeLessThanOrEqualTo((ulong)MaximumIrqLatency);
        maximumCadenceError.Should().BeLessThanOrEqualTo(MaximumCadenceError);
        leftTransitions.Should().Be(Cycles / (LeftTonePeriod * 8));
        rightTransitions.Should().Be(Cycles / (RightTonePeriod * 8));
        sink.Frames.Should().Be(14_400_000);
        sink.Writes.Should().Be(56_250);
        sink.LastBlockLength.Should().Be(512);
        sink.ValidBlocks.Should().BeTrue();
        bool stereoDifference = false;
        for (int index = 0; index < sink.Samples.Length; index += 2)
        {
            float left = sink.Samples[index];
            float right = sink.Samples[index + 1];
            float.IsFinite(left).Should().BeTrue();
            float.IsFinite(right).Should().BeTrue();
            stereoDifference |= left != right;
        }

        stereoDifference.Should().BeTrue();
        context.WriteLine(
            $"Emulation elapsed: {elapsed.Elapsed.TotalSeconds:F3}s; CPU/bus clocks: {bus.CycleCount}; stereo frames: {sink.Frames}; blocks: {sink.Writes}.");

        context.WriteLine(
            $"T1 latch: {TimerLatch}; expiries: {expiries}; acknowledgements/handlers/speaker transitions: {acknowledgements}; final IRQ pending: true.");

        context.WriteLine(
            $"IRQ latency: {minimumLatency}..{maximumLatency} clocks; maximum acknowledgement cadence error: {maximumCadenceError} clocks; timer drift: 0 clocks.");

        context.WriteLine($"Left/right PSG transitions: {leftTransitions}/{rightTransitions}.");
        context.WriteLine("Synthetic timer/speaker/PSG clock accounting only; NOT a PT3 audible playback gate.");
    }

    private static void Load(Apple2Bus bus, ushort address, ReadOnlySpan<byte> code)
    {
        for (int index = 0; index < code.Length; index++)
        {
            bus.SetRam(auxiliary: false, (ushort)(address + index), code[index]);
        }
    }

    private static void InitializeAy(Apple2Bus bus, int offset)
    {
        bus.Write((ushort)(0xC402 + offset), 255);
        bus.Write((ushort)(0xC400 + offset), 0);
        bus.Write((ushort)(0xC403 + offset), 255);
        bus.Write((ushort)(0xC400 + offset), 4);
    }

    private static void WriteAy(Apple2Bus bus, int offset, byte register, byte value)
    {
        bus.Write((ushort)(0xC401 + offset), register);
        bus.Write((ushort)(0xC400 + offset), 7);
        bus.Write((ushort)(0xC400 + offset), 4);
        bus.Write((ushort)(0xC401 + offset), value);
        bus.Write((ushort)(0xC400 + offset), 6);
        bus.Write((ushort)(0xC400 + offset), 4);
    }
}
