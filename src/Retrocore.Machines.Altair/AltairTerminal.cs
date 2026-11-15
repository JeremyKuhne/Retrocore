// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Chips;

namespace Retrocore.Machines.Altair;

/// <summary>
///  The terminal on the 88-2SIO's first port, or on the 88-SIO: an 80-by-24 glass teletype that understands the Lear
///  Siegler ADM-3A's controls, the most common terminal on Altairs running BASIC and CP/M.
/// </summary>
/// <remarks>
///  <para>
///   Printable characters ($20-$7E) appear at the cursor, which wraps to the next line after the 80th column and
///   scrolls the screen at the bottom. The controls are the ADM-3A's: ^H left, ^J down, ^K up, ^L right, ^M to the
///   first column, ^Z clear and home, ^^ home, and ESC <c>=</c> row column, each plus $20, to place the cursor.
///   Bit 7 is ignored; other controls, ^I among them, do nothing, as on the ADM-3A.
///  </para>
///  <para>
///   Keys go out on the line one character time apart, and only into an empty receive register, so typing ahead or
///   pasting never overruns the ACIA.
///  </para>
/// </remarks>
public sealed class AltairTerminal : IVideoSource
{
    /// <summary>
    ///  Characters per line.
    /// </summary>
    public const int Columns = 80;

    /// <summary>
    ///  Lines on the screen.
    /// </summary>
    public const int Rows = 24;

    /// <summary>
    ///  Pixel rows per character row: eight for the character and two between rows.
    /// </summary>
    public const int LinesPerRow = 10;

    /// <summary>
    ///  Pixels per character.
    /// </summary>
    public const int PixelsPerCharacter = 8;

    // Frames per half blink of the cursor.
    private const int BlinkFrames = 30;

    private readonly byte[] _screen = new byte[Columns * Rows];
    private readonly Queue<byte> _keys = new();
    private readonly ISerialLine _line;
    private int _lineCycles;

    // The ESC = sequence in progress: 0 none, 1 after ESC, 2 after '=', 3 after the row.
    private int _escape;
    private int _escapeRow;

    /// <summary>
    ///  Connects a terminal to a serial port: what it sends appears, and keys are its received characters.
    /// </summary>
    /// <param name="line">The serial port.</param>
    internal AltairTerminal(ISerialLine line)
    {
        _line = line;
        _line.Transmitted = Print;
        ClearScreen();
    }

    /// <summary>
    ///  Gets the cursor's row.
    /// </summary>
    public int CursorRow { get; private set; }

    /// <summary>
    ///  Gets the cursor's column.
    /// </summary>
    public int CursorColumn { get; private set; }

    /// <summary>
    ///  Gets the frames shown, for the cursor's blink.
    /// </summary>
    public ulong Frames { get; private set; }

    /// <summary>
    ///  Gets the cycles into the current frame.
    /// </summary>
    public int CycleInFrame { get; private set; }

    /// <summary>
    ///  Gets the number of keys typed but not yet sent.
    /// </summary>
    public int PendingKeys => _keys.Count;

    /// <inheritdoc/>
    public int Width => Columns * PixelsPerCharacter;

    /// <inheritdoc/>
    public int Height => Rows * LinesPerRow;

    /// <inheritdoc/>
    public int CyclesPerFrame => AltairTiming.CyclesPerFrame;

    /// <summary>
    ///  Gets a screen line's text.
    /// </summary>
    /// <param name="row">The row, 0-23.</param>
    /// <returns>Its 80 characters.</returns>
    public string Line(int row)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(row);
        ArgumentOutOfRangeException.ThrowIfGreaterThanOrEqual(row, Rows);
        char[] line = new char[Columns];
        for (int column = 0; column < Columns; column++) { line[column] = (char)_screen[(row * Columns) + column]; }
        return new string(line);
    }

    /// <summary>
    ///  Gets or sets whether typed lowercase letters go out as capitals, as a terminal's caps lock does, for software
    ///  such as Altair BASIC that takes only capitals.
    /// </summary>
    public bool UpperCase { get; set; }

    /// <summary>
    ///  Types a key: an ASCII character for the line.
    /// </summary>
    /// <param name="code">The character.</param>
    public void Type(byte code)
    {
        bool letter = code is >= (byte)'a' and <= (byte)'z';
        _keys.Enqueue(UpperCase && letter ? (byte)(code - 0x20) : code);
    }

    /// <summary>
    ///  Clears the screen and homes the cursor, as ^Z does.
    /// </summary>
    public void ClearScreen()
    {
        Array.Fill(_screen, (byte)' ');
        CursorRow = 0;
        CursorColumn = 0;
    }

    /// <summary>
    ///  Advances one CPU cycle: sends the next key when the line and the receive register are free, and counts
    ///  frames.
    /// </summary>
    internal void Tick()
    {
        if (_lineCycles > 0)
        {
            _lineCycles--;
        }
        else if (_keys.Count != 0 && _line.CanReceive)
        {
            _line.Receive(_keys.Dequeue());
            _lineCycles = _line.CyclesPerCharacter;
        }

        if (++CycleInFrame >= AltairTiming.CyclesPerFrame)
        {
            CycleInFrame = 0;
            Frames++;
        }
    }

    /// <summary>
    ///  Forgets typed keys and any control sequence in progress; the screen stays, as a terminal is not reset with the
    ///  computer.
    /// </summary>
    internal void Reset()
    {
        _keys.Clear();
        _lineCycles = 0;
        _escape = 0;
    }

    /// <summary>
    ///  Shows a character the computer sent.
    /// </summary>
    /// <param name="value">The character; bit 7 is ignored.</param>
    internal void Print(byte value)
    {
        int code = value & 0x7F;
        if (_escape != 0)
        {
            Escape(code);
            return;
        }

        switch (code)
        {
            case 0x08:
                if (CursorColumn > 0) { CursorColumn--; }
                return;
            case 0x0A:
                LineFeed();
                return;
            case 0x0B:
                if (CursorRow > 0) { CursorRow--; }
                return;
            case 0x0C:
                Advance();
                return;
            case 0x0D:
                CursorColumn = 0;
                return;
            case 0x1A:
                ClearScreen();
                return;
            case 0x1B:
                _escape = 1;
                return;
            case 0x1E:
                CursorRow = 0;
                CursorColumn = 0;
                return;
        }

        if (code is < 0x20 or 0x7F) { return; }
        _screen[(CursorRow * Columns) + CursorColumn] = (byte)code;
        Advance();
    }

    /// <inheritdoc/>
    public void Render(Span<byte> pixels, bool scanned)
    {
        if (pixels.Length != Width * Height * 4)
        {
            throw new ArgumentException("The frame buffer is the wrong size.", nameof(pixels));
        }

        ReadOnlySpan<byte> font = AltairTerminalFont.Glyphs;
        bool cursor = Frames / BlinkFrames % 2 == 0;
        for (int row = 0; row < Rows; row++)
        {
            for (int column = 0; column < Columns; column++)
            {
                int code = _screen[(row * Columns) + column];
                int glyph = (code - AltairTerminalFont.First) * 8;
                bool inverse = cursor && row == CursorRow && column == CursorColumn;
                for (int line = 0; line < LinesPerRow; line++)
                {
                    int bits = line < 8 ? font[glyph + line] : 0;
                    if (inverse) { bits ^= 0xFF; }
                    int offset = ((((row * LinesPerRow) + line) * Width) + (column * PixelsPerCharacter)) * 4;
                    for (int pixel = 0; pixel < PixelsPerCharacter; pixel++)
                    {
                        byte level = (bits & (0x80 >> pixel)) != 0 ? (byte)0xFF : (byte)0x00;
                        pixels[offset++] = level;
                        pixels[offset++] = level;
                        pixels[offset++] = level;
                        pixels[offset++] = 0xFF;
                    }
                }
            }
        }
    }

    // ESC = row column, each a character $20 plus the position.
    private void Escape(int code)
    {
        switch (_escape)
        {
            case 1:
                _escape = code == '=' ? 2 : 0;
                return;
            case 2:
                _escapeRow = code - 0x20;
                _escape = 3;
                return;
            default:
                _escape = 0;
                int column = code - 0x20;
                if (_escapeRow is >= 0 and < Rows && column is >= 0 and < Columns)
                {
                    CursorRow = _escapeRow;
                    CursorColumn = column;
                }

                return;
        }
    }

    // Moves right, wrapping to the next line after the last column.
    private void Advance()
    {
        if (++CursorColumn < Columns) { return; }
        CursorColumn = 0;
        LineFeed();
    }

    private void LineFeed()
    {
        if (CursorRow < Rows - 1)
        {
            CursorRow++;
            return;
        }

        Array.Copy(_screen, Columns, _screen, 0, Columns * (Rows - 1));
        Array.Fill(_screen, (byte)' ', Columns * (Rows - 1), Columns);
    }
}
