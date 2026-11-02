// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Devices;

/// <summary>
///  What a host can do to a device's media.
/// </summary>
[Flags]
public enum MediaOperations : byte
{
    /// <summary>
    ///  The media is fixed, as when it is given at power-up.
    /// </summary>
    None = 0,

    /// <summary>
    ///  Media can be inserted.
    /// </summary>
    Insert = 1,

    /// <summary>
    ///  Media can be ejected.
    /// </summary>
    Eject = 2,

    /// <summary>
    ///  Blank media can be inserted to record onto, as a tape.
    /// </summary>
    Record = 4,

    /// <summary>
    ///  The media's write protection can be changed, as by covering a disk's notch.
    /// </summary>
    WriteProtect = 8
}
