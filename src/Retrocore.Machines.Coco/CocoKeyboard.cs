// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Coco;

/// <summary>
///  The Color Computer's keyboard: a matrix of seven rows, read on PIA 0's port A, and eight columns, strobed by
///  its port B.
/// </summary>
public sealed class CocoKeyboard
{
    // A typed key is held 40 ms and released for 40 ms before the next.
    private const int HoldCycles = 40 * CocoTiming.CyclesPerMillisecond;
    private const int ReleaseCycles = 40 * CocoTiming.CyclesPerMillisecond;

    // Color BASIC tokenizes and stores a line after ENTER without scanning the keyboard, and the keyboard keeps no
    // buffer, so a key pressed meanwhile is lost; typing waits longer after ENTER, as a person would.
    private const int ReleaseAfterEnterCycles = 400 * CocoTiming.CyclesPerMillisecond;

    private readonly byte[] _rows = new byte[7];
    private readonly Queue<(CocoKey Key, bool Shift)> _typed = new();
    private (CocoKey Key, bool Shift)? _current;
    private int _remaining;

    /// <summary>
    ///  Gets a counter that changes whenever a key goes up or down, so the bus knows to rescan the matrix.
    /// </summary>
    internal int Version { get; private set; }

    /// <summary>
    ///  Presses or releases a key.
    /// </summary>
    /// <param name="key">The key.</param>
    /// <param name="pressed">Whether it is down.</param>
    public void Set(CocoKey key, bool pressed)
    {
        int row = (int)key >> 3;
        byte bit = (byte)(1 << ((int)key & 7));
        byte old = _rows[row];
        _rows[row] = pressed ? (byte)(old | bit) : (byte)(old & ~bit);
        if (_rows[row] != old) { Version++; }
    }

    /// <summary>
    ///  Gets whether a key is down.
    /// </summary>
    /// <param name="key">The key.</param>
    /// <returns>Whether it is pressed.</returns>
    public bool IsPressed(CocoKey key) => (_rows[(int)key >> 3] & (1 << ((int)key & 7))) != 0;

    /// <summary>
    ///  Gets whether any key is down.
    /// </summary>
    public bool AnyPressed => _rows.AsSpan().ContainsAnyExcept((byte)0);

    /// <summary>
    ///  Queues a typed character: ASCII, with 13 ENTER, 8 left, 9 right, 10 down, 11 up, 12 or 31 CLEAR, and 1 or 27
    ///  BREAK. Letters of either case type unshifted, so they read as Color BASIC's uppercase.
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
    ///  Releases every key and forgets typed ones.
    /// </summary>
    public void Clear()
    {
        _rows.AsSpan().Clear();
        _typed.Clear();
        _current = null;
        _remaining = 0;
        Version++;
    }

    /// <summary>
    ///  Reads the matrix both ways: the rows that see a pressed key in a column driven low, and the columns that see
    ///  a pressed key in a row driven low.
    /// </summary>
    /// <param name="columnsOut">Port B's output, low on strobed columns.</param>
    /// <param name="rowsOut">Port A's output, low on rows a program drives, as a reverse scan does.</param>
    /// <param name="rowsIn">Receives port A's bits 0-6, low on rows that see a pressed key.</param>
    /// <param name="columnsIn">Receives port B's levels, low on columns that see a pressed key.</param>
    internal void Scan(byte columnsOut, byte rowsOut, out byte rowsIn, out byte columnsIn)
    {
        int rows = 0x7F;
        int columns = 0xFF;
        for (int row = 0; row < _rows.Length; row++)
        {
            byte pressed = _rows[row];
            if ((pressed & ~columnsOut) != 0) { rows &= ~(1 << row); }
            if ((rowsOut & (1 << row)) == 0) { columns &= ~pressed; }
        }

        rowsIn = (byte)rows;
        columnsIn = (byte)columns;
    }

    /// <summary>
    ///  Advances typing by one slow CPU cycle.
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
            if (held.Shift) { Set(CocoKey.Shift, pressed: false); }
            _current = null;
            _remaining = held.Key == CocoKey.Enter ? ReleaseAfterEnterCycles : ReleaseCycles;
            return;
        }

        if (_typed.TryDequeue(out (CocoKey Key, bool Shift) next))
        {
            if (next.Shift) { Set(CocoKey.Shift, pressed: true); }
            Set(next.Key, pressed: true);
            _current = next;
            _remaining = HoldCycles;
        }
    }

    private static (CocoKey Key, bool Shift)? Map(byte code) => code switch
    {
        >= (byte)'A' and <= (byte)'Z' => ((CocoKey)(code - 'A' + (int)CocoKey.A), false),
        >= (byte)'a' and <= (byte)'z' => ((CocoKey)(code - 'a' + (int)CocoKey.A), false),
        >= (byte)'0' and <= (byte)'9' => ((CocoKey)(code - '0' + (int)CocoKey.D0), false),
        (byte)'@' => (CocoKey.At, false),
        (byte)' ' => (CocoKey.Space, false),
        (byte)':' => (CocoKey.Colon, false),
        (byte)';' => (CocoKey.Semicolon, false),
        (byte)',' => (CocoKey.Comma, false),
        (byte)'-' => (CocoKey.Minus, false),
        (byte)'.' => (CocoKey.Period, false),
        (byte)'/' => (CocoKey.Slash, false),
        (byte)'!' => (CocoKey.D1, true),
        (byte)'"' => (CocoKey.D2, true),
        (byte)'#' => (CocoKey.D3, true),
        (byte)'$' => (CocoKey.D4, true),
        (byte)'%' => (CocoKey.D5, true),
        (byte)'&' => (CocoKey.D6, true),
        (byte)'\'' => (CocoKey.D7, true),
        (byte)'(' => (CocoKey.D8, true),
        (byte)')' => (CocoKey.D9, true),
        (byte)'*' => (CocoKey.Colon, true),
        (byte)'+' => (CocoKey.Semicolon, true),
        (byte)'<' => (CocoKey.Comma, true),
        (byte)'=' => (CocoKey.Minus, true),
        (byte)'>' => (CocoKey.Period, true),
        (byte)'?' => (CocoKey.Slash, true),
        13 => (CocoKey.Enter, false),
        8 => (CocoKey.Left, false),
        9 => (CocoKey.Right, false),
        10 => (CocoKey.Down, false),
        11 => (CocoKey.Up, false),
        12 or 31 => (CocoKey.Clear, false),
        1 or 27 => (CocoKey.Break, false),
        _ => null
    };
}
