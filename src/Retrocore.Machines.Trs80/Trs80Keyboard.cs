// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Trs80;

/// <summary>
///  The keyboard: an 8x8 matrix read at <c>$3800</c>-<c>$3BFF</c>, where address bits 0-7 select rows and a
///  read returns the pressed keys of the selected rows ORed together.
/// </summary>
/// <remarks>
///  <para>
///   Typed characters queue as key presses held long enough for BASIC's scan and debounce, then released.
///  </para>
///  <para>
///   Letters are typed as the ROM's keyboard driver reads them (<see cref="Trs80TypedLetters"/>). Level II on the
///   Model I reads a letter alone as uppercase and with shift as lowercase. The Model III's and Model 4's Level II
///   ROM and their DOSes read shift and a letter as uppercase whatever the state of caps lock (shift lock), and the
///   letter alone as lowercase only while caps lock is off, so there an uppercase letter is its key with shift and a
///   lowercase letter its key alone, as MAME types them; with caps lock on, a lowercase letter comes out in
///   uppercase, as no key then gives lowercase. Level I reads shift and a letter as its control code, so there every
///   letter is its key alone.
///  </para>
/// </remarks>
public sealed class Trs80Keyboard
{
    // A typed key is held 40 ms and released for 60 ms before the next. Level II 1.3 rereads a new key after
    // 19 ms to debounce it, then takes about 50 ms before it scans again, so a shorter release hides the
    // release of a doubled letter.
    private readonly int _holdCycles;
    private readonly int _releaseCycles;
    private readonly Trs80TypedLetters _letters;

    private readonly byte[] _rows = new byte[8];
    private readonly Queue<(Trs80Key Key, bool Shift)> _typed = new();
    private (Trs80Key Key, bool Shift)? _current;
    private int _remaining;

    /// <summary>
    ///  Creates the keyboard.
    /// </summary>
    /// <param name="clockHertz">The rate <see cref="Tick"/> is called at: the Model I's Z80 clock by default.</param>
    /// <param name="letters">How a letter's key is pressed: Level II on the Model I's way by default.</param>
    internal Trs80Keyboard(
        int clockHertz = Trs80Timing.ClockHertz,
        Trs80TypedLetters letters = Trs80TypedLetters.ShiftForLowercase)
    {
        _holdCycles = 40 * (clockHertz / 1000);
        _releaseCycles = 60 * (clockHertz / 1000);
        _letters = letters;
    }

    /// <summary>
    ///  Presses or releases a key.
    /// </summary>
    /// <param name="key">The key.</param>
    /// <param name="pressed">Whether it is down.</param>
    public void Set(Trs80Key key, bool pressed)
    {
        int row = (int)key >> 3;
        byte bit = (byte)(1 << ((int)key & 7));
        _rows[row] = pressed ? (byte)(_rows[row] | bit) : (byte)(_rows[row] & ~bit);
    }

    /// <summary>
    ///  Gets whether a key is down.
    /// </summary>
    /// <param name="key">The key.</param>
    /// <returns>Whether it is pressed.</returns>
    public bool IsPressed(Trs80Key key) => (_rows[(int)key >> 3] & (1 << ((int)key & 7))) != 0;

    /// <summary>
    ///  Queues a typed character: ASCII, with 13 Enter, 8 left, 9 right, 10 down, 11 up, 31 Clear and 1 Break. A
    ///  letter's case decides whether shift is pressed, as the keyboard was created to type it.
    /// </summary>
    /// <param name="code">The character.</param>
    /// <returns>Whether the keyboard has a key for it.</returns>
    public bool Type(byte code)
    {
        if (Map(code, _letters) is not { } key) { return false; }
        _typed.Enqueue(key);
        return true;
    }

    /// <summary>
    ///  Gets whether typed characters are still being pressed.
    /// </summary>
    public bool IsTyping => _current is not null || _typed.Count != 0;

    /// <summary>
    ///  Reads the rows the address selects.
    /// </summary>
    /// <param name="address">The address, whose low byte selects rows.</param>
    /// <returns>The pressed keys of those rows.</returns>
    internal byte Read(ushort address)
    {
        int value = 0;
        for (int row = 0; row < _rows.Length; row++)
        {
            if ((address & (1 << row)) != 0) { value |= _rows[row]; }
        }

        return (byte)value;
    }

    /// <summary>
    ///  Advances typing by one T-state.
    /// </summary>
    internal void Tick()
    {
        if (_remaining > 0 && --_remaining > 0) { return; }
        if (_current is { } held)
        {
            Set(held.Key, pressed: false);
            if (held.Shift) { Set(Trs80Key.Shift, pressed: false); }
            _current = null;
            _remaining = _releaseCycles;
            return;
        }

        if (!_typed.TryDequeue(out (Trs80Key Key, bool Shift) next)) { return; }
        _current = next;
        Set(next.Key, pressed: true);
        if (next.Shift) { Set(Trs80Key.Shift, pressed: true); }
        _remaining = _holdCycles;
    }

    // Shifted digits and punctuation follow the Model I keycaps, which the Model III's keep.
    private static (Trs80Key Key, bool Shift)? Map(byte code, Trs80TypedLetters letters) => (char)code switch
    {
        >= 'A' and <= 'Z' => ((Trs80Key)(code - 'A' + (int)Trs80Key.A), letters == Trs80TypedLetters.ShiftForUppercase),
        >= 'a' and <= 'z' => ((Trs80Key)(code - 'a' + (int)Trs80Key.A), letters == Trs80TypedLetters.ShiftForLowercase),
        '@' => (Trs80Key.At, false),
        '`' when letters != Trs80TypedLetters.Unshifted => (Trs80Key.At, true),
        >= '0' and <= '9' => ((Trs80Key)(code - '0' + (int)Trs80Key.D0), false),
        >= '!' and <= ')' and not '"' => ((Trs80Key)(code - '!' + (int)Trs80Key.D1), true),
        '"' => (Trs80Key.D2, true),
        ':' => (Trs80Key.Colon, false),
        '*' => (Trs80Key.Colon, true),
        ';' => (Trs80Key.Semicolon, false),
        '+' => (Trs80Key.Semicolon, true),
        ',' => (Trs80Key.Comma, false),
        '<' => (Trs80Key.Comma, true),
        '-' => (Trs80Key.Minus, false),
        '=' => (Trs80Key.Minus, true),
        '.' => (Trs80Key.Period, false),
        '>' => (Trs80Key.Period, true),
        '/' => (Trs80Key.Slash, false),
        '?' => (Trs80Key.Slash, true),
        '\r' => (Trs80Key.Enter, false),
        ' ' => (Trs80Key.Space, false),
        '\b' => (Trs80Key.Left, false),
        '\t' => (Trs80Key.Right, false),
        '\n' => (Trs80Key.Down, false),
        '\v' => (Trs80Key.Up, false),
        '\u001F' => (Trs80Key.Clear, false),
        '\u0001' => (Trs80Key.Break, false),
        _ => null
    };
}
