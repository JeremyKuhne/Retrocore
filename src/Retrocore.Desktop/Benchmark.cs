// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug;
using System.Diagnostics;
using System.Text.Json.Nodes;

namespace Retrocore.Desktop;

/// <summary>
///  Measures how fast a machine runs without the window: stepped as a debugger steps it, run without the
///  debugger's tracking, then the host's run thread at its fastest, so the differences show what each costs.
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
        Cycles(target, 0.5, () => target.RunCycles(256));
        Report("debug target StepCycle", Cycles(target, seconds, () =>
        {
            for (int count = 0; count < 256; count++)
            {
                target.StepCycle();
            }
        }), clock);

        Report("debug target RunCycles", Cycles(target, seconds, () => target.RunCycles(256)), clock);
        (target as IDisposable)?.Dispose();

        Console.Out.WriteLine($"RunCycles ends where stepping does: {(Matches(configuration) ? "yes" : "NO")}");

        using MachineHost host = new(configuration) { Speed = 0, SoundOn = false };
        host.Start();
        Thread.Sleep(1000);
        ulong start = host.CycleCount;
        long started = Stopwatch.GetTimestamp();
        Thread.Sleep(TimeSpan.FromSeconds(seconds));
        double hertz = (host.CycleCount - start) / Stopwatch.GetElapsedTime(started).TotalSeconds;
        Report("host at max speed", hertz, clock);
    }

    private static double Cycles(IDebugTarget target, double seconds, Action run)
    {
        ulong start = target.CycleCount;
        long started = Stopwatch.GetTimestamp();
        TimeSpan length = TimeSpan.FromSeconds(seconds);
        while (Stopwatch.GetElapsedTime(started) < length)
        {
            for (int count = 0; count < 100; count++) { run(); }
        }

        return (target.CycleCount - start) / Stopwatch.GetElapsedTime(started).TotalSeconds;
    }

    // Runs two of the machine the same cycles, one stepped and one without tracking, and compares where they end:
    // the cycle count, program counter, memory and picture.
    private static bool Matches(JsonObject configuration)
    {
        const int Cycles = 300_000;
        IDebugTarget stepped = OffMachine.Build(configuration);
        IDebugTarget run = OffMachine.Build(configuration);
        try
        {
            for (int count = 0; count < Cycles; count++) { stepped.StepCycle(); }
            for (int count = 0; count < Cycles; count += 1000) { run.RunCycles(1000); }
            if (run.CycleCount != stepped.CycleCount || run.ProgramCounter != stepped.ProgramCounter) { return false; }
            for (int address = 0; address <= 0xFFFF; address++)
            {
                if (run.Peek((ushort)address) != stepped.Peek((ushort)address)) { return false; }
            }

            return run.RenderVideo().SequenceEqual(stepped.RenderVideo());
        }
        finally
        {
            (stepped as IDisposable)?.Dispose();
            (run as IDisposable)?.Dispose();
        }
    }

    private static void Report(string name, double hertz, int clock) =>
        Console.Out.WriteLine($"{name}: {hertz / 1e6:0.00} MHz, {hertz / clock:0.0}x");
}