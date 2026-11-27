// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Commodore.Serial;

/// <summary>
///  The Commodore serial bus's signal lines.
/// </summary>
[Flags]
public enum SerialLines : byte
{
    /// <summary>
    ///  No line.
    /// </summary>
    None = 0,

    /// <summary>
    ///  ATN, attention: the computer pulls it to send commands, which every device must answer.
    /// </summary>
    Atn = 0x01,

    /// <summary>
    ///  CLK, the clock: the talker's line.
    /// </summary>
    Clock = 0x02,

    /// <summary>
    ///  DATA: the bits, and the listener's handshake.
    /// </summary>
    Data = 0x04,

    /// <summary>
    ///  SRQ, service request, which the VIC-20 and the 64 read but do not use; the 128's fast bus clocks bytes on it.
    /// </summary>
    Srq = 0x08
}
