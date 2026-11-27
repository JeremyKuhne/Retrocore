// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Tests;

/// <summary>
///  A flat 64 KiB memory and an I/O space that record every access in order, for Z80 tests that compare runs;
///  each port reads a value fixed by its number, so the registers that form a port number show in the result.
/// </summary>
internal sealed class Z80RecordingBus : IProcessorBus, IIoBus
{
    /// <summary>
    ///  Gets the memory.
    /// </summary>
    internal byte[] Memory { get; } = new byte[0x10000];

    /// <summary>
    ///  Gets the accesses, memory and I/O, in order.
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

    /// <inheritdoc/>
    public byte In(ushort port)
    {
        byte value = (byte)((port * 0x9E37) >> 7 ^ port);
        Accesses.Add((port, value, BusOperation.IoRead));
        return value;
    }

    /// <inheritdoc/>
    public void Out(ushort port, byte value) => Accesses.Add((port, value, BusOperation.IoWrite));
}
