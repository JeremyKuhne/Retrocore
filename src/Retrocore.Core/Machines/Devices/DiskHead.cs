// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Devices;

/// <summary>
///  A floppy drive's head and motor.
/// </summary>
/// <param name="Motor">Whether the disk is turning.</param>
/// <param name="Selected">Whether the controller has selected the drive.</param>
/// <param name="Track">The track under the head, with a fraction for a drive that steps in quarter tracks.</param>
/// <param name="Side">The side the head reads, 0 or 1.</param>
/// <param name="Sector">The sector the controller is working on, or null when it does not know one.</param>
public readonly record struct DiskHead(bool Motor, bool Selected, double Track, int Side, int? Sector);
