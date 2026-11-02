// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information


namespace Retrocore.Cpu.M6502;

/// <summary>
///  An allocation-free CPU snapshot, including mid-instruction state and sampled inputs.
///  The caller must separately preserve bus memory and device state.
/// </summary>
public readonly struct ProcessorSnapshot
{
    /// <summary>
    ///  Complete CPU execution state.
    /// </summary>
    internal readonly ProcessorExecutionState State;

    /// <summary>
    ///  Distinguishes captured snapshots from default values.
    /// </summary>
    internal readonly bool IsInitialized;

    /// <summary>
    ///  Creates a CPU snapshot.
    /// </summary>
    /// <param name="variant">The CPU variant.</param>
    /// <param name="state">The complete CPU execution state.</param>
    internal ProcessorSnapshot(ProcessorVariant variant, ProcessorExecutionState state)
    {
        Variant = variant;
        State = state;
        IsInitialized = true;
    }

    /// <summary>
    ///  Gets the CPU variant that produced the snapshot.
    /// </summary>
    public ProcessorVariant Variant { get; }

    /// <summary>
    ///  Gets the architectural registers.
    /// </summary>
    public ProcessorRegisters Registers => State.Registers;

    /// <summary>
    ///  Gets the number of elapsed CPU cycles.
    /// </summary>
    public ulong CycleCount => State.CycleCount;

    /// <summary>
    ///  Gets the current input assertions.
    /// </summary>
    public ProcessorSignals Signals => State.Signals;

    /// <summary>
    ///  Gets the current execution or halt status.
    /// </summary>
    public ProcessorExecutionStatus Status => State.Status;
}
