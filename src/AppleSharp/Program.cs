// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using SDL3;
using System.Text.Json;

namespace AppleSharp;

/// <summary>
///  Standalone, Native AOT-compatible AppleSharp entry point.
/// </summary>
internal static class Program
{
    /// <summary>
    ///  Starts the independently usable SDL3 emulator.
    /// </summary>
    /// <param name="args">The explicit configuration overrides.</param>
    /// <returns>Zero on clean shutdown, nonzero on startup or acceptance failure.</returns>
    [STAThread]
    private static int Main(string[] args)
    {
        try
        {
            AppOptions options = AppOptions.Parse(args);
            if (options.Help)
            {
                string help = options.HelpText ?? throw new InvalidOperationException("The command parser did not produce help.");
                Console.WriteLine(help);
                return !SDL.ShowSimpleMessageBox(SDL.MessageBoxFlags.Information, "AppleSharp", help, IntPtr.Zero)
                    ? throw new InvalidOperationException(SDL.GetError())
                    : 0;
            }

            using Application app = new(options, AppSettings.Load(options.SettingsPath));
            app.Run();
            return 0;
        }
        catch (Exception exception) when (exception is IOException
            or UnauthorizedAccessException
            or ArgumentException
            or InvalidOperationException
            or NotSupportedException
            or JsonException)
        {
            Console.Error.WriteLine(exception);
            if (!args.Contains("--smoke-test", StringComparer.Ordinal))
            {
                if (!SDL.ShowSimpleMessageBox(SDL.MessageBoxFlags.Error, "AppleSharp", exception.Message, IntPtr.Zero))
                {
                    Console.Error.WriteLine("SDL error dialog failed: " + SDL.GetError());
                }
            }

            return 1;
        }
        catch (DllNotFoundException exception)
        {
            Console.Error.WriteLine("AppleSharp requires the SDL3 native library shipped with its publish output: " + exception.Message);
            return 1;
        }
    }
}
