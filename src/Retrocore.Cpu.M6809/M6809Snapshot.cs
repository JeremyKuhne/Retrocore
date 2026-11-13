// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Cpu.M6809;

/// <summary>
///  A complete captured MC6809 state, including in-flight accesses.
/// </summary>
public readonly struct M6809Snapshot
{
    /// <summary>
    ///  The complete captured execution state.
    /// </summary>
    internal readonly M6809ExecutionState State;

    /// <summary>
    ///  Whether this snapshot contains captured state.
    /// </summary>
    internal readonly bool IsInitialized;

    /// <summary>
    ///  Wraps a captured execution state.
    /// </summary>
    /// <param name="state">The state to capture.</param>
    internal M6809Snapshot(M6809ExecutionState state)
    {
        State = state;
        IsInitialized = true;
    }

    /// <summary>
    ///  Gets the architectural registers.
    /// </summary>
    public M6809Registers Registers => State.Registers;

    /// <summary>
    ///  Gets elapsed processor cycles.
    /// </summary>
    public ulong CycleCount => State.CycleCount;

    /// <summary>
    ///  Gets asserted input lines.
    /// </summary>
    public M6809Signals Signals => State.Signals;

    /// <summary>
    ///  Gets the current execution status.
    /// </summary>
    public ProcessorExecutionStatus Status => State.Status;
}

