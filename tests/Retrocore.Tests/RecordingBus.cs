// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Tests;

/// <summary>
///  Flat RAM with an ordered log of actual bus accesses.
/// </summary>
internal sealed class RecordingBus : IProcessorBus
{
    /// <summary>
    ///  Gets the complete 16-bit address space.
    /// </summary>
    public byte[] Memory { get; } = new byte[65536];

    /// <summary>
    ///  Gets the accesses performed by the CPU.
    /// </summary>
    public List<(ushort Address, byte Value, BusOperation Operation)> Accesses { get; } = [];

    /// <summary>
    ///  Gets or sets a device callback invoked during each read.
    /// </summary>
    public Action<ushort>? ReadCallback { get; set; }

    /// <inheritdoc/>
    public byte Read(ushort address)
    {
        byte value = Memory[address];
        ReadCallback?.Invoke(address);
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
