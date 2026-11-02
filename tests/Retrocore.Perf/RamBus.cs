// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Perf;

/// <summary>
///  Caller-owned flat RAM for functional tests, AOT smoke tests, and untraced throughput measurements.
/// </summary>
internal readonly struct RamBus : IProcessorBus
{
    /// <summary>
    ///  Creates a bus over a complete 16-bit address space.
    /// </summary>
    /// <param name="memory">The RAM backing store.</param>
    internal RamBus(byte[] memory)
    {
        ArgumentNullException.ThrowIfNull(memory);
        if (memory.Length != 65536)
        {
            throw new ArgumentException("Exactly 64 KiB of RAM is required.", nameof(memory));
        }

        Memory = memory;
    }

    /// <summary>
    ///  Gets the caller-owned memory.
    /// </summary>
    internal byte[] Memory { get; }

    /// <inheritdoc/>
    public byte Read(ushort address) => Memory[address];

    /// <inheritdoc/>
    public void Write(ushort address, byte value) => Memory[address] = value;
}
