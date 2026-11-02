// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Apple2;

namespace AppleSharp;

/// <summary>
///  Typed root-command binding used by ConsoleAppFramework's generated parser and help.
/// </summary>
internal sealed class CliOptions
{
    private readonly string[] _args;

    /// <summary>
    ///  Retains argument order solely to preserve paired permission-switch precedence.
    /// </summary>
    /// <param name="args">The original arguments.</param>
    internal CliOptions(string[] args) => _args = args;

    /// <summary>
    ///  Gets bound options after successful parsing.
    /// </summary>
    internal AppOptions? Options { get; private set; }

    /// <summary>
    ///  Start the standalone Apple IIe emulator. ROMs are caller-supplied; disk mounts default to read-only.
    /// </summary>
    /// <param name="romDirectory">-r|--rom-folder, External IIe ROM folder containing CD, EF and video chips.</param>
    /// <param name="model">Original or enhanced; omit to use the saved model.</param>
    /// <param name="disk">Slot-seven .po image, or native .woz/.dsk media.</param>
    /// <param name="writable">Explicitly allow persistent writes to mounted images.</param>
    /// <param name="readOnly">Override a saved writable mount with read-only access.</param>
    /// <param name="floppy">Native Disk II drive-one image, including native .po mounting.</param>
    /// <param name="floppy2">Native Disk II drive-two image.</param>
    /// <param name="diskIiRom">Externally supplied 256-byte P5/P5A boot ROM.</param>
    /// <param name="sequencerRom">Externally supplied 256-byte P6 sequencer PROM.</param>
    /// <param name="p6Layout">
    ///  P6 layout: raw, beneath-prodos or boot-socket; omitted values preserve saved configuration.
    /// </param>
    /// <param name="mute">Mute speaker and Mockingboard audio.</param>
    /// <param name="sound">Override saved mute configuration and enable sound.</param>
    /// <param name="settings">Override the per-user settings filename.</param>
    /// <param name="smokeTest">Run bounded native-window acceptance and exit.</param>
    public void Bind(
        string? romDirectory = null,
        string? model = null,
        string? disk = null,
        bool writable = false,
        bool readOnly = false,
        string? floppy = null,
        string? floppy2 = null,
        string? diskIiRom = null,
        string? sequencerRom = null,
        string? p6Layout = null,
        bool mute = false,
        bool sound = false,
        string? settings = null,
        bool smokeTest = false)
    {
        Apple2Model? selected = model switch
        {
            null => null, "original" => Apple2Model.IIe, "enhanced" => Apple2Model.IIeEnhanced,
            _ => throw new ArgumentException("Model must be original or enhanced.")
        };

        P6PromLayout? layout = p6Layout switch
        {
            null => null, "raw" => P6PromLayout.Raw, "beneath-prodos" => P6PromLayout.BeneathProDos,
            "boot-socket" => P6PromLayout.BootSocket,
            _ => throw new ArgumentException("P6 layout must be raw, beneath-prodos or boot-socket.")
        };

        Options = new(
            FullPath(romDirectory),
            selected,
            FullPath(disk),
            Toggle("--writable", writable, "--read-only", readOnly),
            FullPath(settings) ?? AppOptions.DefaultSettingsPath,
            smokeTest,
            Help: false)
        {
            Floppy1Path = FullPath(floppy),
            Floppy2Path = FullPath(floppy2),
            DiskBootRom = FullPath(diskIiRom),
            DiskSequencerRom = FullPath(sequencerRom),
            SequencerLayout = layout,
            Muted = Toggle("--mute", mute, "--sound", sound)
        };
    }

    private static string? FullPath(string? path) => path is null ? null : Path.GetFullPath(path);

    private bool? Toggle(string positive, bool positiveValue, string negative, bool negativeValue)
    {
        int positiveIndex = Array.FindLastIndex(_args, arg => arg == positive || arg.StartsWith(positive + "=", StringComparison.Ordinal));
        int negativeIndex = Array.FindLastIndex(_args, arg => arg == negative || arg.StartsWith(negative + "=", StringComparison.Ordinal));
        return positiveIndex < 0 && negativeIndex < 0 ? null : positiveIndex > negativeIndex ? positiveValue : !negativeValue;
    }
}
