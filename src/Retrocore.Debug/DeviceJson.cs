// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json.Nodes;
using Retrocore.Machines.Devices;

namespace Retrocore.Debug;

/// <summary>
///  Writes a machine's devices for the <c>retro/devices</c> request and event.
/// </summary>
/// <remarks>
///  <para>
///   Each device is an object with its <c>id</c>, <c>kind</c> (<c>floppyDrive</c>, <c>tapeDrive</c> or
///   <c>blockStorage</c>), <c>name</c>, <c>description</c>, <c>controller</c>, <c>formats</c>, <c>operations</c>
///   (<c>insert</c>, <c>eject</c>, <c>record</c>, <c>writeProtect</c>, <c>save</c>), <c>tracks</c> and <c>sides</c>; its
///   <c>media</c> (<c>label</c>, <c>format</c>, <c>writeProtected</c>, <c>changed</c>) or null; its
///   <c>activity</c> (<c>idle</c>, <c>seeking</c>, <c>reading</c>, <c>writing</c>); and its kind's state:
///   <c>head</c> (<c>motor</c>, <c>selected</c>, <c>track</c>, <c>side</c>, <c>sector</c>), <c>transport</c>
///   (<c>motor</c>, <c>mode</c>, <c>position</c>, <c>length</c>) or <c>blocks</c> (<c>count</c>,
///   <c>last</c>).
///  </para>
/// </remarks>
internal static class DeviceJson
{
    /// <summary>
    ///  Writes the devices.
    /// </summary>
    /// <param name="devices">The machine's devices.</param>
    /// <returns>The <c>retro/devices</c> body.</returns>
    internal static JsonObject Write(IReadOnlyList<IDevice> devices)
    {
        JsonArray list = [];
        foreach (IDevice device in devices) { list.Add((JsonNode)Write(device)); }
        return new JsonObject { ["devices"] = list };
    }

    /// <summary>
    ///  Writes one device.
    /// </summary>
    /// <param name="device">The device.</param>
    /// <returns>Its object.</returns>
    internal static JsonObject Write(IDevice device)
    {
        DeviceInfo info = device.Info;
        JsonObject result = new()
        {
            ["id"] = device.Id,
            ["kind"] = Camel(device.Kind.ToString()),
            ["name"] = info.Name,
            ["description"] = info.Description,
            ["controller"] = info.Controller,
            ["formats"] = info.Formats.ToJsonArray(),
            ["operations"] = Operations(info.Operations),
            ["tracks"] = info.Tracks,
            ["sides"] = info.Sides,
            ["media"] = device.Media is { } media ? Media(media) : null,
            ["activity"] = Camel(device.Activity.ToString())
        };

        switch (device)
        {
            case IDiskDrive drive:
                DiskHead head = drive.Head;
                result["head"] = new JsonObject
                {
                    ["motor"] = head.Motor,
                    ["selected"] = head.Selected,
                    ["track"] = head.Track,
                    ["side"] = head.Side,
                    ["sector"] = head.Sector is { } sector ? sector : null
                };

                break;
            case ITapeDrive tape:
                TapeTransport transport = tape.Transport;
                result["transport"] = new JsonObject
                {
                    ["motor"] = transport.Motor,
                    ["mode"] = Camel(transport.Mode.ToString()),
                    ["position"] = transport.Position,
                    ["length"] = transport.Length
                };

                break;
            case IBlockStorage storage:
                result["blocks"] = new JsonObject
                {
                    ["count"] = storage.BlockCount,
                    ["last"] = storage.LastBlock is { } block ? block : null
                };

                break;
        }

        return result;
    }

    private static JsonObject Media(MediaState media) => new()
    {
        ["label"] = media.Label,
        ["format"] = media.Format,
        ["writeProtected"] = media.WriteProtected,
        ["changed"] = media.Changed
    };

    private static JsonArray Operations(MediaOperations operations)
    {
        JsonArray result = [];
        if ((operations & MediaOperations.Insert) != 0) { result.Add((JsonNode)"insert"); }
        if ((operations & MediaOperations.Eject) != 0) { result.Add((JsonNode)"eject"); }
        if ((operations & MediaOperations.Record) != 0) { result.Add((JsonNode)"record"); }
        if ((operations & MediaOperations.WriteProtect) != 0) { result.Add((JsonNode)"writeProtect"); }
        if ((operations & MediaOperations.Save) != 0) { result.Add((JsonNode)"save"); }
        return result;
    }

    private static string Camel(string name) => string.Concat(char.ToLowerInvariant(name[0]).ToString(), name.AsSpan(1));
}
