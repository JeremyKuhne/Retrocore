// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Perf;

/// <summary>
///  Flat RAM and an idle I/O space for Z80 throughput measurements.
/// </summary>
/// <param name="memory">The 64 KiB backing store.</param>
internal readonly struct Z80RamBus(byte[] memory) : IProcessorBus, IIoBus
{
    /// <summary>
    ///  Gets the memory.
    /// </summary>
    internal byte[] Memory { get; } = memory;

    /// <inheritdoc/>
    public byte Read(ushort address) => Memory[address];

    /// <inheritdoc/>
    public void Write(ushort address, byte value) => Memory[address] = value;

    /// <inheritdoc/>
    public byte In(ushort port) => 0xFF;

    /// <inheritdoc/>
    public void Out(ushort port, byte value)
    {
    }
}
