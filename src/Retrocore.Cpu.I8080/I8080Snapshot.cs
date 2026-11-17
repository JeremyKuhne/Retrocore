// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Cpu.I8080;

/// <summary>
///  A complete 8080 or 8085 state, including any machine cycle in progress.
/// </summary>
public readonly struct I8080Snapshot
{
    /// <summary>
    ///  The captured state.
    /// </summary>
    internal readonly I8080ExecutionState State;

    /// <summary>
    ///  Whether the snapshot was captured rather than defaulted.
    /// </summary>
    internal readonly bool IsInitialized;

    /// <summary>
    ///  Wraps a captured state.
    /// </summary>
    /// <param name="state">The state.</param>
    internal I8080Snapshot(I8080ExecutionState state)
    {
        State = state;
        IsInitialized = true;
    }

    /// <summary>
    ///  Gets the registers.
    /// </summary>
    public I8080Registers Registers => State.Registers;

    /// <summary>
    ///  Gets the elapsed states.
    /// </summary>
    public ulong CycleCount => State.CycleCount;

    /// <summary>
    ///  Gets the input lines.
    /// </summary>
    public I8080Signals Signals => State.Signals;
}
