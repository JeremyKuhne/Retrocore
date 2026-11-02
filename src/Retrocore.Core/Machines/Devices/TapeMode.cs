// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Devices;

/// <summary>
///  A tape drive's transport.
/// </summary>
public enum TapeMode : byte
{
    /// <summary>
    ///  No tape, or a tape that is not playing or recording.
    /// </summary>
    Stopped,

    /// <summary>
    ///  The tape plays into the machine when its motor runs.
    /// </summary>
    Playing,

    /// <summary>
    ///  The machine records onto the tape when its motor runs.
    /// </summary>
    Recording
}
