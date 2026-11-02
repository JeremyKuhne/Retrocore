// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Apple2;

namespace Retrocore.Tests;

/// <summary>
///  Directed PCM clock, integration, stereo and allocation checks; no playback fixture is used.
/// </summary>
[TestClass]
public class Apple2AudioTests
{
    /// <summary>
    ///  Verifies every fractional boundary over five minutes using the production sample clock.
    /// </summary>
    /// <param name="rate">The output rate.</param>
    [TestMethod]
    [DataRow(48000)]
    [DataRow(44100)]
    [Timeout(30000)]
    public void FiveMinutesHaveExactFractionalSampleAccounting(int rate)
    {
        AudioSampleClock clock = new(rate);
        int cycles = AudioSampleClock.ClockRate * 300;
        long frames = 0;
        for (int cycle = 0; cycle < cycles; cycle++)
        {
            if (clock.Tick())
            {
                frames++;
            }
        }

        frames.Should().Be(rate * 300L);
        clock.Phase.Should().Be(0);
        for (int cycle = 0; cycle < 113; cycle++)
        {
            if (clock.Tick())
            {
                frames++;
            }

            frames.Should().Be((long)(cycles + cycle + 1) * rate / AudioSampleClock.ClockRate);
            clock.Phase.Should().Be((int)((long)(cycles + cycle + 1) * rate % AudioSampleClock.ClockRate));
        }
    }

    /// <summary>
    ///  Verifies real mixer delivery, complete fixed blocks and flush's unchanged phase.
    /// </summary>
    /// <param name="rate">The output rate.</param>
    [TestMethod]
    [DataRow(48000)]
    [DataRow(44100)]
    [DataRow(1020500)]
    public void MixerProducesExactCountsAndFlushesPartialBlocks(int rate)
    {
        RecordingAudioTests sink = new();
        Apple2Audio audio = new(rate) { Sink = sink };
        const int Cycles = 131071;
        for (int cycle = 0; cycle < Cycles; cycle++)
        {
            audio.Tick(speaker: false, left: 0, right: 0);
        }

        long frames = (long)Cycles * rate / AudioSampleClock.ClockRate;
        sink.Frames.Should().Be(frames / 256 * 256);
        audio.Flush();
        sink.Frames.Should().Be(frames);
        sink.LastBlockLength.Should().Be((int)(frames % 256 * 2));
        sink.ValidBlocks.Should().BeTrue();
        int writes = sink.Writes;
        audio.Flush();
        sink.Writes.Should().Be(writes);
        for (int cycle = 0; cycle < 197; cycle++)
        {
            audio.Tick(speaker: false, left: 0, right: 0);
            audio.Flush();
        }

        sink.Frames.Should().Be((long)(Cycles + 197) * rate / AudioSampleClock.ClockRate);
    }

    /// <summary>
    ///  Verifies an edge crossing a fractional sample boundary is integrated, not point sampled.
    /// </summary>
    [TestMethod]
    public void FractionalIntegrationAndSpeakerTransitionsAreStereo()
    {
        RecordingAudioTests sink = new();
        Apple2Audio audio = new(48000) { Sink = sink };
        for (int cycle = 0; cycle < 21; cycle++)
        {
            audio.Tick(speaker: false, left: 0, right: 0);
        }

        audio.Tick(speaker: true, left: 0, right: 0);
        audio.Flush();
        sink.Frames.Should().Be(1);
        float expected = (float)(((-0.5 * 21 * 48000) + (0.5 * 12500)) / 1020500);
        float highPass = MathF.Exp(-2 * MathF.PI * 20 / 48000);
        sink.Samples[0].Should().BeApproximately(expected * highPass, 0.000001f);
        sink.Samples[1].Should().Be(sink.Samples[0]);
        for (int cycle = 0; cycle < 22; cycle++)
        {
            audio.Tick(speaker: true, left: 0, right: 0);
        }

        audio.Flush();
        sink.Samples[2].Should().BeGreaterThan(0.49f);
        sink.Samples[3].Should().Be(sink.Samples[2]);
    }

    /// <summary>
    ///  Verifies channel isolation, normalized PCM, and high-pass decay for a constant level.
    /// </summary>
    [TestMethod]
    public void StereoInputRemainsSeparatedAndDcDecays()
    {
        RecordingAudioTests sink = new();
        Apple2Audio audio = new(48000) { Sink = sink };
        for (int cycle = 0; cycle < 150000; cycle++)
        {
            audio.Tick(speaker: false, left: 1, right: 0);
        }

        audio.Flush();
        sink.Samples[0].Should().Be(0);
        sink.Samples[1].Should().BeLessThan(-0.49f);
        sink.Samples[^1].Should().BeApproximately(0, 0.000001f);
        foreach (float sample in sink.Samples)
        {
            sample.Should().BeInRange(-1, 1);
        }
    }

    /// <summary>
    ///  Verifies absent sinks never queue audio; changes discard old blocks and reset is explicit.
    /// </summary>
    [TestMethod]
    public void SinkAbsenceAndReplacementNeverRetainUndrainedAudio()
    {
        Apple2Audio audio = new();
        for (int cycle = 0; cycle < 100000; cycle++)
        {
            audio.Tick(speaker: true, left: 1, right: 1);
        }

        RecordingAudioTests first = new();
        audio.Sink = first;
        audio.Flush();
        first.Frames.Should().Be(0);
        for (int cycle = 0; cycle < 100; cycle++)
        {
            audio.Tick(speaker: false, left: 0, right: 0);
        }

        RecordingAudioTests second = new();
        audio.Sink = second;
        audio.Flush();
        first.Frames.Should().Be(0);
        second.Frames.Should().Be(0);
        audio.Reset();
        audio.SampleRate.Should().Be(48000);
        for (int cycle = 0; cycle < 1020500; cycle++)
        {
            audio.Tick(speaker: false, left: 0, right: 0);
        }

        audio.Flush();
        second.Frames.Should().Be(48000);
        audio.Sink = null;
        audio.Reset();
        audio.Flush();
        second.Frames.Should().Be(48000);
    }

    /// <summary>
    ///  Verifies rate bounds protect the accumulator and reject invalid clocks.
    /// </summary>
    /// <param name="rate">The invalid rate.</param>
    [TestMethod]
    [DataRow(0)]
    [DataRow(-1)]
    [DataRow(1020501)]
    public void InvalidSampleRatesAreRejected(int rate)
    {
        Action create = () => _ = new Apple2Audio(rate);
        create.Should().Throw<ArgumentOutOfRangeException>();
    }

    /// <summary>
    ///  Verifies the complete warm card/output/mixer/sink path allocates no managed memory.
    /// </summary>
    [TestMethod]
    public void WarmDeviceLoopsAllocateNothingPerTick()
    {
        Mockingboard board = new();
        RecordingAudioTests sink = new();
        Apple2Audio audio = new() { Sink = sink };
        board.Write(2, 255);
        board.Write(0, 4);
        board.Write(0x82, 255);
        board.Write(0x80, 4);
        for (int cycle = 0; cycle < 50000; cycle++)
        {
            board.Tick();
            audio.Tick((cycle & 16) != 0, board.Left, board.Right);
        }

        long before = GC.GetAllocatedBytesForCurrentThread();
        for (int cycle = 0; cycle < 250000; cycle++)
        {
            board.Tick();
            audio.Tick((cycle & 16) != 0, board.Left, board.Right);
            if ((cycle & 255) == 0)
            {
                board.Write(4, (byte)cycle);
                board.Write(5, 0);
                _ = board.Peek(13);
                _ = board.Read(4);
            }
        }

        audio.Flush();
        long allocated = GC.GetAllocatedBytesForCurrentThread() - before;
        allocated.Should().Be(0);
        sink.ValidBlocks.Should().BeTrue();
    }
}
