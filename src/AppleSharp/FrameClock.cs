// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Apple2;

namespace AppleSharp;

/// <summary>
///  Converts host time to exact CPU budgets, retaining fractional cycles and catch-up backlog.
///  Paused time is deliberately excluded; running time is never silently dropped.
/// </summary>
internal sealed class FrameClock
{
    /// <summary>
    ///  Nominal CPU clocks per second used by the existing NTSC machine plan.
    /// </summary>
    internal const ulong CyclesPerSecond = 1_020_500;
    private readonly ulong _frequency;
    private long _last;
    private ulong _fraction;
    private ulong _pending;

    /// <summary>
    ///  Starts a frame clock.
    /// </summary>
    /// <param name="frequency">The host timer frequency.</param>
    /// <param name="timestamp">The initial timer value.</param>
    internal FrameClock(long frequency, long timestamp)
    {
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(frequency);
        _frequency = (ulong)frequency;
        _last = timestamp;
    }

    /// <summary>
    ///  Consumes at most four video frames of CPU work, retaining any larger backlog.
    /// </summary>
    /// <param name="timestamp">The current host timer value.</param>
    /// <param name="running">Whether the emulated machine is running.</param>
    /// <returns>The bounded CPU cycle budget.</returns>
    internal ulong Take(long timestamp, bool running)
    {
        if (timestamp < _last) { throw new ArgumentOutOfRangeException(nameof(timestamp)); }
        ulong elapsed = (ulong)(timestamp - _last);
        _last = timestamp;
        if (!running)
        {
            _pending = _fraction = 0;
            return 0;
        }

        UInt128 scaled = (UInt128)elapsed * CyclesPerSecond + _fraction;
        _pending += (ulong)(scaled / _frequency);
        _fraction = (ulong)(scaled % _frequency);
        ulong budget = Math.Min(_pending, (ulong)Apple2Video.CyclesPerFrame * 4);
        _pending -= budget;
        return budget;
    }
}
