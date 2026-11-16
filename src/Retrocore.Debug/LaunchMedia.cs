// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Devices;
using System.Text.Json.Nodes;

namespace Retrocore.Debug;

/// <summary>
///  The media a launch itself gives, which no insert can change: the Apple II's slot 7 block device, which comes
///  from the launch's <c>diskImage</c>.
/// </summary>
/// <remarks>
///  <para>
///   A save to another image moves such media to that image, as Save As moves a Disk II's disk; the machine built
///   again, as a restart builds it, takes the launch with the media where they now are.
///  </para>
/// </remarks>
internal static class LaunchMedia
{
    /// <summary>
    ///  Gets a launch configuration with its fixed media as a machine now has them.
    /// </summary>
    /// <param name="devices">The machine's devices.</param>
    /// <param name="configuration">The launch configuration the machine was built from.</param>
    /// <returns>
    ///  The configuration, or a copy of it with <c>diskImage</c> as the image slot 7 now comes from, when that is
    ///  another file that is still there.
    /// </returns>
    internal static JsonObject Current(IEnumerable<IDevice> devices, JsonObject configuration)
    {
        if (devices.FirstOrDefault(device => device.Id == "slot7") is not { Media: { } media }
            || !Path.IsPathFullyQualified(media.Label)
            || !File.Exists(media.Label))
        {
            return configuration;
        }

        string? launched = configuration["diskImage"] is JsonValue value && value.TryGetValue(out string? text) ? text : null;
        if (launched is not null && string.Equals(Path.GetFullPath(launched), media.Label, StringComparison.OrdinalIgnoreCase))
        {
            return configuration;
        }

        JsonObject moved = (JsonObject)configuration.DeepClone();
        moved["diskImage"] = media.Label;
        return moved;
    }
}
