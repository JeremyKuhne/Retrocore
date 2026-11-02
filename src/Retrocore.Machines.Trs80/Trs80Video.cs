// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Trs80;

/// <summary>
///  The video: 1K of video RAM at <c>$3C00</c>, shown as 16 rows of 64 (or 32 wide) characters of 6x12 pixels.
/// </summary>
/// <remarks>
///  <para>
///   Codes with bit 7 set are block graphics: bits 0-5 light the six blocks of a 2x3 grid, top left first.
///   Other codes index the character generator, whose rows 0-7 fill the top of the cell. A stock Model I has
///   no RAM for bit 6, which reads as the inverse of bit 5; the lowercase modification adds it.
///  </para>
/// </remarks>
public sealed class Trs80Video : IVideoSource
{
    /// <summary>
    ///  Columns in 64-character mode.
    /// </summary>
    public const int Columns = 64;

    /// <summary>
    ///  Character rows.
    /// </summary>
    public const int Rows = 16;

    /// <summary>
    ///  Scanlines per character row.
    /// </summary>
    public const int LinesPerRow = 12;

    /// <summary>
    ///  Pixels per character in 64-character mode.
    /// </summary>
    public const int PixelsPerCharacter = 6;

    // The first displayed scanline of the frame, after vertical blanking.
    private const int FirstVisibleLine = 36;

    private static readonly uint s_on = Rgba(0xF0, 0xF0, 0xF0);
    private static readonly uint s_off = Rgba(0x10, 0x10, 0x10);

    private readonly byte[] _ram = new byte[Columns * Rows];
    private readonly byte[] _scanned = new byte[Columns * Rows];
    private readonly byte[] _characterGenerator;
    private readonly bool[] _scannedWide = new bool[Rows];

    // The CPU's byte shown at each scanline's character, or -1, for the frame being drawn.
    private readonly short[] _snow = new short[Rows * LinesPerRow * Columns];

    /// <summary>
    ///  Creates the video.
    /// </summary>
    /// <param name="characterGenerator">The 1K character generator.</param>
    /// <param name="lowercase">Whether the lowercase modification is fitted.</param>
    internal Trs80Video(ReadOnlyMemory<byte> characterGenerator, bool lowercase)
    {
        _characterGenerator = characterGenerator.ToArray();
        Lowercase = lowercase;
        _snow.AsSpan().Fill(-1);
    }

    /// <summary>
    ///  Gets whether the lowercase modification is fitted.
    /// </summary>
    public bool Lowercase { get; }

    /// <summary>
    ///  Gets or sets whether CPU access to video RAM shows as snow in the scanned picture.
    /// </summary>
    /// <remarks>
    ///  The video circuit and the CPU share video RAM's data bus. While the beam draws one of a line's 64
    ///  characters, one each T-state, a CPU access puts the CPU's byte on that bus, and the character generator
    ///  draws that byte's scanline in place of the stored character's.
    /// </remarks>
    public bool Snow { get; set; }

    /// <summary>
    ///  Gets or sets whether port <c>$FF</c> bit 3 selects 32-character mode, which shows the even columns
    ///  twice as wide.
    /// </summary>
    public bool WideCharacters { get; set; }

    /// <summary>
    ///  Gets the T-state within the frame.
    /// </summary>
    public int CycleInFrame { get; private set; }

    /// <summary>
    ///  Gets the frames completed.
    /// </summary>
    public ulong Frames { get; private set; }

    /// <inheritdoc/>
    public int Width => Columns * PixelsPerCharacter;

    /// <inheritdoc/>
    public int Height => Rows * LinesPerRow;

    /// <inheritdoc/>
    public int CyclesPerFrame => Trs80Timing.CyclesPerFrame;

    /// <summary>
    ///  Reads video RAM as the CPU sees it.
    /// </summary>
    /// <param name="offset">The offset, 0-1023.</param>
    /// <returns>The byte, with bit 6 derived on a stock machine.</returns>
    public byte Read(int offset)
    {
        byte value = _ram[offset & 0x3FF];
        return Lowercase ? value : (byte)(value | ((~value & 0x20) << 1));
    }

    /// <summary>
    ///  Writes video RAM; a stock machine drops bit 6.
    /// </summary>
    /// <param name="offset">The offset, 0-1023.</param>
    /// <param name="value">The byte.</param>
    public void Write(int offset, byte value) => _ram[offset & 0x3FF] = Lowercase ? value : (byte)(value & 0xBF);

    /// <summary>
    ///  Reads video RAM for the CPU, which can snow.
    /// </summary>
    /// <param name="offset">The offset, 0-1023.</param>
    /// <returns>The byte.</returns>
    internal byte CpuRead(int offset)
    {
        byte value = Read(offset);
        if (Snow) { Disturb(value); }
        return value;
    }

    /// <summary>
    ///  Writes video RAM for the CPU, which can snow.
    /// </summary>
    /// <param name="offset">The offset, 0-1023.</param>
    /// <param name="value">The byte.</param>
    internal void CpuWrite(int offset, byte value)
    {
        Write(offset, value);
        if (Snow) { Disturb(Lowercase ? value : (byte)(value & 0xBF)); }
    }

    // Shows the CPU's byte at the character the beam is drawing, if it is drawing one.
    private void Disturb(byte value)
    {
        int line = (CycleInFrame / Trs80Timing.CyclesPerLine) - FirstVisibleLine;
        int column = CycleInFrame % Trs80Timing.CyclesPerLine;
        if (line >= 0 && line < Rows * LinesPerRow && column < Columns)
        {
            _snow[(line * Columns) + column] = value;
        }
    }

    /// <summary>
    ///  Advances the beam one T-state, latching each character row as the beam reaches it.
    /// </summary>
    internal void Tick()
    {
        int line = (CycleInFrame / Trs80Timing.CyclesPerLine) - FirstVisibleLine;
        if (Snow && CycleInFrame % Trs80Timing.CyclesPerLine == 0 && line >= 0 && line < Rows * LinesPerRow)
        {
            // A new frame's scanline starts without the last frame's snow.
            _snow.AsSpan(line * Columns, Columns).Fill(-1);
        }

        if (CycleInFrame % Trs80Timing.CyclesPerLine == 0 && line >= 0 && line % LinesPerRow == 0 && line / LinesPerRow < Rows)
        {
            int row = line / LinesPerRow;
            Array.Copy(_ram, row * Columns, _scanned, row * Columns, Columns);
            _scannedWide[row] = WideCharacters;
        }

        if (++CycleInFrame == Trs80Timing.CyclesPerFrame)
        {
            CycleInFrame = 0;
            Frames++;
        }
    }

    /// <inheritdoc/>
    public void Render(Span<byte> pixels, bool scanned)
    {
        int width = Width;
        if (pixels.Length < width * Height * 4)
        {
            throw new ArgumentException("The pixel buffer is too small.", nameof(pixels));
        }

        Span<uint> output = System.Runtime.InteropServices.MemoryMarshal.Cast<byte, uint>(pixels);
        byte[] source = scanned ? _scanned : _ram;
        for (int row = 0; row < Rows; row++)
        {
            bool wide = scanned ? _scannedWide[row] : WideCharacters;
            for (int line = 0; line < LinesPerRow; line++)
            {
                Span<uint> scan = output.Slice(((row * LinesPerRow) + line) * width, width);
                ReadOnlySpan<short> snow = _snow.AsSpan(((row * LinesPerRow) + line) * Columns, Columns);
                for (int x = 0; x < width; x++)
                {
                    // In 32-character mode each even character spans two cells and each pixel two pixels.
                    int column = wide ? (x / (PixelsPerCharacter * 2)) * 2 : x / PixelsPerCharacter;
                    int pixel = wide ? (x % (PixelsPerCharacter * 2)) / 2 : x % PixelsPerCharacter;
                    byte code = source[(row * Columns) + column];
                    if (scanned && Snow && snow[column] >= 0) { code = (byte)snow[column]; }
                    if (!Lowercase) { code |= (byte)((~code & 0x20) << 1); }
                    scan[x] = Lit(code, line, pixel) ? s_on : s_off;
                }
            }
        }
    }

    // Whether a character cell's pixel is lit.
    private bool Lit(byte code, int line, int pixel)
    {
        if ((code & 0x80) != 0)
        {
            // Blocks: three pixels wide and four lines high.
            int block = ((line / 4) * 2) + (pixel / 3);
            return (code & (1 << block)) != 0;
        }

        return line < 8 && (_characterGenerator[((code & 0x7F) << 3) | line] & (0x20 >> pixel)) != 0;
    }

    private static uint Rgba(byte red, byte green, byte blue) =>
        (uint)(red | (green << 8) | (blue << 16) | (0xFF << 24));
}
