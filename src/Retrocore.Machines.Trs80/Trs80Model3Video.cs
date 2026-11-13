// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Runtime.InteropServices;

namespace Retrocore.Machines.Trs80;

/// <summary>
///  The Model III family's video: 64x16 characters of 8x12 pixels, or on a Model 4 80x24 characters of 8x10, each
///  with a wide mode that shows every other character twice as wide.
/// </summary>
/// <remarks>
///  <para>
///   Video RAM is 1K on a Model III and 2K on a Model 4. The 64x16 display shows the first 1K; the Model 4's CPU
///   sees either 1K page at <c>$3C00</c>, chosen by port <c>$84</c> bit 7, or all 2K at <c>$F800</c> in memory map
///   2. The 80x24 display shows 1,920 bytes from the start address in its 6845's registers 12 and 13.
///  </para>
///  <para>
///   Codes <c>$80</c>-<c>$BF</c> are 2x3 block graphics. Codes <c>$C0</c>-<c>$FF</c> are the character generator's
///   special characters, or with the alternate set (port <c>$EC</c> bit 3) the ones at <c>$80</c>-<c>$BF</c>.
///   Inverse video (port <c>$84</c> bit 3) instead shows codes from <c>$80</c> as their low seven bits inverted.
///  </para>
/// </remarks>
public sealed class Trs80Model3Video : IVideoSource
{
    /// <summary>
    ///  Pixels per character.
    /// </summary>
    public const int PixelsPerCharacter = 8;

    private static readonly uint s_on = Rgba(0xF0, 0xF0, 0xF0);
    private static readonly uint s_off = Rgba(0x10, 0x10, 0x10);

    private readonly byte[] _ram;
    private readonly byte[] _scanned;
    private readonly byte[] _characterGenerator;
    private readonly bool _model4;

    // The modes each character row was drawn in, for the scanned picture.
    private readonly (bool Eighty, bool Wide, bool Alternate, bool Inverse, int Start)[] _scannedModes =
        new (bool, bool, bool, bool, int)[24];

    private int _register;

    /// <summary>
    ///  Creates the video.
    /// </summary>
    /// <param name="characterGenerator">The 2K character generator.</param>
    /// <param name="model4">Whether it is a Model 4's, with 2K of RAM and the 80x24 mode.</param>
    internal Trs80Model3Video(ReadOnlyMemory<byte> characterGenerator, bool model4)
    {
        _characterGenerator = characterGenerator.ToArray();
        _model4 = model4;
        _ram = new byte[model4 ? 0x800 : 0x400];
        _scanned = new byte[_ram.Length];
    }

    /// <summary>
    ///  Gets or sets whether the display shows 80x24 rather than 64x16 (port <c>$84</c> bit 2, Model 4 only).
    /// </summary>
    public bool Eighty { get; set; }

    /// <summary>
    ///  Gets or sets whether the display shows every other character twice as wide (port <c>$EC</c> bit 2).
    /// </summary>
    public bool WideCharacters { get; set; }

    /// <summary>
    ///  Gets or sets whether codes <c>$C0</c>-<c>$FF</c> show the alternate characters (port <c>$EC</c> bit 3).
    /// </summary>
    public bool AlternateCharacters { get; set; }

    /// <summary>
    ///  Gets or sets whether codes from <c>$80</c> show inverted (port <c>$84</c> bit 3, Model 4 only).
    /// </summary>
    public bool Inverse { get; set; }

    /// <summary>
    ///  Gets or sets which 1K page the CPU sees at <c>$3C00</c> (port <c>$84</c> bit 7, Model 4 only).
    /// </summary>
    public int Page { get; set; }

    /// <summary>
    ///  Gets the 80x24 display's start address in video RAM, from its 6845's registers 12 and 13.
    /// </summary>
    public int StartAddress { get; private set; }

    /// <summary>
    ///  Gets the T-state within the frame.
    /// </summary>
    public int CycleInFrame { get; private set; }

    /// <summary>
    ///  Gets the frames completed.
    /// </summary>
    public ulong Frames { get; private set; }

    /// <summary>
    ///  Gets the columns the display shows now.
    /// </summary>
    public int Columns => (Eighty ? 80 : 64) / (WideCharacters ? 2 : 1);

    /// <summary>
    ///  Gets the character rows the display shows now.
    /// </summary>
    public int Rows => Eighty ? 24 : 16;

    /// <inheritdoc/>
    public int Width => _model4 ? 640 : 512;

    /// <inheritdoc/>
    public int Height => _model4 ? 240 : 192;

    /// <inheritdoc/>
    public int CyclesPerFrame => Trs80Model3Timing.CyclesPerFrame;

    /// <summary>
    ///  Reads video RAM.
    /// </summary>
    /// <param name="offset">The offset into all of video RAM.</param>
    /// <returns>The byte.</returns>
    public byte Read(int offset) => _ram[offset & (_ram.Length - 1)];

    /// <summary>
    ///  Writes video RAM.
    /// </summary>
    /// <param name="offset">The offset into all of video RAM.</param>
    /// <param name="value">The byte.</param>
    public void Write(int offset, byte value) => _ram[offset & (_ram.Length - 1)] = value;

    /// <summary>
    ///  Gets the byte the display shows at a character position of the current mode, before wide mode.
    /// </summary>
    /// <param name="row">The row.</param>
    /// <param name="column">The column, 0-63 or 0-79.</param>
    /// <returns>The code.</returns>
    public byte Displayed(int row, int column) => Eighty
        ? Read(StartAddress + (row * 80) + column)
        : Read((row * 64) + column);

    /// <summary>
    ///  Writes the 6845's address (<paramref name="data"/> false) or data register; only the start address, in
    ///  registers 12 and 13, changes the picture, as the rest are fixed by the Model 4's circuit.
    /// </summary>
    /// <param name="data">Whether the data register is written.</param>
    /// <param name="value">The value.</param>
    internal void CrtcWrite(bool data, byte value)
    {
        if (!data)
        {
            _register = value & 0x1F;
            return;
        }

        if (_register == 12) { StartAddress = ((value & 0x3F) << 8) | (StartAddress & 0xFF); }
        else if (_register == 13) { StartAddress = (StartAddress & 0x3F00) | value; }
    }

    /// <summary>
    ///  Advances the beam one device T-state, latching each character row as the beam reaches it.
    /// </summary>
    internal void Tick()
    {
        if (CycleInFrame % Trs80Model3Timing.CyclesPerLine == 0)
        {
            int lines = Eighty ? 10 : 12;
            int first = (Trs80Model3Timing.LinesPerFrame - (Rows * lines)) / 2;
            int line = (CycleInFrame / Trs80Model3Timing.CyclesPerLine) - first;
            if (line == 0) { Array.Copy(_ram, _scanned, _ram.Length); }
            if (line >= 0 && line % lines == 0 && line / lines < Rows)
            {
                _scannedModes[line / lines] = (Eighty, WideCharacters, AlternateCharacters, Inverse, StartAddress);
            }
        }

        if (++CycleInFrame == Trs80Model3Timing.CyclesPerFrame)
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

        Span<uint> output = MemoryMarshal.Cast<byte, uint>(pixels)[..(width * Height)];
        output.Fill(s_off);
        bool eighty = scanned ? _scannedModes[0].Eighty : Eighty;
        int rows = eighty ? 24 : 16;
        int lines = eighty ? 10 : 12;
        int columns = eighty ? 80 : 64;

        // The 64x16 picture is centered on a Model 4's 80x24 screen.
        int left = (width - (columns * PixelsPerCharacter)) / 2;
        int top = (Height - (rows * lines)) / 2;
        byte[] source = scanned ? _scanned : _ram;
        for (int row = 0; row < rows; row++)
        {
            (bool _, bool wide, bool alternate, bool inverse, int start) = scanned
                ? _scannedModes[row]
                : (eighty, WideCharacters, AlternateCharacters, Inverse, StartAddress);

            int rowStart = eighty ? start + (row * 80) : row * 64;
            for (int line = 0; line < lines; line++)
            {
                Span<uint> scan = output.Slice(((top + (row * lines) + line) * width) + left, columns * PixelsPerCharacter);
                for (int x = 0; x < scan.Length; x++)
                {
                    int column = wide ? (x / (PixelsPerCharacter * 2)) * 2 : x / PixelsPerCharacter;
                    int pixel = wide ? (x % (PixelsPerCharacter * 2)) / 2 : x % PixelsPerCharacter;
                    byte code = source[(rowStart + column) & (source.Length - 1)];
                    scan[x] = Lit(code, line, pixel, alternate, inverse) ? s_on : s_off;
                }
            }
        }
    }

    // Whether a character cell's pixel is lit.
    private bool Lit(byte code, int line, int pixel, bool alternate, bool inverse)
    {
        if (code >= 0xC0 && !inverse)
        {
            int glyph = alternate ? code & 0xBF : code;
            return line < 8 && (_characterGenerator[(glyph << 3) | line] & (0x80 >> pixel)) != 0;
        }

        if (code >= 0x80 && !inverse)
        {
            // Blocks: four pixels wide and four lines high.
            int block = (Math.Min(line / 4, 2) * 2) + (pixel / 4);
            return (code & (1 << block)) != 0;
        }

        bool lit = line < 8 && (_characterGenerator[((code & 0x7F) << 3) | line] & (0x80 >> pixel)) != 0;
        return inverse && code >= 0x80 ? !lit : lit;
    }

    private static uint Rgba(byte red, byte green, byte blue) =>
        (uint)(red | (green << 8) | (blue << 16) | (0xFF << 24));
}
