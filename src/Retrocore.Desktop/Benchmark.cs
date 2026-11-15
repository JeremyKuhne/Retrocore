// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug;
using System.Diagnostics;
using System.Text.Json.Nodes;

namespace Retrocore.Desktop;

/// <summary>
///  Measures how fast a machine runs without the window: its cycles alone, then the host's run thread at its
///  fastest, so the difference shows what the host costs.
/// </summary>
internal static class Benchmark
{
    /// <summary>
    ///  Runs the measurements and writes them to the console.
    /// </summary>
    /// <param name="configuration">The machine's launch configuration.</param>
    /// <param name="seconds">How long each measurement runs.</param>
    internal static void Run(JsonObject configuration, double seconds)
    {
        IDebugTarget target = OffMachine.Build(configuration);
        int clock = target.ClockHertz;
        Console.Out.WriteLine($"machine: {configuration["machine"]}, clock {clock} Hz");

        // Settle first, so the boot's own work is not measured.
        Cycles(target, 0.5);
        Report("debug target StepCycle", Cycles(target, seconds), clock);
        (target as IDisposable)?.Dispose();

        using MachineHost host = new(configuration) { Speed = 0, SoundOn = false };
        host.Start();
        Thread.Sleep(1000);
        ulong start = host.CycleCount;
        long started = Stopwatch.GetTimestamp();
        Thread.Sleep(TimeSpan.FromSeconds(seconds));
        double hertz = (host.CycleCount - start) / Stopwatch.GetElapsedTime(started).TotalSeconds;
        Report("host at max speed", hertz, clock);
    }

    private static double Cycles(IDebugTarget target, double seconds)
    {
        ulong start = target.CycleCount;
        long started = Stopwatch.GetTimestamp();
        TimeSpan length = TimeSpan.FromSeconds(seconds);
        while (Stopwatch.GetElapsedTime(started) < length)
        {
            for (int count = 0; count < 10_000; count++) { target.StepCycle(); }
        }

        return (target.CycleCount - start) / Stopwatch.GetElapsedTime(started).TotalSeconds;
    }

    private static void Report(string name, double hertz, int clock) =>
        Console.Out.WriteLine($"{name}: {hertz / 1e6:0.00} MHz, {hertz / clock:0.0}x");
}