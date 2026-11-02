// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Apple2;

/// <summary>
///  Side-effect-free drive telemetry for standalone and debugger views.
/// </summary>
/// <param name="Drive">The drive number, one or two.</param>
/// <param name="QuarterTrack">The radial head position.</param>
/// <param name="BitPosition">The next rotational bit position.</param>
/// <param name="BitCount">The current track length.</param>
/// <param name="Motor">Whether the selected drive is still spinning.</param>
/// <param name="Mounted">Whether media is inserted.</param>
/// <param name="WriteProtected">Whether physical media writes are prohibited.</param>
/// <param name="Dirty">Whether media has unpersisted changes.</param>
public readonly record struct DiskDriveState(
    int Drive,
    int QuarterTrack,
    int BitPosition,
    int BitCount,
    bool Motor,
    bool Mounted,
    bool WriteProtected,
    bool Dirty);
