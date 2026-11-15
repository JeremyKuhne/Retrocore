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
    // Cycles run before each timing, past the boot's own work, the same for every path.
    private const ulong SettleCycles = 500_000;

    /// <summary>
    ///  Checks that running without tracking ends where stepping does, then times each path over the same cycles
    ///  from the same state, and writes it all to the console.
    /// </summary>
    /// <param name="configuration">The machine's launch configuration.</param>
    /// <param name="seconds">
    ///  The work each timing runs: twenty times this many seconds of the machine's clock, about this long at 20x.
    /// </param>
    /// <returns>0, or 1 when running without tracking does not end where stepping does.</returns>
    internal static int Run(JsonObject configuration, double seconds)
    {
        Console.Out.WriteLine($"machine: {configuration["machine"]}");
        string? difference = Difference(configuration);
        Console.Out.WriteLine($"RunCycles ends where stepping does: {difference ?? "yes"}");
        if (difference is not null) { return 1; }

        // Each timing starts from a machine of its own, settled the same way, and runs the same cycles.
        IDebugTarget probe = OffMachine.Build(configuration);
        int clock = probe.ClockHertz;
        (probe as IDisposable)?.Dispose();
        // A whole number of the raw paths' 256-cycle batches, at least one, so all three run the same cycles.
        ulong work = Math.Max(1, (ulong)(clock * seconds * 20 / 256)) * 256;
        Console.Out.WriteLine($"clock {clock} Hz; each timing runs {work:N0} cycles after {SettleCycles:N0}");

        Report("debug target StepCycle", Time(configuration, work, target =>
        {
            for (int count = 0; count < 256; count++)
            {
                target.StepCycle();
            }
        }), clock);

        Report("debug target RunCycles", Time(configuration, work, target => target.RunCycles(256)), clock);

        // The host's run thread stops at the settled cycle and again at the end of the work, so its timing covers
        // the same cycles as the others, from the same state.
        using MachineHost host = new(configuration) { Speed = 0, SoundOn = false };
        host.HoldAt(SettleCycles);
        host.Start();
        host.WaitHeld();
        ulong from = host.CycleCount;
        long started = Stopwatch.GetTimestamp();
        host.HoldAt(from + work);
        host.WaitHeld();
        Report("host at max speed", (host.CycleCount - from) / Stopwatch.GetElapsedTime(started).TotalSeconds, clock);
        return 0;
    }

    // Builds the machine, settles it, and times one path over the given cycles: cycles a second.
    private static double Time(JsonObject configuration, ulong work, Action<IDebugTarget> run)
    {
        IDebugTarget target = OffMachine.Build(configuration);
        try
        {
            // To the settled cycle exactly, as the host's hold stops at it.
            while (target.CycleCount < SettleCycles)
            {
                target.RunCycles((int)Math.Min(256, SettleCycles - target.CycleCount));
            }

            ulong from = target.CycleCount;
            long started = Stopwatch.GetTimestamp();
            while (target.CycleCount < from + work) { run(target); }
            return (target.CycleCount - from) / Stopwatch.GetElapsedTime(started).TotalSeconds;
        }
        finally
        {
            (target as IDisposable)?.Dispose();
        }
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