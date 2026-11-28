// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Acorn;

/// <summary>
///  The BBC Micro's keyboard: a matrix of 10 columns and 8 rows, read over the slow data bus, with its own column
///  counter that scans for a key when the CPU is not reading it.
/// </summary>
/// <remarks>
///  <para>
///   With the addressable latch's keyboard write enable (bit 3) low, the CPU reads keys itself: it writes a key number
///   (column in bits 0-3, row in bits 4-6) to the slow data bus, and bit 7 reads back high if that key is down. With
///   the bit high, the keyboard's counter steps through the 16 columns at 1 MHz. Either way, CA2 of the system VIA is
///   high while any key in rows 1-7 of the addressed column is down, which is how a key press interrupts.
///  </para>
///  <para>
///   Row 0 carries SHIFT and CTRL, and in columns 2-9 the eight startup-option links, which never raise CA2.
///  </para>
/// </remarks>
public sealed class BbcKeyboard
{
    // The function keys f0-f9, which codes $F0-$F9 type.
    private static readonly BbcKey[] s_functionKeys =
    [
        BbcKey.F0, BbcKey.F1, BbcKey.F2, BbcKey.F3, BbcKey.F4, BbcKey.F5, BbcKey.F6, BbcKey.F7, BbcKey.F8, BbcKey.F9
    ];

    // Each column's keys down, one bit per row.
    private readonly byte[] _columns = new byte[16];
    private readonly Queue<byte> _typed = new();
    private int _column;
    private int _typingCycles;
    private (BbcKey Key, bool Shift, bool Control)? _holding;

    /// <summary>
    ///  Gets or sets whether typed keys use accelerated scan-length holds and gaps.
    /// </summary>
    public bool FastTyping { get; set; }

    // The 1 MHz cycles left that SHIFT is held for SHIFT-BREAK.
    private int _shiftCycles;

    /// <summary>
    ///  Gets or sets the startup-option links, as the operating system reads them into OSBYTE &amp;FF after a power-on
    ///  or CTRL-BREAK: bits 0-2 the screen mode, bit 3 clear to swap BREAK and SHIFT-BREAK, bits 4-5 the disk timings,
    ///  bit 7 set for the DFS rather than Econet. Bit 7 is column 2's link, bit 0 column 9's; a clear bit is a fitted
    ///  link, which reads as the link's key held down. The default, <c>$FF</c>, is no links: mode 7, SHIFT-BREAK to
    ///  boot, the fastest disk timings and the DFS.
    /// </summary>
    public byte StartupOptions { get; set; } = 0xFF;

    /// <summary>
    ///  Gets or sets the keyboard's mode, from the addressable latch's bit 3: true while the CPU reads the keys, false
    ///  while the keyboard scans.
    /// </summary>
    public bool CpuReads { get; set; }

    /// <summary>
    ///  Gets or sets whether the CAPS LOCK light is on, from the addressable latch's bit 6 (low lights it).
    /// </summary>
    public bool CapsLock { get; set; }

    /// <summary>
    ///  Gets whether CA2 is high: a key in rows 1-7 of the addressed column is down.
    /// </summary>
    public bool Interrupt => (_columns[_column] & 0xFE) != 0;

    /// <summary>
    ///  Gets whether typed text is still going in.
    /// </summary>
    public bool IsTyping => _holding is not null || _typed.Count != 0;

    /// <summary>
    ///  Gets how many typed keys are queued or held.
    /// </summary>
    public int Pending => _typed.Count + (_holding is not null ? 1 : 0);

    /// <summary>
    ///  Gets whether the physical matrix has any keys down, excluding the startup links.
    /// </summary>
    public bool AnyPressed => _columns.AsSpan().ContainsAnyExcept((byte)0);

    /// <summary>
    ///  Gets the column the keyboard addresses.
    /// </summary>
    public int Column => _column;

    /// <summary>
    ///  Presses a key.
    /// </summary>
    /// <param name="key">The key.</param>
    public void Press(BbcKey key) => _columns[(int)key & 15] |= (byte)(1 << ((int)key >> 4));

    /// <summary>
    ///  Releases a key.
    /// </summary>
    /// <param name="key">The key.</param>
    public void Release(BbcKey key) => _columns[(int)key & 15] &= (byte)~(1 << ((int)key >> 4));

    /// <summary>
    ///  Gets whether a key is down.
    /// </summary>
    /// <param name="key">The key.</param>
    /// <returns>Whether it is down.</returns>
    public bool IsDown(BbcKey key) => IsDown((int)key & 15, (int)key >> 4);

    /// <summary>
    ///  Releases every key.
    /// </summary>
    public void ReleaseAll()
    {
        Array.Clear(_columns);
        _typed.Clear();
        _holding = null;
        _shiftCycles = 0;
    }

    /// <summary>
    ///  Holds SHIFT down for a time and then lets it go, as a hand does through SHIFT-BREAK until the operating
    ///  system has read it.
    /// </summary>
    /// <param name="cycles">The 1 MHz cycles to hold it for.</param>
    public void HoldShift(int cycles)
    {
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(cycles);
        Press(BbcKey.Shift);
        _shiftCycles = cycles;
    }

    /// <summary>
    ///  Queues a character to type, with SHIFT or CTRL as it needs. While CAPS LOCK is on every letter is a capital,
    ///  so a lowercase letter presses CAPS LOCK first, and a capital is shifted while it is off.
    /// </summary>
    /// <param name="code">
    ///  An ASCII character, carriage return for RETURN, 8 or 127 for DELETE, 9 TAB, 27 ESCAPE, 1-26 CTRL with a letter,
    ///  the operating system's cursor and COPY codes: <c>$88</c> left, <c>$89</c> right, <c>$8A</c> down,
    ///  <c>$8B</c> up and <c>$87</c> COPY; <c>$8C</c> for SHIFT LOCK, which no key's character is; and
    ///  <c>$F0-$F9</c> for the function keys f0-f9.
    /// </param>
    /// <returns>Whether the BBC has a key for the character.</returns>
    public bool Type(byte code)
    {
        if (!TryMap(code, out _, out _, out _)) { return false; }
        _typed.Enqueue(code);
        return true;
    }

    /// <summary>
    ///  Reads the slow data bus while the CPU addresses the keyboard: the key number written, with bit 7 high if that
    ///  key is down, and the column it names addressed for CA2.
    /// </summary>
    /// <param name="bus">The slow data bus as the VIA drives it.</param>
    /// <returns>The bus with the keyboard's bit 7.</returns>
    public byte Read(byte bus)
    {
        if (!CpuReads) { return bus; }
        _column = bus & 15;
        return Peek(bus);
    }

    /// <summary>
    ///  Gets what <see cref="Read"/> would put on the bus, without latching the column.
    /// </summary>
    /// <param name="bus">The bus.</param>
    /// <returns>The bus with bit 7 from the key.</returns>
    public byte Peek(byte bus)
    {
        if (!CpuReads) { return bus; }
        bool down = IsDown(bus & 15, (bus >> 4) & 7);
        return (byte)((bus & 0x7F) | (down ? 0x80 : 0));
    }

    /// <summary>
    ///  Advances one 1 MHz cycle: the scan counter steps while the keyboard scans, and typed keys go down and up.
    /// </summary>
    internal void Tick()
    {
        if (!CpuReads) { _column = (_column + 1) & 15; }
        if (_shiftCycles > 0 && --_shiftCycles == 0) { Release(BbcKey.Shift); }
        if (_typingCycles > 0 && --_typingCycles > 0) { return; }
        if (_holding is { } held)
        {
            Release(held.Key);
            if (held.Shift) { Release(BbcKey.Shift); }
            if (held.Control) { Release(BbcKey.Control); }
            _holding = null;

            // Long enough up for the operating system's two-key rollover to see the key go.
            _typingCycles = held.Key == BbcKey.Return ? 120_000 : 40_000;
            return;
        }

        if (_typed.TryPeek(out byte code))
        {
            (BbcKey Key, bool Shift, bool Control) next;
            bool letter = (code | 0x20) is >= (byte)'a' and <= (byte)'z';
            bool capital = code is >= (byte)'A' and <= (byte)'Z';
            if (letter && !capital && CapsLock)
            {
                // CAPS LOCK makes every letter a capital, shifted or not; turn it off first.
                next = (BbcKey.CapsLock, false, false);
            }
            else
            {
                _typed.Dequeue();
                TryMap(code, out BbcKey key, out bool shift, out bool control);
                next = (key, letter ? capital && !CapsLock : shift, control);
            }

            if (next.Shift) { Press(BbcKey.Shift); }
            if (next.Control) { Press(BbcKey.Control); }
            Press(next.Key);
            _holding = next;

            // Held for four of the keyboard routine's 10 ms polls, well short of the 0.32 s auto-repeat delay.
            _typingCycles = FastTyping ? 20_000 : 40_000;
        }
    }

    private bool IsDown(int column, int row)
    {
        if (row == 0 && column is >= 2 and <= 9) { return (StartupOptions & (1 << (9 - column))) == 0; }
        return (_columns[column] & (1 << row)) != 0;
    }

    private static bool TryMap(byte code, out BbcKey key, out bool shift, out bool control)
    {
        shift = false;
        control = false;
        key = BbcKey.Space;
        switch (code)
        {
            case >= (byte)'A' and <= (byte)'Z':
                key = Letter(code - 'A');
                return true;
            case >= (byte)'a' and <= (byte)'z':
                key = Letter(code - 'a');
                shift = true;
                return true;
            case >= 1 and <= 26 when code is not (8 or 9 or 13):
                key = Letter(code - 1);
                control = true;
                return true;
        }

        const string Plain = "0123456789-^\\@[_;:],./ ";
        const string Shifted = "\0!\"#$%&'()=~|\0{`+*}<>?\0";
        ReadOnlySpan<BbcKey> keys =
        [
            BbcKey.D0, BbcKey.D1, BbcKey.D2, BbcKey.D3, BbcKey.D4,
            BbcKey.D5, BbcKey.D6, BbcKey.D7, BbcKey.D8, BbcKey.D9,
            BbcKey.Minus, BbcKey.Caret, BbcKey.Backslash, BbcKey.At, BbcKey.LeftBracket, BbcKey.Underscore,
            BbcKey.Semicolon, BbcKey.Colon, BbcKey.RightBracket, BbcKey.Comma, BbcKey.Period, BbcKey.Slash, BbcKey.Space
        ];

        int index = Plain.IndexOf((char)code, StringComparison.Ordinal);
        if (index >= 0)
        {
            key = keys[index];
            return true;
        }

        index = code == 0 ? -1 : Shifted.IndexOf((char)code, StringComparison.Ordinal);
        if (index >= 0)
        {
            key = keys[index];
            shift = true;
            return true;
        }

        (bool known, key) = code switch
        {
            13 => (true, BbcKey.Return),
            8 or 127 => (true, BbcKey.Delete),
            9 => (true, BbcKey.Tab),
            27 => (true, BbcKey.Escape),
            0x87 => (true, BbcKey.Copy),
            0x88 => (true, BbcKey.Left),
            0x89 => (true, BbcKey.Right),
            0x8A => (true, BbcKey.Down),
            0x8B => (true, BbcKey.Up),
            0x8C => (true, BbcKey.ShiftLock),
            >= 0xF0 and <= 0xF9 => (true, s_functionKeys[code - 0xF0]),
            _ => (false, BbcKey.Space)
        };

        return known;
    }

    private static BbcKey Letter(int index) => index switch
    {
        0 => BbcKey.A, 1 => BbcKey.B, 2 => BbcKey.C, 3 => BbcKey.D, 4 => BbcKey.E, 5 => BbcKey.F, 6 => BbcKey.G,
        7 => BbcKey.H, 8 => BbcKey.I, 9 => BbcKey.J, 10 => BbcKey.K, 11 => BbcKey.L, 12 => BbcKey.M, 13 => BbcKey.N,
        14 => BbcKey.O, 15 => BbcKey.P, 16 => BbcKey.Q, 17 => BbcKey.R, 18 => BbcKey.S, 19 => BbcKey.T, 20 => BbcKey.U,
        21 => BbcKey.V, 22 => BbcKey.W, 23 => BbcKey.X, 24 => BbcKey.Y, _ => BbcKey.Z
    };
}
