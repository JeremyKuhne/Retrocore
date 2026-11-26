// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Trs80Model100;

/// <summary>
///  The Model 100's keyboard: a matrix of nine columns of eight rows, and the keys typed into it.
/// </summary>
/// <remarks>
///  <para>
///   The ROM's RST 7.5 handler scans the keyboard every third interrupt, about every 11.7 ms (its counter at
///   <c>$FF8F</c>), takes a key seen on two scans in a row, and forgets the last key once no key has been down for two
///   scans (<c>$FF90</c>). A typed key is held 50 ms and released for 50 ms before the next, so each is seen at least
///   four times either way, and a doubled letter reads as two. Held keys do not repeat in BASIC. MAME's
///   <c>trsm100</c> needs keys held longer, about 100 ms, as its driver's notes say its keyboard is slow.
///  </para>
/// </remarks>
public sealed class Trs80Model100Keyboard
{
    private const int Columns = 9;

    private readonly byte[] _columns = new byte[Columns];
    private readonly Queue<(Trs80Model100Key Key, Trs80Model100Key? Modifier)> _typed = new();
    private readonly int _holdCycles;
    private readonly int _releaseCycles;
    private (Trs80Model100Key Key, Trs80Model100Key? Modifier)? _current;
    private int _remaining;

    /// <summary>
    ///  Builds a keyboard with no keys down.
    /// </summary>
    /// <param name="clockHertz">The CPU clock, which times typed keys.</param>
    internal Trs80Model100Keyboard(int clockHertz = Trs80Model100Timing.ClockHertz)
    {
        _holdCycles = 50 * (clockHertz / 1000);
        _releaseCycles = 50 * (clockHertz / 1000);
    }

    /// <summary>
    ///  Gets whether keys typed with <see cref="Type"/> are still being pressed.
    /// </summary>
    public bool IsTyping => _current is not null || _typed.Count != 0;

    /// <summary>
    ///  Presses or releases a key.
    /// </summary>
    /// <param name="key">The key.</param>
    /// <param name="pressed">Whether it is down.</param>
    public void Set(Trs80Model100Key key, bool pressed)
    {
        int column = (int)key >> 3;
        byte bit = (byte)(1 << ((int)key & 7));
        _columns[column] = pressed ? (byte)(_columns[column] | bit) : (byte)(_columns[column] & ~bit);
    }

    /// <summary>
    ///  Gets whether a key is down.
    /// </summary>
    /// <param name="key">The key.</param>
    /// <returns>Whether it is pressed.</returns>
    public bool IsPressed(Trs80Model100Key key) => (_columns[(int)key >> 3] & (1 << ((int)key & 7))) != 0;

    /// <summary>
    ///  Types a character: presses its key, with SHIFT or CTRL if it needs one, holds it, and lets it go.
    /// </summary>
    /// <param name="code">
    ///  The ASCII code: letters, digits and punctuation as the keycaps have them, carriage return for ENTER, backspace
    ///  for DEL, tab, escape, space, and the other control codes from 1 to 26 as CTRL and a letter; and for the Model
    ///  100's own keys, 28 to 31 for the arrows, right, left, up and down (the codes the ROM gives them), 128 to 135
    ///  for F1 to F8, 136 LABEL, 137 PRINT, 138 PASTE, 139 PAUSE (the PAUSE/BREAK key) and 140 BREAK (it with SHIFT).
    /// </param>
    /// <returns>Whether the keyboard can type it.</returns>
    public bool Type(byte code)
    {
        if (Map(code) is not { } key) { return false; }
        _typed.Enqueue(key);
        return true;
    }

    /// <summary>
    ///  Reads the rows, as port $E0 does: a bit is low when a key in its row is down in a column strobed low.
    /// </summary>
    /// <param name="strobe">The columns' strobes: port A in bits 0-7 and port B bit 0 in bit 8.</param>
    /// <returns>The rows.</returns>
    internal byte Read(int strobe)
    {
        int rows = 0;
        for (int column = 0; column < Columns; column++)
        {
            if ((strobe & (1 << column)) == 0) { rows |= _columns[column]; }
        }

        return (byte)~rows;
    }

    /// <summary>
    ///  Advances typing one CPU cycle.
    /// </summary>
    internal void Tick()
    {
        if (_remaining > 0 && --_remaining > 0) { return; }
        if (_current is { } held)
        {
            Set(held.Key, pressed: false);
            if (held.Modifier is { } modifier) { Set(modifier, pressed: false); }
            _current = null;
            _remaining = _releaseCycles;
            return;
        }

        if (!_typed.TryDequeue(out (Trs80Model100Key Key, Trs80Model100Key? Modifier) next)) { return; }
        _current = next;
        Set(next.Key, pressed: true);
        if (next.Modifier is { } pressedModifier) { Set(pressedModifier, pressed: true); }
        _remaining = _holdCycles;
    }

    private static (Trs80Model100Key Key, Trs80Model100Key? Modifier)? Map(byte code)
    {
        const Trs80Model100Key Shift = Trs80Model100Key.Shift;
        return (char)code switch
        {
            >= 'a' and <= 'z' => (Letter(code - 'a'), null),
            >= 'A' and <= 'Z' => (Letter(code - 'A'), Shift),
            >= '1' and <= '8' => ((Trs80Model100Key)(code - '1' + (int)Trs80Model100Key.D1), null),
            '9' => (Trs80Model100Key.D9, null),
            '0' => (Trs80Model100Key.D0, null),
            '!' => (Trs80Model100Key.D1, Shift),
            '@' => (Trs80Model100Key.D2, Shift),
            '#' => (Trs80Model100Key.D3, Shift),
            '$' => (Trs80Model100Key.D4, Shift),
            '%' => (Trs80Model100Key.D5, Shift),
            '^' => (Trs80Model100Key.D6, Shift),
            '&' => (Trs80Model100Key.D7, Shift),
            '*' => (Trs80Model100Key.D8, Shift),
            '(' => (Trs80Model100Key.D9, Shift),
            ')' => (Trs80Model100Key.D0, Shift),
            '-' => (Trs80Model100Key.Minus, null),
            '_' => (Trs80Model100Key.Minus, Shift),
            '=' => (Trs80Model100Key.Equals, null),
            '+' => (Trs80Model100Key.Equals, Shift),
            '[' => (Trs80Model100Key.Brackets, null),
            ']' => (Trs80Model100Key.Brackets, Shift),
            ';' => (Trs80Model100Key.Semicolon, null),
            ':' => (Trs80Model100Key.Semicolon, Shift),
            '\'' => (Trs80Model100Key.Quote, null),
            '"' => (Trs80Model100Key.Quote, Shift),
            ',' => (Trs80Model100Key.Comma, null),
            '<' => (Trs80Model100Key.Comma, Shift),
            '.' => (Trs80Model100Key.Period, null),
            '>' => (Trs80Model100Key.Period, Shift),
            '/' => (Trs80Model100Key.Slash, null),
            '?' => (Trs80Model100Key.Slash, Shift),
            ' ' => (Trs80Model100Key.Space, null),
            '\r' => (Trs80Model100Key.Enter, null),
            '\b' => (Trs80Model100Key.Delete, null),
            '\t' => (Trs80Model100Key.Tab, null),
            '\u001B' => (Trs80Model100Key.Escape, null),
            '\u001C' => (Trs80Model100Key.Right, null),
            '\u001D' => (Trs80Model100Key.Left, null),
            '\u001E' => (Trs80Model100Key.Up, null),
            '\u001F' => (Trs80Model100Key.Down, null),
            >= '\u0080' and <= '\u0087' => ((Trs80Model100Key)(code - 0x80 + (int)Trs80Model100Key.F1), null),
            '\u0088' => (Trs80Model100Key.Label, null),
            '\u0089' => (Trs80Model100Key.Print, null),
            '\u008A' => (Trs80Model100Key.Paste, null),
            '\u008B' => (Trs80Model100Key.Break, null),
            '\u008C' => (Trs80Model100Key.Break, Shift),
            >= '\u0001' and <= '\u001A' => (Letter(code - 1), Trs80Model100Key.Control),
            _ => null
        };
    }

    // The letters are spread over columns 0-3 of the matrix.
    private static Trs80Model100Key Letter(int index) => (char)('A' + index) switch
    {
        'A' => Trs80Model100Key.A, 'B' => Trs80Model100Key.B, 'C' => Trs80Model100Key.C, 'D' => Trs80Model100Key.D,
        'E' => Trs80Model100Key.E, 'F' => Trs80Model100Key.F, 'G' => Trs80Model100Key.G, 'H' => Trs80Model100Key.H,
        'I' => Trs80Model100Key.I, 'J' => Trs80Model100Key.J, 'K' => Trs80Model100Key.K, 'L' => Trs80Model100Key.L,
        'M' => Trs80Model100Key.M, 'N' => Trs80Model100Key.N, 'O' => Trs80Model100Key.O, 'P' => Trs80Model100Key.P,
        'Q' => Trs80Model100Key.Q, 'R' => Trs80Model100Key.R, 'S' => Trs80Model100Key.S, 'T' => Trs80Model100Key.T,
        'U' => Trs80Model100Key.U, 'V' => Trs80Model100Key.V, 'W' => Trs80Model100Key.W, 'X' => Trs80Model100Key.X,
        'Y' => Trs80Model100Key.Y, _ => Trs80Model100Key.Z
    };
}
