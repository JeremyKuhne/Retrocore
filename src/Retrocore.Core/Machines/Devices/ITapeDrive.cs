// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Devices;

/// <summary>
///  A cassette or other tape drive.
/// </summary>
public interface ITapeDrive : IDevice
{
    /// <summary>
    ///  Gets the transport: its motor, mode and position.
    /// </summary>
    TapeTransport Transport { get; }
}
