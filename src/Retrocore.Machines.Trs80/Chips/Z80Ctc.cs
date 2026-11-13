// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Trs80.Chips;

/// <summary>
///  A Z80 CTC: four counter/timer channels, each counting the system clock through a 16 or 256 prescaler (timer
///  mode) or edges on its trigger input (counter mode), down from a time constant, and interrupting at zero.
/// </summary>
/// <remarks>
///  <para>
///   A control word has bit 0 set: bit 7 enables the interrupt, bit 6 selects counter mode, bit 5 the 256
///   prescaler, bit 4 the rising edge, bit 3 waits for a trigger to start the timer, bit 2 says the time constant
///   follows and bit 1 resets the channel. A word with bit 0 clear, written to channel 0, is the vector base; each
///   channel's vector adds twice its number. Channel 0 has the highest priority.
///  </para>
/// </remarks>
public sealed class Z80Ctc : IZ80DaisyDevice
{
    private const byte InterruptEnable = 0x80;
    private const byte CounterMode = 0x40;
    private const byte Prescale256 = 0x20;
    private const byte RisingEdge = 0x10;
    private const byte TriggerStart = 0x08;
    private const byte ConstantFollows = 0x04;
    private const byte ResetChannel = 0x02;

    private readonly Z80CtcChannel[] _channels = [new(), new(), new(), new()];
    private byte _vector;

    /// <summary>
    ///  Gets a channel's down counter.
    /// </summary>
    /// <param name="channel">The channel, 0-3.</param>
    /// <returns>The count.</returns>
    public int Count(int channel) => _channels[channel].Counter;

    /// <summary>
    ///  Gets a channel's last control word.
    /// </summary>
    /// <param name="channel">The channel, 0-3.</param>
    /// <returns>The control word.</returns>
    public byte Control(int channel) => _channels[channel].Control;

    /// <summary>
    ///  Reads a channel's down counter.
    /// </summary>
    /// <param name="channel">The channel, 0-3.</param>
    /// <returns>Its low byte.</returns>
    internal byte Read(int channel) => (byte)_channels[channel & 3].Counter;

    /// <summary>
    ///  Writes a channel: a time constant it awaits, a control word, or channel 0's vector base.
    /// </summary>
    /// <param name="channel">The channel, 0-3.</param>
    /// <param name="value">The value.</param>
    internal void Write(int channel, byte value)
    {
        Z80CtcChannel c = _channels[channel & 3];
        if (c.AwaitingConstant)
        {
            c.Constant = value == 0 ? 256 : value;
            c.AwaitingConstant = false;
            if (!c.Running)
            {
                c.Counter = c.Constant;
                c.Prescaler = Prescaler(c);

                // A timer waiting for a trigger starts on its edge; otherwise loading the constant starts it.
                c.Running = (c.Control & CounterMode) != 0 || (c.Control & TriggerStart) == 0;
            }

            return;
        }

        if ((value & 1) == 0)
        {
            if ((channel & 3) == 0) { _vector = (byte)(value & 0xF8); }
            return;
        }

        c.Control = value;
        if ((value & InterruptEnable) == 0) { c.Pending = false; }
        if ((value & ResetChannel) != 0) { c.Running = false; }
        c.AwaitingConstant = (value & ConstantFollows) != 0;
    }

    /// <summary>
    ///  Advances the timers one system clock.
    /// </summary>
    internal void Tick()
    {
        foreach (Z80CtcChannel c in _channels)
        {
            if (!c.Running || (c.Control & CounterMode) != 0) { continue; }
            if (--c.Prescaler > 0) { continue; }
            c.Prescaler = Prescaler(c);
            Decrement(c);
        }
    }

    /// <summary>
    ///  Drives a channel's CLK/TRG input: an edge of the selected polarity counts in counter mode, and starts a
    ///  timer waiting for its trigger.
    /// </summary>
    /// <param name="channel">The channel, 0-3.</param>
    /// <param name="level">The input's level.</param>
    internal void Trigger(int channel, bool level)
    {
        Z80CtcChannel c = _channels[channel];
        bool edge = level != c.Input && level == ((c.Control & RisingEdge) != 0);
        c.Input = level;
        if (!edge || c.AwaitingConstant) { return; }
        if ((c.Control & CounterMode) != 0)
        {
            if (c.Running) { Decrement(c); }
        }
        else if (!c.Running && (c.Control & TriggerStart) != 0 && c.Constant > 0)
        {
            c.Running = true;
        }
    }

    /// <inheritdoc/>
    public byte? PendingVector
    {
        get
        {
            for (int channel = 0; channel < _channels.Length; channel++)
            {
                if (_channels[channel].InService) { return null; }
                if (_channels[channel].Pending) { return (byte)(_vector | (channel << 1)); }
            }

            return null;
        }
    }

    /// <inheritdoc/>
    public bool InService => _channels.Any(c => c.InService);

    /// <inheritdoc/>
    void IZ80DaisyDevice.Acknowledge()
    {
        foreach (Z80CtcChannel c in _channels)
        {
            if (c.Pending)
            {
                c.Pending = false;
                c.InService = true;
                return;
            }
        }
    }

    /// <inheritdoc/>
    void IZ80DaisyDevice.ReturnFromInterrupt()
    {
        foreach (Z80CtcChannel c in _channels)
        {
            if (c.InService)
            {
                c.InService = false;
                return;
            }
        }
    }

    private static int Prescaler(Z80CtcChannel c) => (c.Control & Prescale256) != 0 ? 256 : 16;

    private static void Decrement(Z80CtcChannel c)
    {
        if (--c.Counter > 0) { return; }
        c.Counter = c.Constant;
        if ((c.Control & InterruptEnable) != 0) { c.Pending = true; }
    }
}
