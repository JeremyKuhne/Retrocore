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
/// </remarks>
public sealed class Trs80Keyboard
{
    // A typed key is held 40 ms and released for 60 ms before the next. Level II 1.3 rereads a new key after
    // 19 ms to debounce it, then takes about 50 ms before it scans again, so a shorter release hides the
    // release of a doubled letter.
    private const int HoldCycles = 40 * Trs80Timing.CyclesPerMillisecond;
    private const int ReleaseCycles = 60 * Trs80Timing.CyclesPerMillisecond;

    private readonly byte[] _rows = new byte[8];
    private readonly Queue<(Trs80Key Key, bool Shift)> _typed = new();
    private (Trs80Key Key, bool Shift)? _current;
    private int _remaining;

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
    ///  Queues a typed character: ASCII, with 13 Enter, 8 left, 9 right, 10 down, 11 up, 31 Clear and 1 Break.
    /// </summary>
    /// <param name="code">The character.</param>
    /// <returns>Whether the keyboard has a key for it.</returns>
    public bool Type(byte code)
    {
        if (Map(code) is not { } key) { return false; }
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
            _remaining = ReleaseCycles;
            return;
        }

        if (!_typed.TryDequeue(out (Trs80Key Key, bool Shift) next)) { return; }
        _current = next;
        Set(next.Key, pressed: true);
        if (next.Shift) { Set(Trs80Key.Shift, pressed: true); }
        _remaining = HoldCycles;
    }

    // Shifted digits and punctuation follow the Model I keycaps.
    private static (Trs80Key Key, bool Shift)? Map(byte code) => (char)code switch
    {
        >= 'A' and <= 'Z' => ((Trs80Key)(code - 'A' + (int)Trs80Key.A), false),
        >= 'a' and <= 'z' => ((Trs80Key)(code - 'a' + (int)Trs80Key.A), true),
        '@' => (Trs80Key.At, false),
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
