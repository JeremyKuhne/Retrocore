// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Cpu.Z80;

/// <summary>
///  The kinds of machine cycle the Z80 runs, each a fixed sequence of T-states.
/// </summary>
internal enum Z80MachineCycle : byte
{
    /// <summary>
    ///  No machine cycle is in progress.
    /// </summary>
    None,

    /// <summary>
    ///  M1, 4 T-states: the opcode read on T2 increments PC, then T3 and T4 refresh memory at I:R.
    /// </summary>
    Fetch,

    /// <summary>
    ///  M1 while halted: as <see cref="Fetch"/>, but PC stays and the byte is ignored.
    /// </summary>
    HaltFetch,

    /// <summary>
    ///  The 5 T-state M1 that starts a non-maskable interrupt; the byte is ignored and PC stays.
    /// </summary>
    NonMaskableFetch,

    /// <summary>
    ///  The 6 T-state interrupt acknowledge M1, with two automatic wait states, then refresh.
    /// </summary>
    Acknowledge,

    /// <summary>
    ///  A memory read, 3 T-states, read on T2.
    /// </summary>
    Read,

    /// <summary>
    ///  A memory write, 3 T-states, written on T2.
    /// </summary>
    Write,

    /// <summary>
    ///  An I/O read, 4 T-states with the automatic wait state, read on T3.
    /// </summary>
    InputRead,

    /// <summary>
    ///  An I/O write, 4 T-states with the automatic wait state, written on T3.
    /// </summary>
    OutputWrite,

    /// <summary>
    ///  T-states with no bus access; the address bus holds its last value.
    /// </summary>
    Internal
}
