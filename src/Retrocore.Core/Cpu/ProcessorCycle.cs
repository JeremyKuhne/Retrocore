// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Cpu;

/// <summary>
///  Describes a completed CPU clock cycle without allocating a trace object.
/// </summary>
public readonly struct ProcessorCycle
{
    /// <summary>
    ///  Gets the one-based cycle number since construction or state restoration.
    /// </summary>
    public ulong Number { get; init; }

    /// <summary>
    ///  Gets the bus operation. Address and value are meaningful only for read or write operations.
    /// </summary>
    public BusOperation Operation { get; init; }

    /// <summary>
    ///  Gets the bus address.
    /// </summary>
    public ushort Address { get; init; }

    /// <summary>
    ///  Gets the value read or written.
    /// </summary>
    public byte Value { get; init; }

    /// <summary>
    ///  Gets whether this read fetched an instruction opcode.
    /// </summary>
    public bool IsOpcodeFetch { get; init; }

    /// <summary>
    ///  Gets whether the bus cycle was held by RDY and did not advance CPU execution.
    /// </summary>
    public bool IsStalled { get; init; }
}
