// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Commodore.Vic20;

/// <summary>
///  The VIC-20's keyboard: 64 keys in an 8 × 8 matrix, whose columns VIA 2's port B drives low one at a time while
///  port A reads the rows, a pressed key pulling its row low. RESTORE is wired apart, to VIA 1's CA1.
/// </summary>
/// <remarks>
///  <para>
///   The kernal scans the matrix in its 60 Hz interrupt and keeps a ten-key buffer, so a typed key is held for three
///   jiffies and released for three before the next.
///  </para>
/// </remarks>
public sealed class Vic20Keyboard
{
    private readonly byte[] _columns = new byte[8];
    private readonly Queue<(Vic20Key Key, Vic20Key? Modifier)> _typed = new();
    private readonly int _holdCycles;
    private readonly int _releaseCycles;
    private readonly int _releaseAfterReturnCycles;
    private (Vic20Key Key, Vic20Key? Modifier)? _current;
    private int _remaining;

    /// <summary>
    ///  Creates a keyboard with every key up.
    /// </summary>
    /// <param name="cpuHertz">The machine's clock, which times typed keys in jiffies.</param>
    public Vic20Keyboard(double cpuHertz)
    {
        int jiffy = (int)(cpuHertz / 60);
        _holdCycles = 3 * jiffy;
        _releaseCycles = 3 * jiffy;

        // BASIC stores a line after RETURN without reading the buffer; a long line can take longer than ten keys.
        _releaseAfterReturnCycles = 12 * jiffy;
    }

    /// <summary>
    ///  Gets or sets whether RESTORE is down.
    /// </summary>
    public bool Restore { get; set; }

    /// <summary>
    ///  Gets whether typed characters are still being pressed.
    /// </summary>
    public bool IsTyping => _current is not null || _typed.Count != 0;

    /// <summary>
    ///  Presses or releases a key.
    /// </summary>
    /// <param name="key">The key.</param>
    /// <param name="pressed">Whether it is down.</param>
    public void Set(Vic20Key key, bool pressed)
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
    public bool IsPressed(Vic20Key key) => (_columns[(int)key >> 3] & (1 << ((int)key & 7))) != 0;

    /// <summary>
    ///  Queues a typed character, in PETSCII, with SHIFT or CTRL where the keyboard needs it: letters of either case
    ///  type unshifted, as the capitals the VIC shows at power-on; 13 is RETURN, 20 or 8 DEL, 148 INST, 3 STOP, 19
    ///  HOME, 147 CLR, 17 and 145 cursor down and up, 29 and 157 right and left, 133-140 f1-f8, 18 RVS ON and 146 RVS
    ///  OFF, and the colour codes (144, 5, 28, 159, 156, 30, 31, 158) CTRL with 1-8. <c>\</c> types £.
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
    ///  Releases every key and forgets typed ones.
    /// </summary>
    public void Clear()
    {
        _columns.AsSpan().Clear();
        _typed.Clear();
        _current = null;
        _remaining = 0;
        Restore = false;
    }

    /// <summary>
    ///  Reads the rows: each bit low whose row has a pressed key in a column port B drives low.
    /// </summary>
    /// <param name="columns">Port B's levels, a low bit selecting its column.</param>
    /// <returns>Port A's levels.</returns>
    internal byte ReadRows(byte columns)
    {
        int rows = 0;
        for (int column = 0; column < 8; column++)
        {
            if ((columns & (1 << column)) == 0) { rows |= _columns[column]; }
        }

        return (byte)~rows;
    }

    /// <summary>
    ///  Advances typing by one bus cycle.
    /// </summary>
    internal void Tick()
    {
        if (_remaining > 0)
        {
            _remaining--;
            return;
        }

        if (_current is { } held)
        {
            Set(held.Key, pressed: false);
            SetModifier(held.Modifier, pressed: false);
            _current = null;
            _remaining = held.Key == Vic20Key.Return ? _releaseAfterReturnCycles : _releaseCycles;
            return;
        }

        if (_typed.TryDequeue(out (Vic20Key Key, Vic20Key? Modifier) next))
        {
            SetModifier(next.Modifier, pressed: true);
            Set(next.Key, pressed: true);
            _current = next;
            _remaining = _holdCycles;
        }
    }

    private void SetModifier(Vic20Key? modifier, bool pressed)
    {
        if (modifier is { } key) { Set(key, pressed); }
    }

    private static (Vic20Key Key, Vic20Key? Modifier)? Map(byte code) => code switch
    {
        >= (byte)'A' and <= (byte)'Z' => (Letter((char)code), null),
        >= (byte)'a' and <= (byte)'z' => (Letter((char)(code - 0x20)), null),
        >= (byte)'0' and <= (byte)'9' => (Digit(code - '0'), null),
        >= (byte)'!' and <= (byte)')' => (Digit(code - '!' + 1), Vic20Key.LeftShift),
        (byte)'*' => (Vic20Key.Asterisk, null),
        (byte)'+' => (Vic20Key.Plus, null),
        (byte)',' => (Vic20Key.Comma, null),
        (byte)'-' => (Vic20Key.Minus, null),
        (byte)'.' => (Vic20Key.Period, null),
        (byte)'/' => (Vic20Key.Slash, null),
        (byte)':' => (Vic20Key.Colon, null),
        (byte)';' => (Vic20Key.Semicolon, null),
        (byte)'<' => (Vic20Key.Comma, Vic20Key.LeftShift),
        (byte)'=' => (Vic20Key.Equals, null),
        (byte)'>' => (Vic20Key.Period, Vic20Key.LeftShift),
        (byte)'?' => (Vic20Key.Slash, Vic20Key.LeftShift),
        (byte)'@' => (Vic20Key.At, null),
        (byte)'[' => (Vic20Key.Colon, Vic20Key.LeftShift),
        (byte)'\\' => (Vic20Key.Pound, null),
        (byte)']' => (Vic20Key.Semicolon, Vic20Key.LeftShift),
        (byte)'^' => (Vic20Key.UpArrow, null),
        (byte)'_' => (Vic20Key.LeftArrow, null),
        (byte)' ' => (Vic20Key.Space, null),
        13 => (Vic20Key.Return, null),
        8 or 20 => (Vic20Key.Delete, null),
        148 => (Vic20Key.Delete, Vic20Key.LeftShift),
        3 => (Vic20Key.Stop, null),
        19 => (Vic20Key.Home, null),
        147 => (Vic20Key.Home, Vic20Key.LeftShift),
        17 => (Vic20Key.CursorDown, null),
        145 => (Vic20Key.CursorDown, Vic20Key.LeftShift),
        29 => (Vic20Key.CursorRight, null),
        157 => (Vic20Key.CursorRight, Vic20Key.LeftShift),
        133 => (Vic20Key.F1, null),
        134 => (Vic20Key.F3, null),
        135 => (Vic20Key.F5, null),
        136 => (Vic20Key.F7, null),
        137 => (Vic20Key.F1, Vic20Key.LeftShift),
        138 => (Vic20Key.F3, Vic20Key.LeftShift),
        139 => (Vic20Key.F5, Vic20Key.LeftShift),
        140 => (Vic20Key.F7, Vic20Key.LeftShift),
        18 => (Vic20Key.Digit9, Vic20Key.Control),
        146 => (Vic20Key.Digit0, Vic20Key.Control),
        144 => (Vic20Key.Digit1, Vic20Key.Control),
        5 => (Vic20Key.Digit2, Vic20Key.Control),
        28 => (Vic20Key.Digit3, Vic20Key.Control),
        159 => (Vic20Key.Digit4, Vic20Key.Control),
        156 => (Vic20Key.Digit5, Vic20Key.Control),
        30 => (Vic20Key.Digit6, Vic20Key.Control),
        31 => (Vic20Key.Digit7, Vic20Key.Control),
        158 => (Vic20Key.Digit8, Vic20Key.Control),
        _ => null
    };

    private static readonly Vic20Key[] s_letters =
    [
        Vic20Key.A, Vic20Key.B, Vic20Key.C, Vic20Key.D, Vic20Key.E, Vic20Key.F, Vic20Key.G, Vic20Key.H, Vic20Key.I,
        Vic20Key.J, Vic20Key.K, Vic20Key.L, Vic20Key.M, Vic20Key.N, Vic20Key.O, Vic20Key.P, Vic20Key.Q, Vic20Key.R,
        Vic20Key.S, Vic20Key.T, Vic20Key.U, Vic20Key.V, Vic20Key.W, Vic20Key.X, Vic20Key.Y, Vic20Key.Z
    ];

    private static Vic20Key Letter(char letter) => s_letters[letter - 'A'];

    private static Vic20Key Digit(int digit) => digit switch
    {
        0 => Vic20Key.Digit0, 1 => Vic20Key.Digit1, 2 => Vic20Key.Digit2, 3 => Vic20Key.Digit3, 4 => Vic20Key.Digit4,
        5 => Vic20Key.Digit5, 6 => Vic20Key.Digit6, 7 => Vic20Key.Digit7, 8 => Vic20Key.Digit8, _ => Vic20Key.Digit9
    };
}
