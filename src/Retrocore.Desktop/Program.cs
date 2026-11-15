// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Avalonia;
using System.Text.Json.Nodes;

namespace Retrocore.Desktop;

/// <summary>
///  Starts Retrocore Desktop: <c>retrocore-desktop [--machine json] [--smoke-seconds n]</c>.
/// </summary>
internal static class Program
{
    /// <summary>
    ///  Runs the app.
    /// </summary>
    /// <param name="args">
    ///  <c>--machine</c>, a launch configuration as JSON (the Apple IIe by default), and <c>--smoke-seconds</c>, to run
    ///  for that long, report and exit.
    /// </param>
    /// <returns>0, or 1 for bad arguments.</returns>
    [STAThread]
    internal static int Main(string[] args)
    {
        JsonObject configuration = new() { ["machine"] = "apple2" };
        double? smokeSeconds = null;
        string composition = "lowLatency";
        string? theme = null;
        int? zoom = null;
        double? benchmarkSeconds = null;
        double? speed = null;
        bool? fastDrives = null;
        for (int index = 0; index < args.Length; index++)
        {
            string? value = index + 1 < args.Length ? args[index + 1] : null;
            switch (args[index])
            {
                case "--machine" when value is not null && ParseObject(value) is JsonObject machine:
                    configuration = machine;
                    index++;
                    break;
                case "--smoke-seconds" when value is not null && double.TryParse(value, out double seconds) && seconds > 0:
                    smokeSeconds = seconds;
                    index++;
                    break;
                case "--composition" when value is "lowLatency" or "default":
                    composition = value;
                    index++;
                    break;
                case "--theme" when value is "system" or "light" or "dark":
                    theme = value;
                    index++;
                    break;
                case "--benchmark" when value is not null && double.TryParse(value, out double length) && length > 0:
                    benchmarkSeconds = length;
                    index++;
                    break;
                case "--speed" when value is "0" or "1" or "2" or "4" or "8":
                    speed = double.Parse(value, System.Globalization.CultureInfo.InvariantCulture);
                    index++;
                    break;
                case "--fast-drives" when value is "on" or "off":
                    fastDrives = value == "on";
                    index++;
                    break;
                case "--zoom" when value is not null && int.TryParse(value, out int level):
                    zoom = level;
                    index++;
                    break;
                default:
                    Console.Error.WriteLine($"Unknown or incomplete option {args[index]}. Usage: retrocore-desktop [--machine json] [--smoke-seconds n] [--composition lowLatency|default] [--theme system|light|dark] [--zoom n] [--speed 0|1|2|4|8] [--fast-drives on|off] [--benchmark n]");
                    return 1;
            }
        }

        if (benchmarkSeconds is { } benchmark)
        {
            Benchmark.Run(configuration, benchmark);
            return 0;
        }

        // A smoke run neither reads nor writes the user's settings, so it measures the same every time.
        DesktopSettings settings = DesktopSettings.Load(smokeSeconds is null ? DesktopSettings.DefaultPath : null);
        if (theme is not null) { settings.ThemeName = theme; }
        if (fastDrives is { } fast) { settings.FastDrives = fast; }
        if (zoom is { } steps)
        {
            settings.Zoom = Math.Clamp(steps, DesktopSettings.MinimumZoom, DesktopSettings.MaximumZoom);
        }

        using MachineHost host = new(configuration);
        if (speed is { } times) { host.Speed = times; }
        AppBuilder builder = AppBuilder.Configure(() => new DesktopApp(host, settings, smokeSeconds)).UsePlatformDetect();

        // On Windows, a low-latency DXGI swap chain paces frames to the display's vertical blank; Avalonia's
        // default composition keeps to its own timer.
        if (composition == "lowLatency")
        {
            builder = builder.With(new Win32PlatformOptions
            {
                RenderingMode = [Win32RenderingMode.AngleEgl],
                CompositionMode = [Win32CompositionMode.LowLatencyDxgiSwapChain, Win32CompositionMode.WinUIComposition],
            });
        }

        builder.StartWithClassicDesktopLifetime(args: []);

        return 0;
    }

    // A JSON object, or null for anything else, malformed JSON among it.
    private static JsonObject? ParseObject(string json)
    {
        try
        {
            return JsonNode.Parse(json) as JsonObject;
        }
        catch (System.Text.Json.JsonException)
        {
            return null;
        }
    }
}