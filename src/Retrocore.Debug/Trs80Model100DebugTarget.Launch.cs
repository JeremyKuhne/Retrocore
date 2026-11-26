// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Trs80Model100;
using System.Globalization;
using System.Text.Json.Nodes;

namespace Retrocore.Debug;

internal sealed partial class Trs80Model100DebugTarget
{
    /// <summary>
    ///  The variable that names the folder of the Model 100's ROM dumps when a launch gives none.
    /// </summary>
    internal const string RomDirectoryVariable = "RETROCORE_TRS80M100_ROMS";

    // The names the ROMs go by: MAME's first, then the Bitchin100 wiki's zips' and the fixtures'.
    private static readonly string[] s_model100Roms = ["m100rom.m12", "m100.bin", "m100rom.bin"];
    private static readonly string[] s_tandy102Roms = ["m102rom.m12", "t102.bin", "t102_rom.bin", "m102rom.bin"];
    private static readonly string[] s_folders = ["trs80m100", "tandy102", "trs80m100-roms"];

    /// <summary>
    ///  Launches a Model 100 or Tandy 102 from a launch request's arguments.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   The ROM is the user's: <c>rom</c> names its file (a path, or a name in the ROM folder), or it is found in
    ///   <c>romDirectory</c> (or <c>RETROCORE_TRS80M100_ROMS</c>) or that folder's <c>trs80m100</c>, <c>tandy102</c>
    ///   or <c>trs80m100-roms</c> folder, by MAME's name (<c>m100rom.m12</c>, <c>m102rom.m12</c>) or the fixtures'
    ///   (<c>m100.bin</c>, <c>t102.bin</c>). <c>model</c> is <c>100</c> (the default) or <c>102</c>, which picks the
    ///   ROM to look for; with no <c>model</c>, a ROM named by <c>rom</c> tells its model by its digest. <c>ramKilobytes</c> is 8, 16, 24 or
    ///   32 (the default), <c>optionRom</c> names an option ROM's file, and <c>time</c> sets the clock (an ISO 8601
    ///   date and time; the host's local time by default).
    ///  </para>
    ///  <para>
    ///   <c>ramImage</c> names a file that keeps the RAM between sessions, as the Model 100's battery does: the fitted
    ///   RAM's bytes, from its first address to $FFFF. When it exists it is loaded before the power comes on, so the ROM
    ///   finds its RAM valid and carries on, the clock taken from <c>time</c> or the host; when it does not, the
    ///   machine cold-starts and the file is written. Either way the RAM is saved to it when the session ends or
    ///   another launch replaces it (see <see cref="SaveRecordings"/>). <c>coldStart</c>, true, starts from empty RAM
    ///   even when the file exists, and replaces it when the session ends.
    ///  </para>
    /// </remarks>
    /// <param name="args">The arguments.</param>
    /// <returns>The target, powered on.</returns>
    /// <exception cref="ArgumentException">An argument is invalid or the ROM is missing.</exception>
    internal static Trs80Model100DebugTarget Launch(JsonObject args)
    {
        Trs80Model100Variant? model = args.String("model") switch
        {
            null => null,
            "100" or "m100" or "model100" => Trs80Model100Variant.Model100,
            "102" or "t102" or "tandy102" => Trs80Model100Variant.Tandy102,
            _ => throw new ArgumentException("model must be 100 or 102.")
        };

        byte[] rom = Rom(args, model ?? Trs80Model100Variant.Model100);
        byte[]? option = args.String("optionRom") is { } optionPath ? ReadRom(optionPath, "option ROM") : null;

        Trs80Model100Configuration configuration = new()
        {
            RamKilobytes = args.Int("ramKilobytes") ?? 32,
            StartTime = args.String("time") is { } time ? ParseTime(time) : null
        };

        if (configuration.RamKilobytes is not (8 or 16 or 24 or 32))
        {
            throw new ArgumentException("ramKilobytes must be 8, 16, 24 or 32.");
        }

        Trs80Model100Machine machine = new(configuration, new(rom, option), model);
        Trs80Model100DebugTarget target = new(machine);
        if (args.String("ramImage") is { } image)
        {
            string path = Path.GetFullPath(image);
            if (File.Exists(path) && args.Bool("coldStart") != true)
            {
                byte[] ram = File.ReadAllBytes(path);
                int size = configuration.RamKilobytes * 1024;
                if (ram.Length != size)
                {
                    throw new ArgumentException(
                        $"The RAM image {path} has {ram.Length} bytes; a {configuration.RamKilobytes} KB machine's has {size}.");
                }

                machine.LoadRam(ram);
                machine.PowerOn();
            }

            target._ramImagePath = path;
        }

        return target;
    }

    /// <summary>
    ///  Finds a ROM dump in a folder or its MAME and fixture folders.
    /// </summary>
    /// <param name="directory">The folder.</param>
    /// <param name="names">The names to look for, in order.</param>
    /// <returns>The path, or null.</returns>
    internal static string? FindRom(string directory, IReadOnlyList<string> names)
    {
        foreach (string name in names)
        {
            foreach (string folder in s_folders.Prepend(""))
            {
                string path = Path.Join(directory, folder, name);
                if (File.Exists(path)) { return path; }
            }
        }

        return null;
    }

    private static byte[] Rom(JsonObject args, Trs80Model100Variant model)
    {
        string? directory = args.String("romDirectory") ?? Environment.GetEnvironmentVariable(RomDirectoryVariable);
        if (args.String("rom") is { } named)
        {
            // A path, or a name in the ROM folder or its MAME and fixture folders.
            string? found = File.Exists(named) || directory is null ? named : FindRom(directory, [named]);
            return ReadRom(found ?? named, "ROM");
        }

        string[] names = model == Trs80Model100Variant.Tandy102 ? s_tandy102Roms : s_model100Roms;
        string machineName = model == Trs80Model100Variant.Tandy102 ? "Tandy 102" : "Model 100";
        if (directory is null)
        {
            throw new ArgumentException(
                $"The {machineName} needs its ROM, which is not part of Retrocore: give its file as rom, or a folder "
                    + $"holding {names[0]} as romDirectory (or {RomDirectoryVariable}).");
        }

        string path = FindRom(directory, names) ?? throw new ArgumentException(
            $"The {machineName}'s ROM is missing from {directory}; it needs one of {string.Join(", ", names)}.");

        return ReadRom(path, "ROM");
    }

    private static byte[] ReadRom(string path, string what)
    {
        if (!File.Exists(path))
        {
            throw new ArgumentException($"The {what} {path} does not exist.");
        }

        byte[] bytes = File.ReadAllBytes(path);
        bool fits = what == "ROM" ? bytes.Length == Trs80Model100Roms.RomSize : bytes.Length is > 0 and <= Trs80Model100Roms.RomSize;
        if (!fits)
        {
            throw new ArgumentException($"The {what} {path} must be {(what == "ROM" ? "" : "1 to ")}{Trs80Model100Roms.RomSize} bytes.");
        }

        return bytes;
    }

    private static DateTime ParseTime(string time) =>
        DateTime.TryParse(time, CultureInfo.InvariantCulture, DateTimeStyles.AllowWhiteSpaces, out DateTime parsed)
            ? parsed
            : throw new ArgumentException("time must be a date and time, such as 2026-11-26T09:30:00.");

    /// <summary>
    ///  Runs the machine in emulated time, before a program loads, so the ROM has set up its RAM.
    /// </summary>
    /// <param name="seconds">The emulated seconds.</param>
    internal void Boot(double seconds)
    {
        _machine.Run((ulong)(seconds * Trs80Model100Timing.ClockHertz));
        while (!_machine.Processor.IsInstructionBoundary) { _machine.StepCycle(); }
    }
}
