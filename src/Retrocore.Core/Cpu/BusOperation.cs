// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Cpu;

/// <summary>
///  The operation performed during a CPU clock cycle.
/// </summary>
public enum BusOperation : byte
{
    /// <summary>
    ///  The CPU did not access the bus.
    /// </summary>
    None,

    /// <summary>
    ///  The CPU read the bus.
    /// </summary>
    Read,

    /// <summary>
    ///  The CPU wrote the bus.
    /// </summary>
    Write,

    /// <summary>
    ///  The CPU read an I/O port, on a CPU with a separate I/O space.
    /// </summary>
    IoRead,

    /// <summary>
    ///  The CPU wrote an I/O port, on a CPU with a separate I/O space.
    /// </summary>
    IoWrite,

    /// <summary>
    ///  The CPU drove a memory refresh address, as the Z80 does after each opcode fetch.
    /// </summary>
    Refresh,

    /// <summary>
    ///  The CPU acknowledged an interrupt and read the interrupting device's data.
    /// </summary>
    InterruptAcknowledge
}
