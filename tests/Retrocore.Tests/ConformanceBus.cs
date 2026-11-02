// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json;

namespace Retrocore.Tests;

/// <summary>
///  Sparse initialized RAM that rejects bus accesses absent from an upstream test's RAM list.
/// </summary>
internal sealed class ConformanceBus : IProcessorBus
{
    private readonly byte[] _memory = new byte[65536];
    private readonly int[] _initialized = new int[65536];
    private int _generation;

    /// <summary>
    ///  Gets the number of actual bus callbacks in this case.
    /// </summary>
    internal int AccessCount { get; private set; }

    /// <summary>
    ///  Initializes a new test's sparse RAM.
    /// </summary>
    /// <param name="ram">The initial address/value pairs.</param>
    internal void Initialize(JsonElement ram)
    {
        _generation++;
        AccessCount = 0;
        foreach (JsonElement pair in ram.EnumerateArray())
        {
            int address = pair[0].GetInt32();
            _memory[address] = pair[1].GetByte();
            _initialized[address] = _generation;
        }
    }

    /// <summary>
    ///  Gets a RAM byte without emulating a bus cycle.
    /// </summary>
    /// <param name="address">The address.</param>
    /// <returns>The RAM value.</returns>
    internal byte Peek(int address) => _memory[address];

    /// <inheritdoc/>
    public byte Read(ushort address)
    {
        CheckAddress(address);
        AccessCount++;
        return _memory[address];
    }

    /// <inheritdoc/>
    public void Write(ushort address, byte value)
    {
        _initialized[address] = _generation;
        AccessCount++;
        _memory[address] = value;
    }

    private void CheckAddress(ushort address)
    {
        if (_initialized[address] != _generation)
        {
            throw new InvalidOperationException($"Bus access to uninitialized test address ${address:X4}.");
        }
    }
}
