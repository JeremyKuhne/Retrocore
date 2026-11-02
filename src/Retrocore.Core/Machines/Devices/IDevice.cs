// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Devices;

/// <summary>
///  A device installed in a machine, such as a floppy or tape drive.
/// </summary>
/// <remarks>
///  <para>
///   Every property reads the device's state without side effects, so a debugger can show it at any time. Each
///   kind of device adds its own state: <see cref="IDiskDrive"/>, <see cref="ITapeDrive"/> and
///   <see cref="IBlockStorage"/>. Inserting media is the concrete device's job, since the image formats are
///   the machine's own.
///  </para>
/// </remarks>
public interface IDevice
{
    /// <summary>
    ///  Gets the device's identifier, stable for the machine's configuration, such as <c>disk0</c>.
    /// </summary>
    string Id { get; }

    /// <summary>
    ///  Gets what kind of device it is.
    /// </summary>
    DeviceKind Kind { get; }

    /// <summary>
    ///  Gets what the device is.
    /// </summary>
    DeviceInfo Info { get; }

    /// <summary>
    ///  Gets the media in the device, or null when it is empty.
    /// </summary>
    MediaState? Media { get; }

    /// <summary>
    ///  Gets what the device is doing now.
    /// </summary>
    DeviceActivity Activity { get; }
}
