// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Apple2;

/// <summary>
///  Integer phase accumulator for exact NTSC CPU-to-PCM clock conversion.
/// </summary>
internal sealed class AudioSampleClock
{
    /// <summary>
    ///  Nominal IIe CPU clocks per second.
    /// </summary>
    internal const int ClockRate = 1_020_500;

    private readonly int _sampleRate;
    private int _phase;

    /// <summary>
    ///  Creates a clock with at most one PCM frame per CPU clock.
    /// </summary>
    /// <param name="sampleRate">PCM frames per second.</param>
    internal AudioSampleClock(int sampleRate)
    {
        ArgumentOutOfRangeException.ThrowIfLessThan(sampleRate, 1);
        ArgumentOutOfRangeException.ThrowIfGreaterThan(sampleRate, ClockRate);
        _sampleRate = sampleRate;
    }

    /// <summary>
    ///  Gets the elapsed fraction of a PCM frame in sample-rate clock units.
    /// </summary>
    internal int Phase => _phase;

    /// <summary>
    ///  Advances one CPU cycle and reports a completed PCM frame.
    /// </summary>
    /// <returns>Whether a frame boundary was crossed.</returns>
    internal bool Tick()
    {
        _phase += _sampleRate;
        if (_phase < ClockRate)
        {
            return false;
        }

        _phase -= ClockRate;
        return true;
    }

    /// <summary>
    ///  Advances discarded cycles while retaining their exact fractional phase.
    /// </summary>
    /// <param name="cycles">The number of CPU cycles.</param>
    internal void Advance(int cycles)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(cycles);
        _phase = (int)((_phase + ((long)cycles * _sampleRate)) % ClockRate);
    }

    /// <summary>
    ///  Restarts the fractional clock.
    /// </summary>
    internal void Reset() => _phase = 0;
}
