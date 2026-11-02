// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using ConsoleAppFramework;
using Retrocore.Machines.Apple2;

namespace AppleSharp;

/// <summary>
///  Command-line overrides. An absent override preserves saved configuration.
/// </summary>
/// <param name="RomDirectory">An optional caller-supplied ROM directory.</param>
/// <param name="Model">An optional machine model.</param>
/// <param name="DiskPath">An optional raw ProDOS-order disk image.</param>
/// <param name="Writable">An optional write-permission override.</param>
/// <param name="SettingsPath">The per-user configuration file.</param>
/// <param name="SmokeTest">Whether to run bounded native-window acceptance.</param>
/// <param name="Help">Whether to show usage.</param>
internal sealed record AppOptions(
    string? RomDirectory,
    Apple2Model? Model,
    string? DiskPath,
    bool? Writable,
    string SettingsPath,
    bool SmokeTest,
    bool Help)
{
    private static readonly object s_parseGate = new();

    /// <summary>
    ///  Gets or initializes native drive-one media; unlike --disk .po, this always uses Disk II.
    /// </summary>
    internal string? Floppy1Path { get; init; }

    /// <summary>
    ///  Gets or initializes native drive-two media.
    /// </summary>
    internal string? Floppy2Path { get; init; }

    /// <summary>
    ///  Gets or initializes the external P5 boot-ROM path.
    /// </summary>
    internal string? DiskBootRom { get; init; }

    /// <summary>
    ///  Gets or initializes the external P6 sequencer-ROM path.
    /// </summary>
    internal string? DiskSequencerRom { get; init; }

    /// <summary>
    ///  Gets or initializes the explicit P6 dump layout.
    /// </summary>
    internal P6PromLayout? SequencerLayout { get; init; }

    /// <summary>
    ///  Gets or initializes an explicit audio permission override.
    /// </summary>
    internal bool? Muted { get; init; }

    /// <summary>
    ///  Gets or initializes generated command-line help.
    /// </summary>
    internal string? HelpText { get; init; }

    /// <summary>
    ///  Gets the default per-user settings filename.
    /// </summary>
    internal static string DefaultSettingsPath =>
        Path.Join(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "AppleSharp", "settings.json");

    /// <summary>
    ///  Parses explicit overrides, rejecting unknown switches and missing values.
    /// </summary>
    /// <param name="args">The command-line arguments.</param>
    /// <returns>The validated options.</returns>
    internal static AppOptions Parse(string[] args)
    {
        // Framework logging and Environment.ExitCode are process-wide; isolate parser invocations in tests.
        lock (s_parseGate)
        {
            var log = ConsoleApp.Log;
            var logError = ConsoleApp.LogError;
            int exitCode = Environment.ExitCode;
            string? help = null;
            string? error = null;
            try
            {
                Environment.ExitCode = 0;
                ConsoleApp.Log = message => help = help is null ? message : help + Environment.NewLine + message;
                ConsoleApp.LogError = message => error = error is null ? message : error + Environment.NewLine + message;
                CliOptions binding = new(args);
                ConsoleApp.ConsoleAppBuilder app = ConsoleApp.Create();
                app.Add("", binding.Bind);
                app.Run(args);
                if (error is not null) { throw new ArgumentException(error); }
                return binding.Options is { } options
                    ? options
                    : help is not null
                        ? new(
                            RomDirectory: null,
                            Model: null,
                            DiskPath: null,
                            Writable: null,
                            DefaultSettingsPath,
                            SmokeTest: false,
                            Help: true)
                        {
                            HelpText = help
                        }

                        : throw new ArgumentException("No AppleSharp command was selected.");
            }
            finally
            {
                ConsoleApp.Log = log;
                ConsoleApp.LogError = logError;
                Environment.ExitCode = exitCode;
            }
        }
    }
}
