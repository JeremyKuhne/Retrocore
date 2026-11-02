// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Devices;

/// <summary>
///  What a device is doing now.
/// </summary>
public enum DeviceActivity : byte
{
    /// <summary>
    ///  Nothing is moving data, though a motor may be turning.
    /// </summary>
    Idle,

    /// <summary>
    ///  The head is stepping to a track.
    /// </summary>
    Seeking,

    /// <summary>
    ///  Data is coming from the media.
    /// </summary>
    Reading,

    /// <summary>
    ///  Data is going to the media.
    /// </summary>
    Writing
}
