// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Commodore;

/// <summary>
///  The PET 2001's screen: 40 × 25 characters from the 1K of video RAM, drawn from the 2K character ROM.
/// </summary>
/// <remarks>
///  <para>
///   Each byte's bits 0-6 pick one of 128 characters, of 8 rows of 8 dots, the leftmost dot in bit 7; bit 7 of the
///   byte draws it reversed. The VIA's CA2 picks one of the ROM's two sets: low, uppercase and graphics; high, the
///   set with lowercase. PIA 1's CA2 low blanks the screen.
///  </para>
///  <para>
///   On the 2001 the CPU and the display share the video RAM's bus, so a CPU access while the beam draws a line shows
///   the CPU's byte for that character instead, as snow. The editor of BASIC 1 writes only while VIDEO ON is low to
///   avoid it. With <see cref="Snow"/> on, the scanned frame shows it: a line's characters are taken as it starts,
///   and an access in the line's drawn cycles replaces the one under the beam.
///  </para>
/// </remarks>
public sealed class PetVideo : IVideoSource, ICharacterSet
{
    private const int Columns = 40;
    private const int Rows = 25;
    private const int Lines = PetTiming.DisplayLines;

    private readonly byte[] _videoRam;
    private readonly byte[] _characters;
    private readonly byte[] _scanned = new byte[Lines * Columns];
    private readonly byte[] _lineFlags = new byte[Lines];
    private readonly bool _capitalsFirst;

    /// <summary>
    ///  Constructs the video.
    /// </summary>
    /// <param name="videoRam">The 1K of video RAM it shows.</param>
    /// <param name="characters">The 2K character ROM.</param>
    internal PetVideo(byte[] videoRam, ReadOnlySpan<byte> characters)
    {
        _videoRam = videoRam;
        _characters = characters.ToArray();

        // The 2001's 901447-08 has the second set's capitals at $01-$1A, where the 901447-10 has lowercase: there
        // its A is the first set's.
        _capitalsFirst = characters.Slice(0x408, 8).SequenceEqual(characters.Slice(0x008, 8));
    }

    /// <summary>
    ///  Gets or sets the monitor's phosphor.
    /// </summary>
    public PetPhosphor Phosphor { get; set; } = PetPhosphor.White;

    /// <summary>
    ///  Gets or sets whether CPU accesses to video RAM during the display show as snow, as on the 2001's static board.
    /// </summary>
    public bool Snow { get; set; } = true;

    /// <summary>
    ///  Gets whether the character set with lowercase is shown, as the VIA's CA2 chooses.
    /// </summary>
    public bool Lowercase { get; internal set; }

    /// <summary>
    ///  Gets whether the display is on: PIA 1's CA2 high.
    /// </summary>
    public bool Enabled { get; internal set; } = true;

    /// <inheritdoc/>
    public int Width => Columns * 8;

    /// <inheritdoc/>
    public int Height => Lines;

    /// <inheritdoc/>
    public int CyclesPerFrame => PetTiming.CyclesPerFrame;

    /// <inheritdoc/>
    int ICharacterSet.CharacterWidth => 8;

    /// <inheritdoc/>
    int ICharacterSet.CharacterHeight => 8;

    /// <inheritdoc/>
    public void Render(Span<byte> pixels, bool scanned)
    {
        if (pixels.Length != Width * Height * 4)
        {
            throw new ArgumentException("Pixels must be 320×200 RGBA.", nameof(pixels));
        }

        (byte red, byte green, byte blue) = Phosphor == PetPhosphor.Green ? ((byte)0, (byte)0xFF, (byte)0) : ((byte)0xFF, (byte)0xFF, (byte)0xFF);
        for (int y = 0; y < Lines; y++)
        {
            bool lowercase;
            bool enabled;
            ReadOnlySpan<byte> codes;
            if (scanned)
            {
                lowercase = (_lineFlags[y] & 1) != 0;
                enabled = (_lineFlags[y] & 2) != 0;
                codes = _scanned.AsSpan(y * Columns, Columns);
            }
            else
            {
                lowercase = Lowercase;
                enabled = Enabled;
                codes = _videoRam.AsSpan((y >> 3) * Columns, Columns);
            }

            Span<byte> row = pixels.Slice(y * Width * 4, Width * 4);
            for (int column = 0; column < Columns; column++)
            {
                byte code = codes[column];
                int dots = enabled ? Dots(code, y & 7, lowercase) : 0;
                for (int x = 0; x < 8; x++)
                {
                    bool lit = (dots & (0x80 >> x)) != 0;
                    int offset = ((column * 8) + x) * 4;
                    row[offset] = lit ? red : (byte)0;
                    row[offset + 1] = lit ? green : (byte)0;
                    row[offset + 2] = lit ? blue : (byte)0;
                    row[offset + 3] = 0xFF;
                }
            }
        }
    }

    /// <summary>
    ///  Renders a frame from current video RAM.
    /// </summary>
    /// <returns>320×200 RGBA.</returns>
    public byte[] RenderBitmap()
    {
        byte[] pixels = new byte[Width * Height * 4];
        Render(pixels, scanned: false);
        return pixels;
    }

    /// <summary>
    ///  Reads the screen as text, in the uppercase set: bytes <c>$00-$1F</c> as <c>@A-Z[\]↑←</c> (the arrows as
    ///  <c>^</c> and <c>_</c>), <c>$20-$3F</c> as themselves, reversed characters as normal ones, and graphics as
    ///  spaces.
    /// </summary>
    /// <returns>25 lines of 40 characters.</returns>
    public string[] ReadText()
    {
        string[] lines = new string[Rows];
        Span<char> line = stackalloc char[Columns];
        for (int row = 0; row < Rows; row++)
        {
            for (int column = 0; column < Columns; column++)
            {
                int code = _videoRam[(row * Columns) + column] & 0x7F;
                line[column] = code switch
                {
                    < 0x20 => (char)(code + 0x40),
                    < 0x40 => (char)code,
                    _ => ' '
                };
            }

            lines[row] = new string(line);
        }

        return lines;
    }

    /// <inheritdoc/>
    bool ICharacterSet.IsLit(byte code, int line, int pixel, bool flashed) =>
        (Dots(code, line & 7, Lowercase) & (0x80 >> pixel)) != 0;

    /// <inheritdoc/>
    char ICharacterSet.Character(byte code)
    {
        int value = code & 0x7F;
        if (Lowercase)
        {
            return value switch
            {
                0 => '@',
                >= 1 and <= 26 => (char)((_capitalsFirst ? 'A' : 'a') + value - 1),
                >= 0x1B and < 0x20 => "[\\]^_"[value - 0x1B],
                < 0x40 => (char)value,
                >= 0x41 and <= 0x5A => (char)((_capitalsFirst ? 'a' : 'A') + value - 0x41),
                _ => '\0'
            };
        }

        return value switch
        {
            < 0x20 => (char)(value + 0x40),
            < 0x40 => (char)value,
            _ => '\0'
        };
    }

    /// <summary>
    ///  Takes a displayed line's characters and modes as the beam starts it.
    /// </summary>
    /// <param name="line">The line, 0-199.</param>
    internal void StartLine(int line)
    {
        _videoRam.AsSpan((line >> 3) * Columns, Columns).CopyTo(_scanned.AsSpan(line * Columns, Columns));
        _lineFlags[line] = (byte)((Lowercase ? 1 : 0) | (Enabled ? 2 : 0));
    }

    /// <summary>
    ///  Shows the CPU's byte in place of the character under the beam, for an access to video RAM while a line is
    ///  drawn.
    /// </summary>
    /// <param name="line">The line, 0-199.</param>
    /// <param name="column">The column under the beam, 0-39.</param>
    /// <param name="value">The byte on the bus.</param>
    internal void ShowSnow(int line, int column, byte value)
    {
        if (Snow) { _scanned[(line * Columns) + column] = value; }
    }

    private int Dots(byte code, int row, bool lowercase) =>
        _characters[((lowercase ? 1 : 0) << 10) | ((code & 0x7F) << 3) | row] ^ ((code & 0x80) != 0 ? 0xFF : 0);
}
