// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json.Nodes;
using Retrocore.Machines.Devices;

namespace Retrocore.Debug;

/// <summary>
///  Controls host pacing and records the requested policy for each kind of media.
/// </summary>
/// <param name="target">The machine with the media devices.</param>
internal sealed class MediaSpeedPolicy(IDebugTarget target)
{
    private MediaSpeed? _tape;
    private MediaSpeed? _disk;

    /// <summary>
    ///  Gets whether the machine has a tape drive.
    /// </summary>
    internal bool HasTape => target.Devices.Any(device => device is ITapeDrive);

    /// <summary>
    ///  Gets whether the machine has a disk or block drive.
    /// </summary>
    internal bool HasDisk => target.Devices.Any(IsDisk);

    /// <summary>
    ///  Gets the requested tape speed.
    /// </summary>
    internal MediaSpeed Tape => _tape ?? Default(tape: true);

    /// <summary>
    ///  Gets the requested disk speed.
    /// </summary>
    internal MediaSpeed Disk => _disk ?? Default(tape: false);

    /// <summary>
    ///  Gets the image boot policy, retaining unthrottled legacy project launches.
    /// </summary>
    /// <param name="tape">Whether the boot uses tape rather than disk.</param>
    /// <returns>The requested boot policy.</returns>
    internal MediaSpeed Boot(bool tape) => (tape ? _tape : _disk) ?? MediaSpeed.Fast;

    /// <summary>
    ///  Gets whether current media work calls for unthrottled execution.
    /// </summary>
    internal bool Accelerated
    {
        get
        {
            if (target.Accelerated) { return true; }
            if (_disk is (MediaSpeed.Fast or MediaSpeed.Skip) && target is AltairDebugTarget { DiskBusy: true })
            {
                return true;
            }

            if ((_tape is null or MediaSpeed.Normal) && (_disk is null or MediaSpeed.Normal)) { return false; }
            IReadOnlyList<IDevice> devices = target.Devices;
            for (int i = 0; i < devices.Count; i++)
            {
                IDevice device = devices[i];
                if (device.Activity != DeviceActivity.Idle
                    && (device is ITapeDrive ? _tape is MediaSpeed.Fast or MediaSpeed.Skip
                        : IsDisk(device) && target is not AltairDebugTarget && _disk is MediaSpeed.Fast or MediaSpeed.Skip))
                {
                    return true;
                }
            }

            return false;
        }
    }

    /// <summary>
    ///  Sets the requested speed for one media kind.
    /// </summary>
    /// <param name="tape">Whether to set tape rather than disk speed.</param>
    /// <param name="speed">The requested value.</param>
    internal void Set(bool tape, MediaSpeed speed)
    {
        if (tape) { _tape = speed; }
        else { _disk = speed; }
        bool fast = speed != MediaSpeed.Normal;
        switch (target)
        {
            case Apple2DebugTarget apple when !tape: apple.FastDisk = fast; break;
            case Apple3DebugTarget apple when !tape: apple.FastDisk = fast; break;
            case Trs80Model2DebugTarget trs when !tape: trs.FastDisk = fast; break;
            case KayproDebugTarget kaypro when !tape: kaypro.FastDisk = fast; break;
            case Apple1DebugTarget apple when tape: apple.FastCassette = fast; break;
            case CocoDebugTarget coco when tape: coco.FastCassette = fast; break;
            case PetDebugTarget pet when tape: pet.FastCassette = fast; break;
            case Vic20DebugTarget vic when tape: vic.FastCassette = fast; break;
            case Trs80DebugTarget trs when tape: trs.FastCassette = fast; break;
            case Trs80Model3DebugTarget trs when tape: trs.FastCassette = fast; break;
            case AltairDebugTarget altair when tape: altair.FastCassette = fast; break;
            case BbcDebugTarget bbc when tape: bbc.FastCassette = fast; break;
            case AtariDebugTarget atari when tape: atari.FastCassette = fast; break;
            case Trs80Model100DebugTarget trs when tape: trs.FastCassette = fast; break;
        }
    }

    /// <summary>
    ///  Applies validated media speeds to the new target.
    /// </summary>
    /// <param name="settings">The tape and disk choices, if supplied.</param>
    internal void Apply((MediaSpeed? Tape, MediaSpeed? Disk) settings)
    {
        if (settings.Tape is { } tape) { Set(tape: true, tape); }
        if (settings.Disk is { } disk) { Set(tape: false, disk); }
    }

    /// <summary>
    ///  Resolves and validates the launch preferences before replacing the target.
    /// </summary>
    /// <param name="args">The merged launch arguments.</param>
    /// <returns>The tape and disk choices, if supplied.</returns>
    internal static (MediaSpeed? Tape, MediaSpeed? Disk) LaunchModes(JsonObject args)
    {
        JsonObject? defaults = args["mediaSpeedDefaults"] as JsonObject;
        return (LaunchMode(args, tape: true) ?? Read(defaults?["tape"]),
            LaunchMode(args, tape: false) ?? Read(defaults?["disk"]));
    }

    /// <summary>
    ///  Gets an explicit launch preference, favoring the new mode over its legacy boolean.
    /// </summary>
    /// <param name="args">The launch arguments.</param>
    /// <param name="tape">Whether to resolve tape rather than disk speed.</param>
    /// <returns>The launch preference, or null when neither setting was given.</returns>
    internal static MediaSpeed? LaunchMode(JsonObject args, bool tape)
    {
        if (args[tape ? "tapeSpeed" : "diskSpeed"] is { } mode) { return Parse(mode); }
        return args.Bool(tape ? "fastCassette" : "fastDisk") switch
        {
            true => MediaSpeed.Fast,
            false => MediaSpeed.Normal,
            null => null
        };
    }

    /// <summary>
    ///  Writes both settings, with null for a kind not installed.
    /// </summary>
    /// <returns>The settings object.</returns>
    internal JsonObject ToJson() => new()
    {
        ["tape"] = HasTape ? Name(Tape) : null,
        ["disk"] = HasDisk ? Name(Disk) : null
    };

    /// <summary>
    ///  Finds an active device of the indicated media kind.
    /// </summary>
    /// <param name="tape">Whether to look for tape rather than disk.</param>
    /// <returns>The first busy device, or null.</returns>
    internal IDevice? Active(bool tape) => !tape && target is AltairDebugTarget { DiskBusy: false }
        ? null
        : target.Devices.FirstOrDefault(device =>
            (tape ? device is ITapeDrive : IsDisk(device)) && device.Activity != DeviceActivity.Idle);

    /// <summary>
    ///  Builds a protocol result for a media operation.
    /// </summary>
    /// <param name="tape">Whether the operation uses tape rather than disk.</param>
    /// <param name="requested">The selected mode.</param>
    /// <param name="effective">The mode that actually ran.</param>
    /// <param name="device">The device ID.</param>
    /// <param name="reason">The fallback reason, if any.</param>
    /// <returns>The result object.</returns>
    internal static JsonObject Outcome(bool tape, MediaSpeed requested, MediaSpeed effective, string device, string? reason = null) => new()
    {
        ["kind"] = tape ? "tape" : "disk",
        ["requested"] = Name(requested),
        ["effective"] = Name(effective),
        ["device"] = device,
        ["reason"] = reason
    };

    /// <summary>
    ///  Parses a media speed from a configuration value.
    /// </summary>
    /// <param name="value">The value to parse.</param>
    /// <returns>The parsed mode.</returns>
    internal static MediaSpeed Parse(JsonNode? value) =>
        Read(value) ?? throw new ArgumentException("Media speed must be normal, fast or skip.");

    /// <summary>
    ///  Reads a saved preference without applying an invalid setting.
    /// </summary>
    /// <param name="value">The value from settings.</param>
    /// <returns>The mode, or null if not recognized.</returns>
    internal static MediaSpeed? Read(JsonNode? value) => (value is JsonValue json && json.TryGetValue(out string? name) ? name : null) switch
    {
        "normal" => MediaSpeed.Normal,
        "fast" => MediaSpeed.Fast,
        "skip" => MediaSpeed.Skip,
        _ => null
    };

    /// <summary>
    ///  Gets the protocol name of a media speed.
    /// </summary>
    /// <param name="speed">The mode to name.</param>
    /// <returns>The protocol name.</returns>
    internal static string Name(MediaSpeed speed) => speed switch
    {
        MediaSpeed.Normal => "normal",
        MediaSpeed.Fast => "fast",
        MediaSpeed.Skip => "skip",
        _ => throw new ArgumentOutOfRangeException(nameof(speed))
    };

    private static bool IsDisk(IDevice device) => device is IDiskDrive or IBlockStorage;

    private MediaSpeed Default(bool tape) => LegacyFast(tape) == true ? MediaSpeed.Fast : MediaSpeed.Normal;

    private bool? LegacyFast(bool tape) => target switch
    {
        Apple2DebugTarget apple when !tape => apple.FastDisk,
        Apple3DebugTarget apple when !tape => apple.FastDisk,
        Trs80Model2DebugTarget trs when !tape => trs.FastDisk,
        KayproDebugTarget kaypro when !tape => kaypro.FastDisk,
        Apple1DebugTarget apple when tape => apple.FastCassette,
        CocoDebugTarget coco when tape => coco.FastCassette,
        PetDebugTarget pet when tape => pet.FastCassette,
        Vic20DebugTarget vic when tape => vic.FastCassette,
        Trs80DebugTarget trs when tape => trs.FastCassette,
        Trs80Model3DebugTarget trs when tape => trs.FastCassette,
        AltairDebugTarget altair when tape => altair.FastCassette,
        BbcDebugTarget bbc when tape => bbc.FastCassette,
        AtariDebugTarget atari when tape => atari.FastCassette,
        Trs80Model100DebugTarget trs when tape => trs.FastCassette,
        _ => null
    };
}
