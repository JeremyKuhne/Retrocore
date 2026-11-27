// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Diagnostics;

namespace Retrocore.Debug;

/// <summary>
///  Keeps a project boot phase at its selected wall-clock speed.
/// </summary>
/// <param name="Began">The wall-clock origin.</param>
/// <param name="Speed">The speed multiplier, or zero to run unthrottled.</param>
/// <param name="Clock">The guest clock in hertz.</param>
/// <param name="Start">The guest-cycle origin.</param>
internal readonly record struct ImageBootPace(long Began, double Speed, int Clock, long Start = 0)
{
    /// <summary>
    ///  Waits if media work is ahead of the selected speed.
    /// </summary>
    /// <param name="cycles">The cycles run so far.</param>
    /// <param name="transport">The adapter that can cancel this launch.</param>
    internal void Wait(long cycles, DapTransport? transport)
    {
        transport?.ThrowIfLaunchCancelled();
        if (Speed == 0) { return; }
        double seconds = (cycles - Start) / (Clock * Speed) - Stopwatch.GetElapsedTime(Began).TotalSeconds;
        if (seconds > 0) { Thread.Sleep(TimeSpan.FromSeconds(seconds)); }
    }
}
