// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Runtime.InteropServices;

namespace Retrocore.Machines.Apple1;

/// <summary>
///  The Apple-1's video terminal: 24 lines of 40 characters, kept in shift registers rather than the 6502's
///  memory, which takes one character a frame from the PIA's port B.
/// </summary>
/// <remarks>
///  <para>
///   The terminal stores six bits a character, the Signetics 2513's character address: ASCII bits 0-4, with bit 6
///   inverted above them. Bit 5 is dropped, so lowercase shows as uppercase. A character is written only when bit
///   5 or bit 6 is set, so control characters other than Return are dropped. Return blanks the rest of the line
///   and moves the cursor to the next; the line after the last scrolls the screen up.
///  </para>
///  <para>
///   A write to port B takes CB2 low, which the terminal latches as data available and shows on PB7 (busy). The
///   terminal can only write at the cursor, once a frame as the beam reaches its cell, so it takes the character
///   then, and pulses CB1, which in the handshake mode the Monitor sets up takes CB2 high again. A character
///   therefore waits up to a frame, about 16.7 ms, which limits output to 60 characters a second.
///  </para>
///  <para>
///   The cursor is the 2513's <c>@</c> blinking with a space, from a 555 timer; here it changes every 16 frames.
///  </para>
/// </remarks>
public sealed class Apple1Terminal : IVideoSource
{
    /// <summary>
    ///  Characters per line.
    /// </summary>
    public const int Columns = 40;

    /// <summary>
    ///  Lines on the screen.
    /// </summary>
    public const int Rows = 24;

    /// <summary>
    ///  Scanlines per line of text: seven rows of dots and a blank one.
    /// </summary>
    public const int LinesPerRow = 8;

    /// <summary>
    ///  Pixels per character: five dots and two between characters.
    /// </summary>
    public const int PixelsPerCharacter = 7;

    // The 2513's character for a blank and for the cursor's @.
    private const byte Blank = 32;
    private const byte CursorCharacter = 0;

    // Frames between the cursor's changes.
    private const int BlinkFrames = 16;

    // Cycles CB1's one-shot holds its pulse: about 3.5 microseconds.
    private const int AcknowledgeCycles = 4;

    private static readonly uint s_on = Rgba(0xF0, 0xF0, 0xF0);
    private static readonly uint s_off = Rgba(0x10, 0x10, 0x10);

    private readonly byte[] _screen = new byte[Columns * Rows];
    private readonly byte[] _characterGenerator;
    private readonly Pia6821 _pia;
    private bool _lastStrobe = true;
    private int _acknowledge;

    /// <summary>
    ///  Creates the terminal on the PIA's port B.
    /// </summary>
    /// <param name="characterGenerator">The 512-byte character generator.</param>
    /// <param name="pia">The PIA.</param>
    internal Apple1Terminal(ReadOnlyMemory<byte> characterGenerator, Pia6821 pia)
    {
        _characterGenerator = characterGenerator.ToArray();
        _pia = pia;
        _screen.AsSpan().Fill(Blank);
    }

    /// <summary>
    ///  Gets the cursor's line, 0-23.
    /// </summary>
    public int CursorRow { get; private set; }

    /// <summary>
    ///  Gets the cursor's column, 0-39.
    /// </summary>
    public int CursorColumn { get; private set; }

    /// <summary>
    ///  Gets whether a character waits for the terminal to take it, which PB7 shows.
    /// </summary>
    public bool Busy { get; private set; }

    /// <summary>
    ///  Gets the cycle within the frame.
    /// </summary>
    public int CycleInFrame { get; private set; }

    /// <summary>
    ///  Gets the frames completed.
    /// </summary>
    public ulong Frames { get; private set; }

    /// <summary>
    ///  Gets whether the blinking cursor shows its <c>@</c> now.
    /// </summary>
    public bool CursorShown => Frames / BlinkFrames % 2 == 0;

    /// <inheritdoc/>
    public int Width => Columns * PixelsPerCharacter;

    /// <inheritdoc/>
    public int Height => Rows * LinesPerRow;

    /// <inheritdoc/>
    public int CyclesPerFrame => Apple1Timing.CyclesPerFrame;

    /// <summary>
    ///  Gets a line of the screen as ASCII, uppercase and symbols, without the cursor.
    /// </summary>
    /// <param name="row">The line, 0-23.</param>
    /// <returns>The 40 characters.</returns>
    public string Line(int row)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(row);
        ArgumentOutOfRangeException.ThrowIfGreaterThanOrEqual(row, Rows);
        return string.Create(Columns, _screen.AsMemory(row * Columns, Columns), static (text, line) =>
        {
            for (int column = 0; column < text.Length; column++) { text[column] = Ascii(line.Span[column]); }
        });
    }

    /// <summary>
    ///  Gets the character a stored code shows, as ASCII.
    /// </summary>
    /// <param name="code">The six-bit code.</param>
    /// <returns>The character: <c>@</c>-<c>_</c> for 0-31, space-<c>?</c> for 32-63.</returns>
    public static char Ascii(byte code) => (char)(code < 32 ? code + 0x40 : code);

    /// <summary>
    ///  Gets the six-bit code the terminal stores for an ASCII character.
    /// </summary>
    /// <param name="ascii">The character's code, bit 7 ignored.</param>
    /// <returns>The code, 0-63.</returns>
    public static byte Code(int ascii) => (byte)((ascii & 0x1F) | ((~ascii & 0x40) >> 1));

    /// <summary>
    ///  Presses CLEAR SCREEN: blanks the screen and puts the cursor at the top left.
    /// </summary>
    public void ClearScreen()
    {
        _screen.AsSpan().Fill(Blank);
        CursorRow = CursorColumn = 0;
    }

    /// <summary>
    ///  Advances the beam one cycle: latches a write's strobe, and takes the character as the beam reaches the
    ///  cursor.
    /// </summary>
    internal void Tick()
    {
        // CB2's falling edge latches data available.
        bool strobe = _pia.CB2;
        if (_lastStrobe && !strobe) { Busy = true; }
        _lastStrobe = strobe;

        if (_acknowledge > 0 && --_acknowledge == 0) { _pia.SetCB1(false); }

        if (CycleInFrame == CursorCycle)
        {
            if (Busy)
            {
                Busy = false;
                Take((byte)(_pia.PinsB & 0x7F));
            }

            // The one-shot acknowledges as the cursor comes around.
            _pia.SetCB1(true);
            _acknowledge = AcknowledgeCycles;
        }

        if (++CycleInFrame == Apple1Timing.CyclesPerFrame)
        {
            CycleInFrame = 0;
            Frames++;
        }
    }

    /// <summary>
    ///  Resets the terminal's handshake, as the RESET button does through the PIA; the screen is kept.
    /// </summary>
    internal void Reset()
    {
        Busy = false;
        _lastStrobe = true;
    }

    // The cycle in the frame at which the beam reaches the cursor's cell.
    private int CursorCycle => (CursorRow * LinesPerRow * Apple1Timing.CyclesPerLine) + CursorColumn;

    // Writes a character at the cursor, or carries out a Return.
    private void Take(byte ascii)
    {
        if (ascii == 0x0D)
        {
            _screen.AsSpan((CursorRow * Columns) + CursorColumn, Columns - CursorColumn).Fill(Blank);
            NewLine();
            return;
        }

        if ((ascii & 0x60) == 0) { return; }
        _screen[(CursorRow * Columns) + CursorColumn] = Code(ascii);
        if (++CursorColumn == Columns) { NewLine(); }
    }

    private void NewLine()
    {
        CursorColumn = 0;
        if (++CursorRow < Rows) { return; }
        CursorRow = Rows - 1;
        _screen.AsSpan(Columns).CopyTo(_screen);
        _screen.AsSpan((Rows - 1) * Columns).Fill(Blank);
    }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The terminal changes only as the cursor passes, once a frame, so the scanned and current pictures are the
    ///   same.
    ///  </para>
    /// </remarks>
    public void Render(Span<byte> pixels, bool scanned)
    {
        int width = Width;
        if (pixels.Length < width * Height * 4)
        {
            throw new ArgumentException("The pixel buffer is too small.", nameof(pixels));
        }

        Span<uint> output = MemoryMarshal.Cast<byte, uint>(pixels);
        int cursor = CursorShown ? (CursorRow * Columns) + CursorColumn : -1;
        for (int row = 0; row < Rows; row++)
        {
            for (int line = 0; line < LinesPerRow; line++)
            {
                Span<uint> scan = output.Slice(((row * LinesPerRow) + line) * width, width);
                for (int column = 0; column < Columns; column++)
                {
                    int cell = (row * Columns) + column;

                    // The cursor flips the 2513's top address bit, turning the blank under it into @.
                    byte code = cell == cursor ? (byte)(_screen[cell] ^ (Blank ^ CursorCharacter)) : _screen[cell];
                    int dots = _characterGenerator[(code << 3) | line];
                    for (int x = 0; x < PixelsPerCharacter; x++)
                    {
                        bool lit = x is >= 1 and <= 5 && (dots & (0x10 >> (x - 1))) != 0;
                        scan[(column * PixelsPerCharacter) + x] = lit ? s_on : s_off;
                    }
                }
            }
        }
    }

    private static uint Rgba(byte red, byte green, byte blue) =>
        (uint)(red | (green << 8) | (blue << 16) | (0xFF << 24));
}
