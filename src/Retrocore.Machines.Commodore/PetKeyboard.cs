// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Commodore;

/// <summary>
///  The PET's keyboard, graphics or business: ten rows, chosen by PIA 1's PA0-PA3 through a 74145 decoder, read on
///  its port B, a pressed key pulling its bit low.
/// </summary>
/// <remarks>
///  <para>
///   The kernal scans one row at a time in its 60 Hz interrupt and keeps a ten-key buffer, so a typed key is held
///   for three frames and released for three before the next.
///  </para>
/// </remarks>
public sealed class PetKeyboard
{
    private const int HoldCycles = 3 * PetTiming.CyclesPerFrame;
    private const int ReleaseCycles = 3 * PetTiming.CyclesPerFrame;

    // BASIC stores a line after RETURN without reading the buffer; a long line can take longer than ten keys.
    private const int ReleaseAfterReturnCycles = 12 * PetTiming.CyclesPerFrame;

    private readonly byte[] _rows = new byte[10];
    private readonly Queue<(int Key, bool Shift)> _typed = new();
    private readonly int _shift;
    private readonly int _return;
    private (int Key, bool Shift)? _current;
    private int _remaining;

    /// <summary>
    ///  Gets or sets whether typed keys use scan-length rather than typist-length holds and gaps.
    /// </summary>
    public bool FastTyping { get; set; }

    /// <summary>
    ///  Creates a keyboard with every key up.
    /// </summary>
    /// <param name="business">Whether it is the business keyboard rather than the graphics one.</param>
    public PetKeyboard(bool business = false)
    {
        Business = business;
        _shift = business ? (int)PetBusinessKey.LeftShift : (int)PetKey.LeftShift;
        _return = business ? (int)PetBusinessKey.Return : (int)PetKey.Return;
    }

    /// <summary>
    ///  Gets whether this is the business keyboard; its keys are <see cref="PetBusinessKey"/>, and the graphics
    ///  keyboard's are <see cref="PetKey"/>.
    /// </summary>
    public bool Business { get; }

    /// <summary>
    ///  Presses or releases a key of the graphics keyboard.
    /// </summary>
    /// <param name="key">The key.</param>
    /// <param name="pressed">Whether it is down.</param>
    /// <exception cref="InvalidOperationException">This is the business keyboard.</exception>
    public void Set(PetKey key, bool pressed)
    {
        if (Business) { throw new InvalidOperationException("The business keyboard's keys are PetBusinessKey."); }
        SetPosition((int)key, pressed);
    }

    /// <summary>
    ///  Presses or releases a key of the business keyboard.
    /// </summary>
    /// <param name="key">The key.</param>
    /// <param name="pressed">Whether it is down.</param>
    /// <exception cref="InvalidOperationException">This is the graphics keyboard.</exception>
    public void Set(PetBusinessKey key, bool pressed)
    {
        if (!Business) { throw new InvalidOperationException("The graphics keyboard's keys are PetKey."); }
        SetPosition((int)key, pressed);
    }

    /// <summary>
    ///  Gets whether a key of the graphics keyboard is down.
    /// </summary>
    /// <param name="key">The key.</param>
    /// <returns>Whether it is pressed.</returns>
    public bool IsPressed(PetKey key) => !Business && IsPressedAt((int)key);

    /// <summary>
    ///  Gets whether a key of the business keyboard is down.
    /// </summary>
    /// <param name="key">The key.</param>
    /// <returns>Whether it is pressed.</returns>
    public bool IsPressed(PetBusinessKey key) => Business && IsPressedAt((int)key);

    private void SetPosition(int key, bool pressed)
    {
        int row = key >> 3;
        byte bit = (byte)(1 << (key & 7));
        _rows[row] = pressed ? (byte)(_rows[row] | bit) : (byte)(_rows[row] & ~bit);
    }

    private bool IsPressedAt(int key) => (_rows[key >> 3] & (1 << (key & 7))) != 0;

    /// <summary>
    ///  Gets whether typed characters are still being pressed.
    /// </summary>
    public bool IsTyping => _current is not null || _typed.Count != 0;

    /// <summary>
    ///  Gets how many typed keys are queued or held.
    /// </summary>
    public int Pending => _typed.Count + (_current is not null ? 1 : 0);

    /// <summary>
    ///  Gets whether the physical matrix has any keys down.
    /// </summary>
    public bool AnyPressed => _rows.AsSpan().ContainsAnyExcept((byte)0);

    /// <summary>
    ///  Queues a typed character, in PETSCII, with SHIFT where the keyboard needs it: letters of either case type
    ///  unshifted, as the capitals the PET shows; 9 is the business keyboard's TAB and 27 its ESC;
    ///  13 is RETURN, 20 or 8 DELETE, 3 STOP, 19 HOME, 147 CLEAR (SHIFT-HOME), 17 and 145 cursor down and up, 29 and
    ///  157 right and left, 18 RVS ON and 146 RVS OFF.
    /// </summary>
    /// <param name="code">The character.</param>
    /// <returns>Whether the keyboard has a key for it.</returns>
    public bool Type(byte code)
    {
        if ((Business ? MapBusiness(code) : MapGraphics(code)) is not { } key) { return false; }
        _typed.Enqueue(key);
        return true;
    }

    /// <summary>
    ///  Releases every key and forgets typed ones.
    /// </summary>
    public void Clear()
    {
        _rows.AsSpan().Clear();
        _typed.Clear();
        _current = null;
        _remaining = 0;
    }

    /// <summary>
    ///  Reads a row: the bits of its pressed keys low. Rows past 9 select nothing.
    /// </summary>
    /// <param name="row">The row, PIA 1's PA0-PA3.</param>
    /// <returns>Port B's levels.</returns>
    internal byte Read(int row) => row < _rows.Length ? (byte)~_rows[row] : (byte)0xFF;

    /// <summary>
    ///  Advances typing by one CPU cycle.
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
            SetPosition(held.Key, pressed: false);
            if (held.Shift) { SetPosition(_shift, pressed: false); }
            _current = null;
            if (held.Key == _return) { _remaining = ReleaseAfterReturnCycles; }
            else if (FastTyping) { _remaining = PetTiming.CyclesPerFrame; }
            else { _remaining = ReleaseCycles; }
            return;
        }

        if (_typed.TryDequeue(out (int Key, bool Shift) next))
        {
            if (next.Shift) { SetPosition(_shift, pressed: true); }
            SetPosition(next.Key, pressed: true);
            _current = next;
            _remaining = FastTyping ? 2 * PetTiming.CyclesPerFrame : HoldCycles;
        }
    }

    private static (int Key, bool Shift)? MapGraphics(byte code) =>
        MapGraphicsKey(code) is { } key ? ((int)key.Key, key.Shift) : null;

    private static (PetKey Key, bool Shift)? MapGraphicsKey(byte code) => code switch
    {
        >= (byte)'A' and <= (byte)'Z' => (Letter((char)code), false),
        >= (byte)'a' and <= (byte)'z' => (Letter((char)(code - 0x20)), false),
        >= (byte)'0' and <= (byte)'9' => (Digit(code - '0'), false),
        (byte)'!' => (PetKey.Exclamation, false),
        (byte)'"' => (PetKey.DoubleQuote, false),
        (byte)'#' => (PetKey.Hash, false),
        (byte)'$' => (PetKey.Dollar, false),
        (byte)'%' => (PetKey.Percent, false),
        (byte)'&' => (PetKey.Ampersand, false),
        (byte)'\'' => (PetKey.Apostrophe, false),
        (byte)'(' => (PetKey.OpenParenthesis, false),
        (byte)')' => (PetKey.CloseParenthesis, false),
        (byte)'*' => (PetKey.KeypadAsterisk, false),
        (byte)'+' => (PetKey.KeypadPlus, false),
        (byte)',' => (PetKey.Comma, false),
        (byte)'-' => (PetKey.KeypadMinus, false),
        (byte)'.' => (PetKey.KeypadPeriod, false),
        (byte)'/' => (PetKey.KeypadSlash, false),
        (byte)':' => (PetKey.Colon, false),
        (byte)';' => (PetKey.Semicolon, false),
        (byte)'<' => (PetKey.LessThan, false),
        (byte)'=' => (PetKey.KeypadEquals, false),
        (byte)'>' => (PetKey.GreaterThan, false),
        (byte)'?' => (PetKey.Question, false),
        (byte)'@' => (PetKey.At, false),
        (byte)'[' => (PetKey.OpenBracket, false),
        (byte)'\\' => (PetKey.Backslash, false),
        (byte)']' => (PetKey.CloseBracket, false),
        (byte)'^' => (PetKey.UpArrow, false),
        (byte)'_' => (PetKey.LeftArrow, false),
        (byte)' ' => (PetKey.Space, false),
        13 => (PetKey.Return, false),
        8 or 20 => (PetKey.Delete, false),
        148 => (PetKey.Delete, true),
        3 => (PetKey.Stop, false),
        19 => (PetKey.Home, false),
        147 => (PetKey.Home, true),
        17 => (PetKey.CursorDown, false),
        145 => (PetKey.CursorDown, true),
        29 => (PetKey.CursorRight, false),
        157 => (PetKey.CursorRight, true),
        18 => (PetKey.Reverse, false),
        146 => (PetKey.Reverse, true),
        _ => null
    };

    private static PetKey Letter(char letter) => letter switch
    {
        'A' => PetKey.A, 'B' => PetKey.B, 'C' => PetKey.C, 'D' => PetKey.D, 'E' => PetKey.E, 'F' => PetKey.F,
        'G' => PetKey.G, 'H' => PetKey.H, 'I' => PetKey.I, 'J' => PetKey.J, 'K' => PetKey.K, 'L' => PetKey.L,
        'M' => PetKey.M, 'N' => PetKey.N, 'O' => PetKey.O, 'P' => PetKey.P, 'Q' => PetKey.Q, 'R' => PetKey.R,
        'S' => PetKey.S, 'T' => PetKey.T, 'U' => PetKey.U, 'V' => PetKey.V, 'W' => PetKey.W, 'X' => PetKey.X,
        'Y' => PetKey.Y, _ => PetKey.Z
    };

    private static PetKey Digit(int digit) => digit switch
    {
        0 => PetKey.Keypad0, 1 => PetKey.Keypad1, 2 => PetKey.Keypad2, 3 => PetKey.Keypad3, 4 => PetKey.Keypad4,
        5 => PetKey.Keypad5, 6 => PetKey.Keypad6, 7 => PetKey.Keypad7, 8 => PetKey.Keypad8, _ => PetKey.Keypad9
    };

    private static (int Key, bool Shift)? MapBusiness(byte code) =>
        MapBusinessKey(code) is { } key ? ((int)key.Key, key.Shift) : null;

    // The editor shifts $21-$3F by flipping bit 4, so each symbol is its key's character with SHIFT.
    private static (PetBusinessKey Key, bool Shift)? MapBusinessKey(byte code) => code switch
    {
        >= (byte)'A' and <= (byte)'Z' => (BusinessLetter((char)code), false),
        >= (byte)'a' and <= (byte)'z' => (BusinessLetter((char)(code - 0x20)), false),
        (byte)'0' => (PetBusinessKey.Digit0, false),
        >= (byte)'1' and <= (byte)'9' => (BusinessDigit(code - '0'), false),
        >= (byte)'!' and <= (byte)')' => (BusinessDigit(code - '!' + 1), true),
        (byte)'*' => (PetBusinessKey.Colon, true),
        (byte)'+' => (PetBusinessKey.Semicolon, true),
        (byte)',' => (PetBusinessKey.Comma, false),
        (byte)'-' => (PetBusinessKey.Minus, false),
        (byte)'.' => (PetBusinessKey.Period, false),
        (byte)'/' => (PetBusinessKey.Slash, false),
        (byte)':' => (PetBusinessKey.Colon, false),
        (byte)';' => (PetBusinessKey.Semicolon, false),
        (byte)'<' => (PetBusinessKey.Comma, true),
        (byte)'=' => (PetBusinessKey.Minus, true),
        (byte)'>' => (PetBusinessKey.Period, true),
        (byte)'?' => (PetBusinessKey.Slash, true),
        (byte)'@' => (PetBusinessKey.At, false),
        (byte)'[' => (PetBusinessKey.OpenBracket, false),
        (byte)'\\' => (PetBusinessKey.Backslash, false),
        (byte)']' => (PetBusinessKey.CloseBracket, false),
        (byte)'^' => (PetBusinessKey.UpArrow, false),
        (byte)'_' => (PetBusinessKey.LeftArrow, false),
        (byte)' ' => (PetBusinessKey.Space, false),
        13 => (PetBusinessKey.Return, false),
        8 or 20 => (PetBusinessKey.Delete, false),
        148 => (PetBusinessKey.Delete, true),
        3 => (PetBusinessKey.Stop, false),
        9 => (PetBusinessKey.Tab, false),
        27 => (PetBusinessKey.Escape, false),
        19 => (PetBusinessKey.Home, false),
        147 => (PetBusinessKey.Home, true),
        17 => (PetBusinessKey.CursorDown, false),
        145 => (PetBusinessKey.CursorDown, true),
        29 => (PetBusinessKey.CursorRight, false),
        157 => (PetBusinessKey.CursorRight, true),
        18 => (PetBusinessKey.Reverse, false),
        146 => (PetBusinessKey.Reverse, true),
        _ => null
    };

    private static PetBusinessKey BusinessLetter(char letter) => letter switch
    {
        'A' => PetBusinessKey.A, 'B' => PetBusinessKey.B, 'C' => PetBusinessKey.C, 'D' => PetBusinessKey.D,
        'E' => PetBusinessKey.E, 'F' => PetBusinessKey.F, 'G' => PetBusinessKey.G, 'H' => PetBusinessKey.H,
        'I' => PetBusinessKey.I, 'J' => PetBusinessKey.J, 'K' => PetBusinessKey.K, 'L' => PetBusinessKey.L,
        'M' => PetBusinessKey.M, 'N' => PetBusinessKey.N, 'O' => PetBusinessKey.O, 'P' => PetBusinessKey.P,
        'Q' => PetBusinessKey.Q, 'R' => PetBusinessKey.R, 'S' => PetBusinessKey.S, 'T' => PetBusinessKey.T,
        'U' => PetBusinessKey.U, 'V' => PetBusinessKey.V, 'W' => PetBusinessKey.W, 'X' => PetBusinessKey.X,
        'Y' => PetBusinessKey.Y, _ => PetBusinessKey.Z
    };

    private static PetBusinessKey BusinessDigit(int digit) => digit switch
    {
        1 => PetBusinessKey.Digit1, 2 => PetBusinessKey.Digit2, 3 => PetBusinessKey.Digit3,
        4 => PetBusinessKey.Digit4, 5 => PetBusinessKey.Digit5, 6 => PetBusinessKey.Digit6,
        7 => PetBusinessKey.Digit7, 8 => PetBusinessKey.Digit8, _ => PetBusinessKey.Digit9
    };
}
