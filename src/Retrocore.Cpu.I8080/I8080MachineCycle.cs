// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Cpu.I8080;

/// <summary>
///  The kinds of machine cycle the core runs. A bus cycle puts its address out on T1, samples READY on T2 (a wait
///  state repeats T2) and transfers its byte on T3.
/// </summary>
internal enum I8080MachineCycle : byte
{
    /// <summary>
    ///  No machine cycle is in progress.
    /// </summary>
    None,

    /// <summary>
    ///  M1, 4 states: the opcode read on T3 increments PC; T4 decodes. An instruction that needs the 8080's 5-state
    ///  or the 8085's 6-state M1 follows it with idle states.
    /// </summary>
    Fetch,

    /// <summary>
    ///  The interrupt acknowledge M1: as <see cref="Fetch"/>, but the device puts the opcode on the bus and PC stays.
    /// </summary>
    Acknowledge,

    /// <summary>
    ///  A memory read, 3 states.
    /// </summary>
    Read,

    /// <summary>
    ///  A memory write, 3 states.
    /// </summary>
    Write,

    /// <summary>
    ///  An I/O read, 3 states.
    /// </summary>
    InputRead,

    /// <summary>
    ///  An I/O write, 3 states.
    /// </summary>
    OutputWrite,

    /// <summary>
    ///  States with no bus access, including the halt state.
    /// </summary>
    Internal
}
