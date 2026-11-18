// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Chips;

/// <summary>
///  A Z80 SIO's two serial channels: each transmitter is always empty, a received character waits in the channel's
///  buffer until it is read, and it never interrupts. Its registers are written and read back as the chip's pointer
///  selects them.
/// </summary>
public sealed class Z80Sio : IZ80DaisyDevice
{
    // Read register 0: transmit buffer empty, with DCD and CTS high.
    private const byte TransmitEmpty = 0x2C;

    // Read register 0: a received character is waiting.
    private const byte ReceivedCharacter = 0x01;

    private readonly int[] _pointer = new int[2];
    private readonly byte[,] _registers = new byte[2, 8];
    private readonly byte[] _received = new byte[2];
    private readonly bool[] _receiveFull = new bool[2];

    /// <summary>
    ///  Gets the bytes each channel transmitted.
    /// </summary>
    public List<byte>[] Transmitted { get; } = [[], []];

    /// <summary>
    ///  Gets or sets what takes each character a channel transmits, in place of <see cref="Transmitted"/>: the
    ///  channel, 0 for A or 1 for B, and the character.
    /// </summary>
    public Action<int, byte>? Transmit { get; set; }

    /// <summary>
    ///  Gets whether a channel's received character is still waiting to be read.
    /// </summary>
    /// <param name="channel">0 for A, 1 for B.</param>
    /// <returns>Whether it is.</returns>
    public bool ReceiveFull(int channel) => _receiveFull[channel];

    /// <summary>
    ///  Receives a character on a channel, replacing one that was not read.
    /// </summary>
    /// <param name="channel">0 for A, 1 for B.</param>
    /// <param name="value">The character.</param>
    public void Receive(int channel, byte value)
    {
        _received[channel] = value;
        _receiveFull[channel] = true;
    }

    /// <summary>
    ///  Reads a register.
    /// </summary>
    /// <param name="register">0 A data, 1 A control, 2 B data, 3 B control.</param>
    /// <returns>The value.</returns>
    internal byte Read(int register)
    {
        int channel = (register >> 1) & 1;
        if ((register & 1) == 0)
        {
            _receiveFull[channel] = false;
            return _received[channel];
        }

        int pointer = _pointer[channel];
        _pointer[channel] = 0;
        return pointer switch
        {
            0 => (byte)(TransmitEmpty | (_receiveFull[channel] ? ReceivedCharacter : 0)),
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
            if (Transmit is { } transmit) { transmit(channel, value); }
            else { Transmitted[channel].Add(value); }
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
