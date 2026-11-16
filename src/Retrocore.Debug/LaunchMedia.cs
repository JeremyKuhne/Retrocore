// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Devices;
using Retrocore.Media;
using System.Text.Json.Nodes;

namespace Retrocore.Debug;

/// <summary>
///  The media a launch itself gives, which no insert can change: the Apple II's slot 7 block device, which comes
///  from the launch's <c>diskImage</c>.
/// </summary>
/// <remarks>
///  <para>
///   A save to another image moves such media to that image, as Save As moves a Disk II's disk. A saved machine
///   keeps it under <c>media</c> as it keeps any drive's, and the launch built from that saved machine takes its
///   <c>diskImage</c> from there, before the machine is built, so a restart or the next launch has the image where
///   it now is.
///  </para>
/// </remarks>
internal static class LaunchMedia
{
    private const string Slot7 = "slot7";

    /// <summary>
    ///  Gets how paths compare as files do on this system: without case on Windows and macOS, by case elsewhere.
    /// </summary>
    internal static StringComparison PathComparison { get; } = OperatingSystem.IsWindows() || OperatingSystem.IsMacOS()
        ? StringComparison.OrdinalIgnoreCase
        : StringComparison.Ordinal;

    /// <summary>
    ///  Gets whether a device's media come from the launch, so a saved machine keeps them for the launch to take.
    /// </summary>
    /// <param name="device">The device.</param>
    /// <returns>True for slot 7's block device.</returns>
    internal static bool FromLaunch(IDevice device) =>
        device.Id == Slot7 && device is IMediumSlot && !device.Info.Operations.HasFlag(MediaOperations.Insert);

    /// <summary>
    ///  Gets a launch configuration with the media a saved machine gives in place of its own.
    /// </summary>
    /// <param name="configuration">The launch configuration.</param>
    /// <param name="saved">The saved machine, or null.</param>
    /// <returns>
    ///  The configuration, or a copy of it with <c>diskImage</c> as the image the saved machine's slot 7 comes from,
    ///  when the launch gives slot 7 a block image and the saved one is another file that is still there.
    /// </returns>
    internal static JsonObject WithSaved(JsonObject configuration, JsonNode? saved)
    {
        if (saved?["media"]?[Slot7]?["path"] is not JsonValue value
            || !value.TryGetValue(out string? path)
            || !Path.IsPathFullyQualified(path)
            || !BlockImage(path)
            || !File.Exists(path))
        {
            return configuration;
        }

        // Slot 7 is there only for a block image the launch does not give the Disk II.
        if (Text(configuration, "diskImage") is not { } launched
            || !BlockImage(launched)
            || Text(configuration, "diskController") == "diskII"
            || configuration["diskBootRom"] is not null
            || string.Equals(Path.GetFullPath(launched), path, PathComparison))
        {
            return configuration;
        }

        JsonObject moved = (JsonObject)configuration.DeepClone();
        moved["diskImage"] = path;
        return moved;
    }

    private static bool BlockImage(string path) => Path.GetExtension(path).ToLowerInvariant() is ".po" or ".hdv" or ".2mg";

    private static string? Text(JsonObject configuration, string name) =>
        configuration[name] is JsonValue value && value.TryGetValue(out string? text) ? text : null;
}
