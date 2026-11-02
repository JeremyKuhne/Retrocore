// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Cpu;

/// <summary>
///  Reports why an execution helper returned.
/// </summary>
public enum ProcessorExecutionStatus : byte
{
    /// <summary>
    ///  The processor is executing.
    /// </summary>
    Running,

    /// <summary>
    ///  One instruction completed.
    /// </summary>
    InstructionComplete,

    /// <summary>
    ///  WAI is waiting for an interrupt or reset.
    /// </summary>
    Waiting,

    /// <summary>
    ///  STP stopped execution until reset.
    /// </summary>
    Stopped,

    /// <summary>
    ///  An NMOS JAM instruction stopped execution until reset.
    /// </summary>
    Jammed,

    /// <summary>
    ///  The caller's cycle budget was exhausted.
    /// </summary>
    CycleBudgetExhausted
}
