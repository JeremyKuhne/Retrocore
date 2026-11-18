// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Commodore;

/// <summary>
///  The IEEE-488 bus's control lines.
/// </summary>
[Flags]
public enum Ieee488Lines : byte
{
    /// <summary>
    ///  No line.
    /// </summary>
    None = 0,

    /// <summary>
    ///  EOI, end or identify: the byte being sent is the last.
    /// </summary>
    Eoi = 0x01,

    /// <summary>
    ///  DAV, data valid: the talker's byte is on the data lines.
    /// </summary>
    Dav = 0x02,

    /// <summary>
    ///  NRFD, not ready for data: a listener is not ready.
    /// </summary>
    Nrfd = 0x04,

    /// <summary>
    ///  NDAC, not data accepted: a listener has not taken the byte.
    /// </summary>
    Ndac = 0x08,

    /// <summary>
    ///  IFC, interface clear: the controller resets the devices.
    /// </summary>
    Ifc = 0x10,

    /// <summary>
    ///  SRQ, service request: a device asks for attention.
    /// </summary>
    Srq = 0x20,

    /// <summary>
    ///  ATN, attention: the controller sends a command.
    /// </summary>
    Atn = 0x40,

    /// <summary>
    ///  REN, remote enable.
    /// </summary>
    Ren = 0x80
}
