// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Apple2;

/// <summary>
///  Explicit sequencer PROM wiring; do not guess layout from a firmware byte.
/// </summary>
public enum P6PromLayout : byte
{
    /// <summary>
    ///  Raw P6 chip dump with physical address/data pin ordering.
    /// </summary>
    Raw,

    /// <summary>
    ///  Published Beneath Apple ProDOS table ordering.
    /// </summary>
    BeneathProDos,

    /// <summary>
    ///  A P6 dump read from the boot ROM's socket, which exchanges address lines A5 and A7 and reverses data lines
    ///  D7-D4, as the known dump of the 13-sector 341-0010 is.
    /// </summary>
    BootSocket
}
