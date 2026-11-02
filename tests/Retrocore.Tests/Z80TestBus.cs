// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Tests;

/// <summary>
///  A flat 64 KiB memory and an I/O space that replays scripted input and records output, for Z80 tests.
/// </summary>
internal sealed class Z80TestBus : IProcessorBus, IIoBus
{
    /// <summary>
    ///  Gets the memory.
    /// </summary>
    internal byte[] Memory { get; } = new byte[0x10000];

    /// <summary>
    ///  Gets the bytes inputs return, in order; an empty queue reads <c>$FF</c>.
    /// </summary>
    internal Queue<byte> Inputs { get; } = new();

    /// <summary>
    ///  Gets the input ports read, in order.
    /// </summary>
    internal List<ushort> InputPorts { get; } = [];

    /// <summary>
    ///  Gets the outputs written, in order.
    /// </summary>
    internal List<(ushort Port, byte Value)> Outputs { get; } = [];

    /// <summary>
    ///  Gets or sets what handles an output instead of recording it, such as a CP/M console.
    /// </summary>
    internal Action<ushort, byte>? OutputHandler { get; set; }

    /// <inheritdoc/>
    public byte Read(ushort address) => Memory[address];

    /// <inheritdoc/>
    public void Write(ushort address, byte value) => Memory[address] = value;

    /// <inheritdoc/>
    public byte In(ushort port)
    {
        InputPorts.Add(port);
        return InputHandler is { } handler ? handler(port) : Inputs.TryDequeue(out byte value) ? value : (byte)0xFF;
    }

    /// <summary>
    ///  Gets or sets what supplies input instead of <see cref="Inputs"/>.
    /// </summary>
    internal Func<ushort, byte>? InputHandler { get; set; }

    /// <inheritdoc/>
    public void Out(ushort port, byte value)
    {
        if (OutputHandler is { } handler)
        {
            handler(port, value);
            return;
        }

        Outputs.Add((port, value));
    }

    /// <summary>
    ///  Clears the I/O records.
    /// </summary>
    internal void ClearIo()
    {
        Inputs.Clear();
        InputPorts.Clear();
        Outputs.Clear();
    }
}
