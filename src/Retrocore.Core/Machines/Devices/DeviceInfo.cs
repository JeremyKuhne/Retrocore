// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Devices;

/// <summary>
///  What a device is, which does not change while the machine runs.
/// </summary>
public sealed record DeviceInfo
{
    /// <summary>
    ///  Gets the name the machine's own documentation uses, such as <c>Drive 0</c> or <c>Cassette</c>.
    /// </summary>
    public required string Name { get; init; }

    /// <summary>
    ///  Gets what the device is, such as <c>5¼-inch single-sided floppy drive</c>.
    /// </summary>
    public required string Description { get; init; }

    /// <summary>
    ///  Gets what drives the device, such as <c>FD1771 in the Expansion Interface</c>.
    /// </summary>
    public required string Controller { get; init; }

    /// <summary>
    ///  Gets the image file extensions the host can insert, without dots, such as <c>jv1</c> and <c>jv3</c>.
    /// </summary>
    public IReadOnlyList<string> Formats { get; init; } = [];

    /// <summary>
    ///  Gets what the host can do to the device's media.
    /// </summary>
    public MediaOperations Operations { get; init; }

    /// <summary>
    ///  Gets the tracks the head can reach, or 0 when the device has none.
    /// </summary>
    public int Tracks { get; init; }

    /// <summary>
    ///  Gets the sides the device reads, or 0 when the device has none.
    /// </summary>
    public int Sides { get; init; }
}
