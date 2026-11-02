// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Cpu;

/// <summary>
///  The outcome of bounded CPU execution.
/// </summary>
public readonly struct ProcessorExecutionResult
{
    /// <summary>
    ///  Gets the reason execution returned.
    /// </summary>
    public ProcessorExecutionStatus Status { get; init; }

    /// <summary>
    ///  Gets the number of cycles executed by this call.
    /// </summary>
    public ulong Cycles { get; init; }
}
