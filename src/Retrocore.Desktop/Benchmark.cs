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

        Console.Out.WriteLine($"RunCycles ends where stepping does: {Difference(configuration) ?? "yes"}");

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

    // Runs three of the machine the same cycles, two stepped and one without tracking, and compares where they end:
    // the cycle count, program counter, memory and picture. An address that changes while it is read, or that the
    // two stepped ones disagree on, such as the Apple III's clock, which reads the host's time as it is read, is left
    // out. Returns the first difference, or null.
    private static string? Difference(JsonObject configuration)
    {
        const int Cycles = 300_000;
        IDebugTarget stepped = OffMachine.Build(configuration);
        IDebugTarget again = OffMachine.Build(configuration);
        IDebugTarget run = OffMachine.Build(configuration);
        try
        {
            for (int count = 0; count < Cycles; count++)
            {
                stepped.StepCycle();
                again.StepCycle();
            }

            for (int count = 0; count < Cycles; count += 1000) { run.RunCycles(1000); }
            if (run.CycleCount != stepped.CycleCount)
            {
                return $"NO, cycles {run.CycleCount} against {stepped.CycleCount}";
            }

            if (run.ProgramCounter != stepped.ProgramCounter)
            {
                return $"NO, PC ${run.ProgramCounter:X4} against ${stepped.ProgramCounter:X4}";
            }

            for (int address = 0; address <= 0xFFFF; address++)
            {
                byte expected = stepped.Peek((ushort)address);
                byte got = run.Peek((ushort)address);
                if (stepped.Peek((ushort)address) != expected || again.Peek((ushort)address) != expected) { continue; }
                if (got != expected) { return $"NO, ${address:X4} holds ${got:X2} against ${expected:X2}"; }
            }

            return run.RenderVideo().SequenceEqual(stepped.RenderVideo()) ? null : "NO, the picture differs";
        }
        finally
        {
            (stepped as IDisposable)?.Dispose();
            (again as IDisposable)?.Dispose();
            (run as IDisposable)?.Dispose();
        }
    }

    private static void Report(string name, double hertz, int clock) =>
        Console.Out.WriteLine($"{name}: {hertz / 1e6:0.00} MHz, {hertz / clock:0.0}x");
}