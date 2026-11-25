// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Atari;

/// <summary>
///  How the machine's disk drives are emulated.
/// </summary>
public enum AtariDiskDriveKind
{
    /// <summary>
    ///  The 810 at the hardware level (<see cref="Atari810"/>), running its firmware: the default.
    /// </summary>
    Atari810,

    /// <summary>
    ///  A drive that answers the 810's commands from the image (<see cref="AtariSioDiskDrive"/>), which needs no
    ///  firmware, is faster, and reads double-density disks too.
    /// </summary>
    CommandLevel
}
