// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Tests;

/// <summary>
///  A mutable struct bus that exposes its internal read counter through a shared log.
/// </summary>
internal struct StatefulBus : IProcessorBus
{
    private readonly List<int> _reads;
    private int _count;

    /// <summary>
    ///  Creates a stateful bus.
    /// </summary>
    /// <param name="reads">The shared read log.</param>
    internal StatefulBus(List<int> reads) => _reads = reads;

    /// <inheritdoc/>
    public byte Read(ushort address)
    {
        _reads.Add(++_count);
        return 0xEA;
    }

    /// <inheritdoc/>
    public void Write(ushort address, byte value) =>
        throw new InvalidOperationException("This test bus only serves NOP instructions.");
}
