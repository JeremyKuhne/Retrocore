// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Runtime.InteropServices;

namespace Retrocore.Machines.Kaypro;

/// <summary>
///  The Kaypro II's display: 24 lines of 80 characters from 4K of video RAM, each line 128 bytes apart, drawn on a green screen
///  on a 9-inch screen.
/// </summary>
/// <remarks>
///  <para>
///   Each character cell is 7 dots wide and 10 scanlines high. The character generator gives the top eight
///   scanlines' middle five dots, lit where its bits are clear. The display inverts a code's bit 7 before it
///   addresses the chip, whose first half is blank, so a code with bit 7 set blinks: it shows every other eight
///   frames. That is the ROM's cursor.
///  </para>
/// </remarks>
public sealed class KayproVideo : IVideoSource, ICharacterSet
{
    /// <summary>
    ///  The lines on the screen.
    /// </summary>
    public const int Rows = 24;

    /// <summary>
    ///  The characters on a line.
    /// </summary>
    public const int Columns = 80;

    /// <summary>
    ///  The bytes from one line's start to the next's.
    /// </summary>
    public const int LineBytes = 128;

    /// <summary>
    ///  The video RAM's size.
    /// </summary>
    public const int Size = 0x1000;

    private const int CellWidth = 7;
    private const int CellHeight = 10;
    private const int GlyphLines = 8;
    private const int ShownLines = Rows * CellHeight;

    private static readonly uint s_on = Rgba(0xF0, 0xF0, 0xF0);
    private static readonly uint s_off = Rgba(0x10, 0x10, 0x10);

    private readonly byte[] _ram = new byte[Size];
    private readonly byte[] _scanned = new byte[Size];
    private readonly byte[] _characterGenerator;
    private ulong _scannedFrames;

    /// <summary>
    ///  Creates the display.
    /// </summary>
    /// <param name="characterGenerator">The character generator.</param>
    internal KayproVideo(ReadOnlyMemory<byte> characterGenerator)
    {
        _characterGenerator = characterGenerator.ToArray();
    }

    /// <summary>
    ///  Gets the T-state within the frame.
    /// </summary>
    public int CycleInFrame { get; private set; }

    /// <summary>
    ///  Gets the frames drawn since power-up.
    /// </summary>
    public ulong Frames { get; private set; }

    /// <inheritdoc/>
    public int Width => Columns * CellWidth;

    /// <inheritdoc/>
    public int Height => ShownLines;

    /// <inheritdoc/>
    public int CyclesPerFrame => KayproTiming.CyclesPerFrame;

    /// <summary>
    ///  Reads video RAM.
    /// </summary>
    /// <param name="offset">The offset from <c>$3000</c>.</param>
    /// <returns>The byte.</returns>
    public byte Read(int offset) => _ram[offset & (Size - 1)];

    /// <summary>
    ///  Writes video RAM.
    /// </summary>
    /// <param name="offset">The offset from <c>$3000</c>.</param>
    /// <param name="value">The byte.</param>
    public void Write(int offset, byte value) => _ram[offset & (Size - 1)] = value;

    /// <summary>
    ///  Gets the code shown at a place on the screen.
    /// </summary>
    /// <param name="row">The line, 0-23.</param>
    /// <param name="column">The column, 0-79.</param>
    /// <returns>The code, bit 7 set while it blinks.</returns>
    public byte Displayed(int row, int column) => _ram[(row * LineBytes) + column];

    /// <summary>
    ///  Counts a T-state, latching the picture as the beam leaves the shown lines.
    /// </summary>
    /// <returns>Whether the picture was latched.</returns>
    internal bool Tick()
    {
        if (++CycleInFrame < KayproTiming.CyclesPerFrame)
        {
            if (CycleInFrame != ShownLines * KayproTiming.CyclesPerLine) { return false; }
            Array.Copy(_ram, _scanned, _ram.Length);
            _scannedFrames = Frames;
            return true;
        }

        CycleInFrame = 0;
        Frames++;
        return false;
    }

    /// <inheritdoc/>
    public void Render(Span<byte> pixels, bool scanned)
    {
        int width = Width;
        if (pixels.Length < width * Height * 4)
        {
            throw new ArgumentException("The pixel buffer is too small.", nameof(pixels));
        }

        Span<uint> output = MemoryMarshal.Cast<byte, uint>(pixels)[..(width * Height)];
        output.Fill(s_off);
        byte[] source = scanned ? _scanned : _ram;
        bool flashed = Blinking(scanned ? _scannedFrames : Frames);
        for (int row = 0; row < Rows; row++)
        {
            for (int line = 0; line < GlyphLines; line++)
            {
                Span<uint> scan = output.Slice(((row * CellHeight) + line) * width, width);
                for (int column = 0; column < Columns; column++)
                {
                    int dots = Dots(source[(row * LineBytes) + column], line, flashed);
                    if (dots == 0) { continue; }
                    Span<uint> cell = scan.Slice(column * CellWidth, CellWidth);
                    for (int pixel = 0; pixel < 5; pixel++)
                    {
                        if ((dots & (0x10 >> pixel)) != 0) { cell[pixel + 1] = s_on; }
                    }
                }
            }
        }
    }

    /// <inheritdoc/>
    public int CharacterWidth => CellWidth;

    /// <inheritdoc/>
    public int CharacterHeight => CellHeight;

    /// <inheritdoc/>
    public bool IsLit(byte code, int line, int pixel, bool flashed) =>
        line < GlyphLines && pixel is >= 1 and <= 5 && (Dots(code, line, flashed) & (0x10 >> (pixel - 1))) != 0;

    /// <inheritdoc/>
    public char Character(byte code)
    {
        // Codes below $20 are Greek letters, and $7F a checkerboard; bit 7 blinks a code.
        int low = code & 0x7F;
        return low is < 0x20 or 0x7F ? '\0' : (char)low;
    }

    // Whether a blinking character shows: for eight frames of every sixteen.
    private static bool Blinking(ulong frames) => (frames & 0x08) != 0;

    // A code's lit dots on a scanline, bit 4 at the left.
    private int Dots(byte code, int line, bool flashed)
    {
        int character = code ^ 0x80;
        if (character < 0x80 && flashed) { character |= 0x80; }
        return ~_characterGenerator[(character << 3) | line] & 0x1F;
    }

    private static uint Rgba(byte red, byte green, byte blue) =>
        (uint)(red | (green << 8) | (blue << 16) | (0xFF << 24));
}
