// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Tests;

/// <summary>
///  A flat 64 KiB memory that records every access in order, for MC6809 tests that compare runs.
/// </summary>
internal sealed class M6809RecordingBus : IProcessorBus
{
    /// <summary>
    ///  Gets the memory.
    /// </summary>
    internal byte[] Memory { get; } = new byte[0x10000];

    /// <summary>
    ///  Gets the accesses in order.
    /// </summary>
    internal List<(ushort Address, byte Value, BusOperation Operation)> Accesses { get; } = [];

    /// <inheritdoc/>
    public byte Read(ushort address)
    {
        byte value = Memory[address];
        Accesses.Add((address, value, BusOperation.Read));
        return value;
    }

    /// <inheritdoc/>
    public void Write(ushort address, byte value)
    {
        Memory[address] = value;
        Accesses.Add((address, value, BusOperation.Write));
    }
}
