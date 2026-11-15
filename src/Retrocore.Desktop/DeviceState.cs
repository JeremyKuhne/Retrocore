// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Devices;
using System.Globalization;

namespace Retrocore.Desktop;

/// <summary>
///  A device as the Drives section shows it, read from the machine at one moment: what <c>retro/devices</c> gives
///  the extension's Drives view.
/// </summary>
/// <param name="Id">The device's id.</param>
/// <param name="Kind">What kind of device it is.</param>
/// <param name="Info">Its name, description, controller, formats, operations and geometry.</param>
/// <param name="Media">Its media, or null when empty.</param>
/// <param name="Activity">What it is doing.</param>
/// <param name="Head">A disk drive's head, or null.</param>
/// <param name="Transport">A tape drive's transport, or null.</param>
/// <param name="Blocks">Block storage's size and last block, or null.</param>
internal sealed record DeviceState(
    string Id,
    DeviceKind Kind,
    DeviceInfo Info,
    MediaState? Media,
    DeviceActivity Activity,
    DiskHead? Head,
    TapeTransport? Transport,
    (long Count, long? Last)? Blocks)
{
    /// <summary>
    ///  Reads a device.
    /// </summary>
    /// <param name="device">The device.</param>
    /// <returns>Its state now.</returns>
    internal static DeviceState Of(IDevice device) => new(
        device.Id,
        device.Kind,
        device.Info,
        device.Media,
        device.Activity,
        device is IDiskDrive drive ? drive.Head : null,
        device is ITapeDrive tape ? tape.Transport : null,
        device is IBlockStorage storage ? (storage.BlockCount, storage.LastBlock) : null);

    /// <summary>
    ///  Gets whether the device can do an operation.
    /// </summary>
    /// <param name="operation">The operation.</param>
    /// <returns>True when it can.</returns>
    internal bool Can(MediaOperations operation) => (Info.Operations & operation) != 0;

    /// <summary>
    ///  Gets the one-line summary after the device's name: its media, where it is and what it is doing, as the
    ///  extension's Drives view writes it.
    /// </summary>
    internal string Summary
    {
        get
        {
            List<string> parts = [Media is { } media ? FileName(media) : "empty"];
            if (Head is { } head)
            {
                string track = head.Track == Math.Floor(head.Track)
                    ? ((int)head.Track).ToString(CultureInfo.CurrentCulture)
                    : head.Track.ToString("0.00", CultureInfo.CurrentCulture);

                parts.Add($"track {track}" + (Info.Sides > 1 ? $" side {head.Side}" : "") + (head.Sector is { } sector ? $" sector {sector}" : ""));
            }

            if (Transport is { } transport && Media is not null)
            {
                parts.Add($"{transport.Position:N0} of {transport.Length:N0} bytes");
            }

            if (Blocks is { Last: { } last }) { parts.Add($"block {last}"); }
            if (Media?.WriteProtected == true) { parts.Add("read-only"); }
            if (Media?.Changed == true) { parts.Add("changed"); }
            if (Activity != DeviceActivity.Idle)
            {
                parts.Add(Activity.ToString().ToLowerInvariant());
            }
            else if (Head?.Motor == true || Transport?.Motor == true)
            {
                parts.Add("motor on");
            }

            return string.Join(" · ", parts);
        }
    }

    /// <summary>
    ///  Gets the detail rows under the device, as the extension's Drives view lists them.
    /// </summary>
    internal IReadOnlyList<(string Detail, string Value)> Details
    {
        get
        {
            List<(string, string)> rows =
            [
                ("Media", Media is { } media ? $"{media.Label} ({media.Format})" : "none"),
                ("Activity", Activity.ToString().ToLowerInvariant()),
            ];

            if (Media is { } loaded)
            {
                rows.Add(("Write protected", loaded.WriteProtected ? "yes" : "no"));
                rows.Add(("Changed", loaded.Changed ? "yes, not saved to the image" : "no"));
            }

            if (Head is { } head)
            {
                rows.Add(("Motor", head.Motor ? "on" : "off"));
                rows.Add(("Selected", head.Selected ? "yes" : "no"));
                rows.Add(("Track", head.Track.ToString(CultureInfo.CurrentCulture)));
                if (Info.Sides > 1) { rows.Add(("Side", head.Side.ToString(CultureInfo.CurrentCulture))); }
                if (head.Sector is { } sector) { rows.Add(("Sector", sector.ToString(CultureInfo.CurrentCulture))); }
            }

            if (Transport is { } transport)
            {
                rows.Add(("Motor", transport.Motor ? "on" : "off"));
                rows.Add(("Mode", transport.Mode.ToString().ToLowerInvariant()));
                rows.Add(("Position", $"{transport.Position:N0} of {transport.Length:N0} bytes"));
            }

            if (Blocks is { } blocks)
            {
                rows.Add(("Blocks", blocks.Count.ToString("N0", CultureInfo.CurrentCulture)));
                rows.Add(("Last block", blocks.Last is { } last ? last.ToString(CultureInfo.CurrentCulture) : "none yet"));
            }

            rows.Add(("Device", Info.Description));
            rows.Add(("Controller", Info.Controller));
            if (Info.Tracks > 0)
            {
                rows.Add(("Geometry", $"{Info.Tracks} tracks, {Info.Sides} side{(Info.Sides == 1 ? "" : "s")}"));
            }

            if (Info.Formats.Count > 0)
            {
                rows.Add(("Formats", string.Join(", ", Info.Formats.Select(format => "." + format))));
            }

            return rows;
        }
    }

    // The media's file name, or its format when it has none, as a tape recorded in memory has.
    private static string FileName(MediaState media)
    {
        string name = Path.GetFileName(media.Label);
        return name.Length != 0 ? name : media.Format;
    }
}