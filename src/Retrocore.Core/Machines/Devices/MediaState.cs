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
public readonly record struct MediaState(string Label, string Format, bool WriteProtected, bool Changed);
