// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Devices;

/// <summary>
///  The media in a device.
/// </summary>
/// <param name="Label">What the host called the media when it inserted it, such as the image's path.</param>
/// <param name="Format">The image format, such as <c>JV3</c> or <c>WOZ</c>.</param>
/// <param name="WriteProtected">Whether the machine cannot write to it.</param>
/// <param name="Changed">Whether the machine has written to it since it was inserted.</param>
public readonly record struct MediaState(string Label, string Format, bool WriteProtected, bool Changed)
{
    /// <summary>
    ///  Gets what the media holds, where the device can tell, such as <c>Level I tape</c>; null when it cannot.
    /// </summary>
    public string? Contents { get; init; }

    /// <summary>
    ///  Gets why the machine cannot read the media, such as a tape recorded for another ROM; null when nothing is
    ///  known to be wrong.
    /// </summary>
    public string? Warning { get; init; }
}
