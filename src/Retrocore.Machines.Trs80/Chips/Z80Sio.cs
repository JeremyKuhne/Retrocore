// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Trs80.Chips;

/// <summary>
///  A Z80 SIO's two serial channels with nothing connected: each transmitter is always empty, nothing is received,
///  and it never interrupts. Its registers are written and read back as the chip's pointer selects them.
/// </summary>
public sealed class Z80Sio : IZ80DaisyDevice
{
    // Read register 0: transmit buffer empty, with DCD and CTS high.
    private const byte TransmitEmpty = 0x2C;

    private readonly int[] _pointer = new int[2];
    private readonly byte[,] _registers = new byte[2, 8];

    /// <summary>
    ///  Gets the bytes each channel transmitted.
    /// </summary>
    public List<byte>[] Transmitted { get; } = [[], []];

    /// <summary>
    ///  Reads a register.
    /// </summary>
    /// <param name="register">0 A data, 1 A control, 2 B data, 3 B control.</param>
    /// <returns>The value.</returns>
    internal byte Read(int register)
    {
        int channel = (register >> 1) & 1;
        if ((register & 1) == 0) { return 0; }
        int pointer = _pointer[channel];
        _pointer[channel] = 0;
        return pointer switch
        {
            0 => TransmitEmpty,
            1 => 0x01,
            2 when channel == 1 => _registers[0, 2],
            _ => 0
        };
    }

    /// <summary>
    ///  Writes a register.
    /// </summary>
    /// <param name="register">0 A data, 1 A control, 2 B data, 3 B control.</param>
    /// <param name="value">The value.</param>
    internal void Write(int register, byte value)
    {
        int channel = (register >> 1) & 1;
        if ((register & 1) == 0)
        {
            Transmitted[channel].Add(value);
            return;
        }

        int pointer = _pointer[channel];
        _registers[channel, pointer] = value;
        _pointer[channel] = pointer == 0 ? value & 0x07 : 0;
    }

    /// <inheritdoc/>
    public byte? PendingVector => null;

    /// <inheritdoc/>
    public bool InService => false;

    /// <inheritdoc/>
    void IZ80DaisyDevice.Acknowledge()
    {
    }

    /// <inheritdoc/>
    void IZ80DaisyDevice.ReturnFromInterrupt()
    {
    }
}
