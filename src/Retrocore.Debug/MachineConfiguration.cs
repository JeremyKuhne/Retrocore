// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json.Nodes;
using Retrocore.Machines.Devices;

namespace Retrocore.Debug;

/// <summary>
///  The part of a machine a launch can restore: the cards in its slots and the media in its drives. The editor
///  keeps the last one it saw for each launch configuration and gives it back at the next launch.
/// </summary>
/// <remarks>
///  <para>
///   The configuration is <c>{ "cards": { "4": "mockingboard", "5": "diskII16", ... }, "media": { "disk1":
///   { "path": "...", "writeProtected": false }, "disk2": null } }</c>. A drive given as null is empty. Media the
///   host cannot insert again, such as a disk a DOS launch built or a tape being recorded, is left out, so the
///   launch's own stays.
///  </para>
/// </remarks>
internal static class MachineConfiguration
{
    /// <summary>
    ///  Gets a machine's configuration.
    /// </summary>
    /// <param name="target">The machine.</param>
    /// <returns>Its cards, when it has slots, and the media in the drives that take media.</returns>
    internal static JsonObject Capture(IDebugTarget target)
    {
        JsonObject media = [];
        foreach (IDevice device in target.Devices)
        {
            if (!device.Info.Operations.HasFlag(MediaOperations.Insert)) { continue; }
            if (device.Media is not { } state)
            {
                media[device.Id] = null;
            }
            else if (Reinsertable(device, state))
            {
                media[device.Id] = new JsonObject { ["path"] = state.Label, ["writeProtected"] = state.WriteProtected };
            }
        }

        JsonObject configuration = [];
        if (target.Cards() is { } cards) { configuration["cards"] = cards; }
        configuration["media"] = media;
        return configuration;
    }

    /// <summary>
    ///  Puts a saved configuration's cards and media into a machine, as far as it can.
    /// </summary>
    /// <param name="target">The machine, as the launch built it.</param>
    /// <param name="saved">The configuration.</param>
    /// <returns>What could not be restored, one message each.</returns>
    internal static List<string> Restore(IDebugTarget target, JsonObject saved)
    {
        List<string> problems = [];
        if (saved["cards"] is JsonObject cards) { problems.AddRange(target.RestoreCards(cards)); }
        if (saved["media"] is not JsonObject media) { return problems; }
        foreach ((string id, JsonNode? node) in media)
        {
            if (target.Devices.FirstOrDefault(device => device.Id == id) is not { } device)
            {
                problems.Add($"There is no {id} for its saved media.");
                continue;
            }

            try
            {
                Restore(target, device, node as JsonObject);
            }
            catch (Exception error) when (error is ArgumentException or IOException or InvalidOperationException)
            {
                problems.Add($"{device.Info.Name}: {error.Message}");
            }
        }

        return problems;
    }

    private static void Restore(IDebugTarget target, IDevice device, JsonObject? saved)
    {
        string? path = saved?.String("path");
        if (path is null)
        {
            if (device.Media is not null && device.Info.Operations.HasFlag(MediaOperations.Eject))
            {
                target.DeviceAction(device, "eject", []);
            }

            return;
        }

        if (!File.Exists(path)) { throw new IOException($"{path} no longer exists."); }
        if (!string.Equals(device.Media?.Label, path, StringComparison.OrdinalIgnoreCase))
        {
            target.DeviceAction(device, "insert", new JsonObject { ["path"] = path });
        }

        bool writeProtected = saved?.Bool("writeProtected") ?? false;
        if (device.Info.Operations.HasFlag(MediaOperations.WriteProtect) && device.Media?.WriteProtected != writeProtected)
        {
            target.DeviceAction(device, "writeProtect", new JsonObject { ["writeProtected"] = writeProtected });
        }
    }

    // An image the host inserted from a file that is still there; a tape only while it plays, as a recording's file
    // is not written until its tape is ejected.
    private static bool Reinsertable(IDevice device, MediaState media) =>
        Path.IsPathFullyQualified(media.Label)
            && File.Exists(media.Label)
            && (device is not ITapeDrive || media.WriteProtected);
}
