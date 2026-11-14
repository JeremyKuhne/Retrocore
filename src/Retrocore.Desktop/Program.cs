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
        for (int index = 0; index < args.Length; index++)
        {
            string? value = index + 1 < args.Length ? args[index + 1] : null;
            switch (args[index])
            {
                case "--machine" when value is not null && JsonNode.Parse(value) is JsonObject machine:
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
                default:
                    Console.Error.WriteLine($"Unknown or incomplete option {args[index]}. Usage: retrocore-desktop [--machine json] [--smoke-seconds n] [--composition lowLatency|default]");
                    return 1;
            }
        }

        using MachineHost host = new(configuration);
        AppBuilder builder = AppBuilder.Configure(() => new DesktopApp(host, smokeSeconds)).UsePlatformDetect();

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
}