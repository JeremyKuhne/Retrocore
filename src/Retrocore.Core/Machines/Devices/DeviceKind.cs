// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Devices;

/// <summary>
///  What a device is.
/// </summary>
public enum DeviceKind : byte
{
    /// <summary>
    ///  A floppy disk drive: a head that steps between tracks over a turning disk.
    /// </summary>
    FloppyDrive,

    /// <summary>
    ///  A cassette or other tape drive: media read or written in one pass.
    /// </summary>
    TapeDrive,

    /// <summary>
    ///  Storage addressed by block number, such as a hard disk or a ProDOS block device.
    /// </summary>
    BlockStorage
}
