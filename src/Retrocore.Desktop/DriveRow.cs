// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Devices;

namespace Retrocore.Desktop;

/// <summary>
///  A drive as the Drives section shows it.
/// </summary>
/// <param name="Name">The drive's name, such as <c>Drive 1</c>.</param>
/// <param name="Kind">What kind of drive it is.</param>
/// <param name="Media">The media's file name and whether it changed, or null when the drive is empty.</param>
/// <param name="Locked">Whether the machine cannot write the media.</param>
/// <param name="Activity">What the drive is doing.</param>
internal sealed record DriveRow(string Name, DeviceKind Kind, string? Media, bool Locked, DeviceActivity Activity);