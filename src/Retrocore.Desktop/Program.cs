// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Avalonia;
using System.Globalization;
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
    /// <returns>The application exit code, or 1 for bad arguments or a failed tour check.</returns>
    [STAThread]
    internal static int Main(string[] args)
    {
        JsonObject configuration = MachineCatalog.Configuration(MachineCatalog.Machines[0]);
        bool named = false;
        double? smokeSeconds = null;
        string? tour = null;
        string? tourDisk = null;
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
                    named = true;
                    index++;
                    break;
                case "--smoke-seconds" when value is not null && double.TryParse(value, NumberStyles.Float, CultureInfo.InvariantCulture, out double seconds) && double.IsFinite(seconds) && seconds > 0:
                    smokeSeconds = seconds;
                    index++;
                    break;
                case "--tour" when value is not null:
                    tour = value;
                    index++;
                    break;
                case "--tour-disk" when value is not null:
                    tourDisk = Path.GetFullPath(value);
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
                case "--benchmark" when value is not null && double.TryParse(value, NumberStyles.Float, CultureInfo.InvariantCulture, out double length) && double.IsFinite(length) && length is > 0 and <= 3600:
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
                    Console.Error.WriteLine($"Unknown or incomplete option {args[index]}. Usage: retrocore-desktop [--machine json] [--smoke-seconds n] [--composition lowLatency|default] [--theme system|light|dark] [--zoom n] [--speed 0|1|2|4|8] [--fast-drives on|off] [--benchmark n] [--tour folder [--tour-disk image]]");
                    return 1;
            }
        }

        if (benchmarkSeconds is { } benchmark)
        {
            return Benchmark.Run(configuration, benchmark);
        }

        // A smoke run neither reads nor writes the user's settings, so it measures the same every time.
        bool trial = smokeSeconds is not null || tour is not null;
        DesktopSettings settings = DesktopSettings.Load(trial ? null : DesktopSettings.DefaultPath);
        if (theme is not null) { settings.ThemeName = theme; }
        if (fastDrives is { } fast) { settings.FastDrives = fast; }
        if (zoom is { } steps)
        {
            settings.Zoom = Math.Clamp(steps, DesktopSettings.MinimumZoom, DesktopSettings.MaximumZoom);
        }

        // The machine last shown, with its cards and media, unless the command line names one.
        JsonObject? kept = named ? null : settings.Machine;
        using MachineSession session = new(
            kept ?? configuration,
            kept is null ? null : settings.MachineState,
            settings,
            keep: !trial);

        if (speed is { } times) { session.Host.Speed = times; }
        AppBuilder builder = AppBuilder.Configure(() => new DesktopApp(session, settings, smokeSeconds, tour is null ? null : (tour, tourDisk))).UsePlatformDetect();

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

        return builder.StartWithClassicDesktopLifetime(args: []);
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