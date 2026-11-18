// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Chips;

/// <summary>
///  What MOS Technology's 6530 and 6532 share: RAM, two 8-bit ports with direction registers, and an interval timer
///  with a prescaler of 1, 8, 64 or 1024 clocks.
/// </summary>
/// <remarks>
///  <para>
///   Writing the timer loads it and starts it counting down at the prescaler's rate; the read value is the count.
///   Past zero it sets its interrupt flag and counts on at every clock, so a program can see how long ago it ran out.
///   Reading or writing the timer clears the flag, and an address bit chosen at the access enables or disables the
///   interrupt.
///  </para>
/// </remarks>
public abstract class RiotBase
{
    /// <summary>
    ///  The interrupt flag register's timer bit.
    /// </summary>
    public const byte TimerFlag = 0x80;

    /// <summary>
    ///  The interrupt flag register's PA7 edge bit, on the 6532.
    /// </summary>
    public const byte EdgeFlag = 0x40;

    private static readonly int[] s_shifts = [0, 3, 6, 10];

    private readonly byte[] _ram;
    private int _remaining;
    private int _shift;
    private bool _counting;
    private bool _timedOutNow;

    /// <summary>
    ///  Creates the chip, reset.
    /// </summary>
    /// <param name="ramSize">The bytes of RAM: 64 on the 6530, 128 on the 6532.</param>
    protected RiotBase(int ramSize)
    {
        _ram = new byte[ramSize];
        _shift = 10;
        _remaining = 256 << 10;
        _counting = true;
        Reset();
    }

    /// <summary>
    ///  Gets the RAM.
    /// </summary>
    public Span<byte> Ram => _ram;

    /// <summary>
    ///  Gets or sets the levels on port A's pins from outside.
    /// </summary>
    public byte PortAInput { get; set; } = 0xFF;

    /// <summary>
    ///  Gets or sets the levels on port B's pins from outside.
    /// </summary>
    public byte PortBInput { get; set; } = 0xFF;

    /// <summary>
    ///  Gets port A's output register.
    /// </summary>
    public byte PortAData { get; private set; }

    /// <summary>
    ///  Gets port A's direction register: a set bit is an output.
    /// </summary>
    public byte PortADirection { get; private set; }

    /// <summary>
    ///  Gets port B's output register.
    /// </summary>
    public byte PortBData { get; private set; }

    /// <summary>
    ///  Gets port B's direction register: a set bit is an output.
    /// </summary>
    public byte PortBDirection { get; private set; }

    /// <summary>
    ///  Gets what port A drives: the output register on output pins, and high on input pins.
    /// </summary>
    public byte PortAOutput => (byte)((PortAData & PortADirection) | ~PortADirection);

    /// <summary>
    ///  Gets what port B drives: the output register on output pins, and high on input pins.
    /// </summary>
    public virtual byte PortBOutput => (byte)((PortBData & PortBDirection) | ~PortBDirection);

    /// <summary>
    ///  Gets whether the timer has run out since it was last read or written.
    /// </summary>
    public bool TimerExpired { get; private set; }

    /// <summary>
    ///  Gets whether the timer's interrupt is enabled.
    /// </summary>
    public bool TimerInterruptEnabled { get; private set; }

    /// <summary>
    ///  Gets whether the chip asserts its interrupt.
    /// </summary>
    public abstract bool InterruptRequested { get; }

    /// <summary>
    ///  Clears the ports' registers and the interrupt enables, as RESET does; RAM and the timer run on.
    /// </summary>
    public virtual void Reset()
    {
        PortAData = 0;
        PortADirection = 0;
        PortBData = 0;
        PortBDirection = 0;
        TimerInterruptEnabled = false;
    }

    /// <summary>
    ///  Advances the timer one clock.
    /// </summary>
    public void Tick()
    {
        _timedOutNow = false;
        if (--_remaining > 0) { return; }

        // Running out sets the flag once; then the count goes on at every clock, 255 down to 0, again and again.
        if (_counting)
        {
            TimerExpired = true;
            _timedOutNow = true;
            _counting = false;
        }

        _remaining = 256;
    }

    /// <summary>
    ///  Reads the timer as the CPU does, which clears its flag and sets whether it interrupts.
    /// </summary>
    /// <param name="interruptEnable">Whether the address enables the timer's interrupt.</param>
    /// <returns>The count.</returns>
    protected byte ReadTimer(bool interruptEnable)
    {
        byte value = PeekTimer();

        // A read in the clock the timer runs out does not clear the flag it sets.
        if (!_timedOutNow)
        {
            TimerExpired = false;
            if (!_counting) { Start(value); }
        }

        TimerInterruptEnabled = interruptEnable;
        return value;
    }

    /// <summary>
    ///  Reads the timer's count without side effects.
    /// </summary>
    /// <returns>The count.</returns>
    protected byte PeekTimer()
    {
        int shift = _counting ? _shift : 0;
        int value = _remaining >> shift;
        return (byte)((_remaining & ((1 << shift) - 1)) != 0 ? value : value - 1);
    }

    /// <summary>
    ///  Loads the timer and starts it, as a write does.
    /// </summary>
    /// <param name="prescaler">The address's low two bits: 1, 8, 64 or 1024 clocks a count.</param>
    /// <param name="value">The count.</param>
    /// <param name="interruptEnable">Whether the address enables the timer's interrupt.</param>
    protected void WriteTimer(int prescaler, byte value, bool interruptEnable)
    {
        _shift = s_shifts[prescaler & 3];
        Start(value);
        TimerExpired = false;
        TimerInterruptEnabled = interruptEnable;
    }

    /// <summary>
    ///  Reads a port or direction register.
    /// </summary>
    /// <param name="register">0 port A, 1 its direction, 2 port B, 3 its direction.</param>
    /// <returns>The value.</returns>
    protected virtual byte ReadPort(int register) => (register & 3) switch
    {
        0 => (byte)((PortAData & PortADirection) | (PortAInput & ~PortADirection)),
        1 => PortADirection,
        2 => (byte)((PortBData & PortBDirection) | (PortBInput & ~PortBDirection)),
        _ => PortBDirection
    };

    /// <summary>
    ///  Writes a port or direction register.
    /// </summary>
    /// <param name="register">0 port A, 1 its direction, 2 port B, 3 its direction.</param>
    /// <param name="value">The value.</param>
    protected virtual void WritePort(int register, byte value)
    {
        switch (register & 3)
        {
            case 0:
                PortAData = value;
                break;
            case 1:
                PortADirection = value;
                break;
            case 2:
                PortBData = value;
                break;
            default:
                PortBDirection = value;
                break;
        }
    }

    // Counts the value down at the prescaler's rate, the first count one clock long.
    private void Start(byte value)
    {
        _counting = true;
        _remaining = (value << _shift) + 1;
    }
}
