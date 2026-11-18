// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Acorn;

/// <summary>
///  The analogue port: the NEC uPD7002 analogue to digital converter, with four channels for two joysticks, and the
///  joysticks' fire buttons on the system VIA.
/// </summary>
/// <remarks>
///  <para>
///   Writing register 0 (<c>$FEC0</c>) starts a conversion: bits 0-1 choose the channel, bit 2 is a flag and bit 3
///   asks for 10 bits (10 ms) rather than 8 (4 ms). Reading register 0 gives the status: the channel, the flag and the
///   mode, the result's top two bits in bits 5 and 4, bit 6 clear while busy and bit 7 clear once the conversion is
///   done. Registers 1 and 2 hold the result, left-justified: its top 8 bits, then the low bits in bits 4-7.
///  </para>
///  <para>
///   The chip's end of conversion output is the system VIA's CB1: high while converting, low when done. Channels 1
///   and 2 (0 and 1 here) are the first joystick's left-right and up-down, low for right and down.
///  </para>
/// </remarks>
public sealed class BbcAnalogue
{
    private readonly ushort[] _inputs = [0x8000, 0x8000, 0x8000, 0x8000];
    private byte _control;
    private ushort _result;
    private int _cyclesLeft;
    private bool _busy;

    /// <summary>
    ///  Gets whether the end of conversion output is high: a conversion is under way, or none has finished.
    /// </summary>
    public bool EndOfConversion { get; private set; } = true;

    /// <summary>
    ///  Gets or sets the fire buttons down, bit 0 the first joystick's and bit 1 the second's.
    /// </summary>
    public int Buttons { get; set; }

    /// <summary>
    ///  Gets or sets a channel's input, from 0 (0 V) to 65,535 (Vref); a centred joystick is half way.
    /// </summary>
    /// <param name="channel">The channel, 0-3.</param>
    public ushort this[int channel]
    {
        get => _inputs[channel];
        set => _inputs[channel] = value;
    }

    /// <summary>
    ///  Reads a register.
    /// </summary>
    /// <param name="register">The register, 0-3.</param>
    /// <returns>The value; register 3 reads as 0.</returns>
    public byte Read(int register) => (register & 3) switch
    {
        0 => (byte)((_control & 0x0F) | ((_result >> 10) & 0x30) | (_busy ? 0 : 0x40) | (EndOfConversion ? 0x80 : 0)),
        1 => (byte)(_result >> 8),
        2 => (byte)(_result & 0xF0),
        _ => 0
    };

    /// <summary>
    ///  Writes a register: register 0 starts a conversion; the others do nothing.
    /// </summary>
    /// <param name="register">The register, 0-3.</param>
    /// <param name="value">The value.</param>
    public void Write(int register, byte value)
    {
        if ((register & 3) != 0) { return; }
        _control = value;
        _busy = true;
        EndOfConversion = true;
        _cyclesLeft = (value & 8) != 0 ? 10_000 : 4_000;
    }

    /// <summary>
    ///  Resets the converter, as power-on does.
    /// </summary>
    public void Reset()
    {
        _control = 0;
        _result = 0;
        _busy = false;
        _cyclesLeft = 0;
        EndOfConversion = true;
    }

    /// <summary>
    ///  Advances one 1 MHz cycle.
    /// </summary>
    internal void Tick()
    {
        if (!_busy || --_cyclesLeft > 0) { return; }
        _busy = false;
        ushort value = _inputs[_control & 3];
        _result = (ushort)((_control & 8) != 0 ? value & 0xFFC0 : value & 0xFF00);
        EndOfConversion = false;
    }
}
