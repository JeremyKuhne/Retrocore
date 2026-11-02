// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Devices;

/// <summary>
///  A floppy disk drive.
/// </summary>
public interface IDiskDrive : IDevice
{
    /// <summary>
    ///  Gets where the drive's head is and whether it is turning.
    /// </summary>
    DiskHead Head { get; }
}
