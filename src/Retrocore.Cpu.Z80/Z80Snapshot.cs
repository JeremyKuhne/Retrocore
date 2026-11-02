// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Cpu.Z80;

/// <summary>
///  A complete Z80 state, including any machine cycle in progress.
/// </summary>
public readonly struct Z80Snapshot
{
    /// <summary>
    ///  The captured state.
    /// </summary>
    internal readonly Z80ExecutionState State;

    /// <summary>
    ///  Whether the snapshot was captured rather than defaulted.
    /// </summary>
    internal readonly bool IsInitialized;

    /// <summary>
    ///  Wraps a captured state.
    /// </summary>
    /// <param name="state">The state.</param>
    internal Z80Snapshot(Z80ExecutionState state)
    {
        State = state;
        IsInitialized = true;
    }

    /// <summary>
    ///  Gets the registers.
    /// </summary>
    public Z80Registers Registers => State.Registers;

    /// <summary>
    ///  Gets the elapsed T-states.
    /// </summary>
    public ulong CycleCount => State.CycleCount;

    /// <summary>
    ///  Gets the input lines.
    /// </summary>
    public Z80Signals Signals => State.Signals;
}
