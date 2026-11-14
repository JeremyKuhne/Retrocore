// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Threading;
using System.Diagnostics;

namespace Retrocore.Desktop;

/// <summary>
///  Runs the window for a while, types a line at the machine, and reports what the spike measures: frames, frame
///  times, emulated speed, sound and whether the typing reached the screen.
/// </summary>
internal static class SmokeRun
{
    // The first second is left out: the window opening and the JIT (for a non-AOT run) settle in it.
    private static readonly TimeSpan s_settle = TimeSpan.FromSeconds(1);

    /// <summary>
    ///  Starts the run.
    /// </summary>
    /// <param name="window">The window.</param>
    /// <param name="host">The machine.</param>
    /// <param name="seconds">How long to measure.</param>
    /// <param name="desktop">The application, to shut down at the end.</param>
    internal static void Start(MainWindow window, MachineHost host, double seconds, IClassicDesktopStyleApplicationLifetime desktop)
    {
        long started = Stopwatch.GetTimestamp();
        bool settled = false;
        bool typed = false;
        DispatcherTimer timer = new() { Interval = TimeSpan.FromMilliseconds(100) };
        timer.Tick += (_, _) =>
        {
            TimeSpan elapsed = Stopwatch.GetElapsedTime(started);
            if (!settled && elapsed >= s_settle)
            {
                settled = true;
                window.Screen.Stats.Restart();
            }

            // Halfway, the line goes in through the same path the keyboard's keys do.
            if (!typed && elapsed.TotalSeconds >= seconds / 2)
            {
                typed = true;
                foreach (char character in "PRINT 6*7") { host.Key(character); }
                host.Key(13);
            }

            if (elapsed.TotalSeconds < seconds + s_settle.TotalSeconds) { return; }
            timer.Stop();
            Report(window, host, seconds);
            desktop.Shutdown();
        };

        timer.Start();
    }

    private static void Report(MainWindow window, MachineHost host, double seconds)
    {
        FrameStats stats = window.Screen.Stats;
        bool reached = host.ScreenText().Contains("42", StringComparison.Ordinal);
        double speed = host.MeasuredHertz / host.ClockHertz;
        Console.Out.WriteLine($"machine: {host.Name}");
        Console.Out.WriteLine($"seconds: {seconds:0.0}");
        if (stats.FirstFrame is { } first)
        {
            Console.Out.WriteLine($"first frame after start: {(first - Process.GetCurrentProcess().StartTime).TotalMilliseconds:0} ms");
        }

        Console.Out.WriteLine($"display frames: {stats.Frames} ({stats.Frames / seconds:0.0} a second), pictures drawn: {stats.Drawn}");
        Console.Out.WriteLine($"frame time ms: median {stats.Percentile(50):0.00}, p99 {stats.Percentile(99):0.00}, max {stats.Percentile(100):0.00}");
        Console.Out.WriteLine($"emulated speed: {speed:0.000}x of {host.ClockHertz} Hz");
        Console.Out.WriteLine($"sound: {(host.AudioOpen ? "open" : "not open")}, underruns: {host.AudioUnderruns}");
        Console.Out.WriteLine($"typing reached the screen: {(reached ? "yes" : "no")}");
        Console.Out.Flush();
    }
}