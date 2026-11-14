// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Chips;

namespace Retrocore.Machines.Altair;

/// <summary>
///  A MITS 88-SIO serial board: one port, a UART with a transmit holding register ahead of its shift register, and
///  status bits that are low when ready. The 88-ACR cassette interface is an 88-SIO with a modem for the tape.
/// </summary>
/// <remarks>
///  <para>
///   The board takes two ports: status and control at the even one, data at the odd one. Status bit 0 is low while a
///   received character waits, bit 7 is low while the transmitter can take a character, and bit 4 is high once a
///   character arrived before the last was read, and was lost; the other bits read 0. Reading the data takes the
///   character and clears bits 0 and 4.
///  </para>
///  <para>
///   Control bit 0 enables the input interrupt, which requests while a received character waits, and bit 1 the output
///   interrupt, which requests while the transmitter can take a character. RESET clears both. Unlike the 88-2SIO's
///   ACIAs, the UART needs no setting up: its format and baud rate are jumpers.
///  </para>
/// </remarks>
public sealed class AltairSio : ISerialLine
{
    /// <summary>
    ///  Status bit 0: low while a received character waits.
    /// </summary>
    public const byte InputNotReady = 0x01;

    /// <summary>
    ///  Status bit 4: a character was lost because the last was not read.
    /// </summary>
    public const byte Overflow = 0x10;

    /// <summary>
    ///  Status bit 7: low while the transmitter can take a character.
    /// </summary>
    public const byte OutputNotReady = 0x80;

    private byte _control;
    private bool _received;
    private bool _overflow;
    private byte _receiveData;
    private bool _holding;
    private byte _holdingData;
    private bool _shifting;
    private byte _shiftData;
    private int _shiftCycles;

    /// <summary>
    ///  Creates a board.
    /// </summary>
    /// <param name="port">The status port; data is the next one.</param>
    /// <param name="cyclesPerCharacter">The CPU cycles one character takes at the board's baud rate.</param>
    internal AltairSio(byte port, int cyclesPerCharacter)
    {
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(cyclesPerCharacter);
        Port = port;
        CyclesPerCharacter = cyclesPerCharacter;
    }

    /// <summary>
    ///  Gets the status port; data is the next one.
    /// </summary>
    public byte Port { get; }

    /// <inheritdoc/>
    public int CyclesPerCharacter { get; }

    /// <inheritdoc/>
    public Action<byte>? Transmitted { get; set; }

    /// <summary>
    ///  Gets the control register: bit 0 the input interrupt, bit 1 the output interrupt.
    /// </summary>
    public byte Control => _control;

    /// <summary>
    ///  Gets the status register as a read would return it.
    /// </summary>
    public byte Status =>
        (byte)((_received ? 0 : InputNotReady) | (_overflow ? Overflow : 0) | (_holding ? OutputNotReady : 0));

    /// <summary>
    ///  Gets whether the board requests an interrupt.
    /// </summary>
    public bool Interrupt => ((_control & 1) != 0 && _received) || ((_control & 2) != 0 && !_holding);

    /// <inheritdoc/>
    public bool CanReceive => !_received;

    /// <summary>
    ///  Gets whether the board answers a port.
    /// </summary>
    /// <param name="port">The port's low byte.</param>
    /// <returns>True for the status and data ports.</returns>
    public bool Answers(byte port) => (byte)(port & 0xFE) == Port;

    /// <summary>
    ///  Reads a register: the status, or the received character, which clears its ready and overflow bits.
    /// </summary>
    /// <param name="register">0 status, 1 data.</param>
    /// <returns>The value.</returns>
    public byte Read(int register)
    {
        if ((register & 1) == 0) { return Status; }
        _received = false;
        _overflow = false;
        return _receiveData;
    }

    /// <summary>
    ///  Reads a register without side effects.
    /// </summary>
    /// <param name="register">0 status, 1 data.</param>
    /// <returns>The value.</returns>
    public byte Peek(int register) => (register & 1) == 0 ? Status : _receiveData;

    /// <summary>
    ///  Writes a register: the control, or a character for the transmitter. A character written while the holding
    ///  register is full replaces the one waiting.
    /// </summary>
    /// <param name="register">0 control, 1 data.</param>
    /// <param name="value">The value.</param>
    public void Write(int register, byte value)
    {
        if ((register & 1) == 0)
        {
            _control = (byte)(value & 3);
            return;
        }

        _holdingData = value;
        _holding = true;
    }

    /// <inheritdoc/>
    /// <remarks>A character that arrives before the last was read is lost, and sets the overflow bit.</remarks>
    public void Receive(byte value)
    {
        if (_received)
        {
            _overflow = true;
            return;
        }

        _receiveData = value;
        _received = true;
    }

    /// <summary>
    ///  Advances one CPU cycle: the shifting character leaves, and a waiting one moves into the idle shift register.
    /// </summary>
    internal void Tick()
    {
        if (_shifting && --_shiftCycles <= 0)
        {
            _shifting = false;
            Transmitted?.Invoke(_shiftData);
        }

        if (!_shifting && _holding)
        {
            _shiftData = _holdingData;
            _shiftCycles = CyclesPerCharacter;
            _shifting = true;
            _holding = false;
        }
    }

    /// <summary>
    ///  RESET: the interrupt enables clear. The UART keeps its registers, and a character shifting out still leaves.
    /// </summary>
    internal void Reset() => _control = 0;
}
