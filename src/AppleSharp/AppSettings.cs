// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Apple2;
using System.Text.Json;

namespace AppleSharp;

/// <summary>
///  Persisted first-host configuration, serialized with Native AOT-compatible metadata.
/// </summary>
internal sealed record AppSettings
{
    /// <summary>
    ///  Gets or initializes the external firmware directory.
    /// </summary>
    public string? RomDirectory { get; init; }

    /// <summary>
    ///  Gets or initializes the selected IIe model.
    /// </summary>
    public Apple2Model Model { get; init; } = Apple2Model.IIeEnhanced;

    /// <summary>
    ///  Gets or initializes the optional raw .po image.
    /// </summary>
    public string? DiskPath { get; init; }

    /// <summary>
    ///  Gets or initializes whether mounts explicitly allow persistent writes.
    /// </summary>
    public bool Writable { get; init; }

    /// <summary>
    ///  Gets or initializes fullscreen mode.
    /// </summary>
    public bool Fullscreen { get; init; }

    /// <summary>
    ///  Gets or initializes the integer UI pixel scale; null selects the display default.
    /// </summary>
    public int? UiScale { get; init; }

    /// <summary>
    ///  Gets or initializes native drive-one media.
    /// </summary>
    public string? Floppy1Path { get; init; }

    /// <summary>
    ///  Gets or initializes native drive-two media.
    /// </summary>
    public string? Floppy2Path { get; init; }

    /// <summary>
    ///  Gets or initializes the caller-supplied P5 boot ROM.
    /// </summary>
    public string? DiskBootRom { get; init; }

    /// <summary>
    ///  Gets or initializes the caller-supplied P6 sequencer PROM.
    /// </summary>
    public string? DiskSequencerRom { get; init; }

    /// <summary>
    ///  Gets or initializes the explicitly selected sequencer dump layout.
    /// </summary>
    public P6PromLayout SequencerLayout { get; init; }

    /// <summary>
    ///  Gets or initializes whether sound output is muted.
    /// </summary>
    public bool Muted { get; init; }

    /// <summary>
    ///  Gets or initializes the monitor the video is shown on.
    /// </summary>
    public Apple2Monitor Screen { get; init; }

    /// <summary>
    ///  Reads saved configuration; only a nonexistent file produces first-launch defaults.
    /// </summary>
    /// <param name="path">The configuration file.</param>
    /// <returns>The validated settings.</returns>
    internal static AppSettings Load(string path)
    {
        if (!File.Exists(path)) { return new(); }
        AppSettings settings = JsonSerializer.Deserialize(File.ReadAllText(path), AppSettingsContext.Default.AppSettings)
            ?? throw new InvalidDataException("AppleSharp settings cannot be null.");

        if (!settings.Model.IsIIe())
        {
            throw new InvalidDataException("AppleSharp settings name a model that is not a IIe.");
        }

        if (settings.UiScale is < 1 or > 4)
        {
            throw new InvalidDataException("UI scale must be between 1 and 4.");
        }

        if (!Enum.IsDefined(settings.Screen)) { throw new InvalidDataException("Unknown screen."); }
        return !Enum.IsDefined(settings.SequencerLayout)
            ? throw new InvalidDataException("Unknown P6 PROM layout.")
            : settings.RomDirectory is { Length: 0 } || settings.DiskPath is { Length: 0 }
                ? throw new InvalidDataException("Configured ROM and disk paths cannot be empty.")
                : settings;
    }

    /// <summary>
    ///  Atomically replaces configuration using source-generated serialization.
    /// </summary>
    /// <param name="path">The configuration file.</param>
    internal void Save(string path)
    {
        string fullPath = Path.GetFullPath(path);
        Directory.CreateDirectory(
            Path.GetDirectoryName(
                fullPath) ?? throw new ArgumentException(
                    "Missing settings directory.",
                    nameof(path)));

        string temporary = fullPath + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            File.WriteAllText(temporary, JsonSerializer.Serialize(this, AppSettingsContext.Default.AppSettings));
            File.Move(temporary, fullPath, overwrite: true);
        }
        finally
        {
            if (File.Exists(temporary)) { File.Delete(temporary); }
        }
    }
}
