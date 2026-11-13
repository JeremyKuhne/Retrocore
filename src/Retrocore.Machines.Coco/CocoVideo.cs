// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Runtime.InteropServices;

namespace Retrocore.Machines.Coco;

/// <summary>
///  The CoCo 1 and 2's video: the MC6847 (or MC6847T1) VDG fed by the SAM's address generator, with the
///  horizontal and field sync it sends PIA 0.
/// </summary>
/// <remarks>
///  <para>
///   A field is 262 lines of 114 time units: 25 lines of top border, 192 active lines, then bottom border and
///   retrace. HS goes low for the last 8 units of each line. FS is high until the last active line (216) starts and
///   low until the field ends.
///  </para>
///  <para>
///   Each active line is captured as it starts: the VDG's mode (PIA 1's port B), the SAM's mode and the 32 bytes
///   at the SAM's address. The SAM counts from its display offset, holding each row of 16 or 32 bytes (as its mode
///   clears 3 or 4 low bits at HS) for 12, 3, 2 or 1 lines; the VDG reads 16 or 32 bytes of it as its own mode
///   needs. A frame mixes modes line by line as the hardware does, though a change within a line takes effect at
///   the next.
///  </para>
/// </remarks>
public sealed class CocoVideo : IVideoSource
{
    /// <summary>
    ///  The first active line.
    /// </summary>
    public const int FirstActiveLine = 25;

    /// <summary>
    ///  The active lines.
    /// </summary>
    public const int ActiveLines = 192;

    /// <summary>
    ///  The line field sync falls on.
    /// </summary>
    public const int FieldSyncLine = FirstActiveLine + ActiveLines - 1;

    private const int HsyncLowUnit = CocoTiming.UnitsPerLine - 8;
    private const int BorderX = 32;
    private const int BorderY = 24;

    // PIA 1 port B bits: CSS, GM0 (INT/EXT), GM1, GM2, A/G.
    private const byte ColorSetBit = 0x08;
    private const byte GraphicsMode0Bit = 0x10;
    private const byte GraphicsMode1Bit = 0x20;
    private const byte AlphaGraphicsBit = 0x80;

    private static readonly uint[] s_palette =
    [
        Rgb(0x30, 0xD2, 0x00), // 0 green
        Rgb(0xC1, 0xE5, 0x00), // 1 yellow
        Rgb(0x4C, 0x3A, 0xB4), // 2 blue
        Rgb(0x9A, 0x32, 0x36), // 3 red
        Rgb(0xBF, 0xC8, 0xAD), // 4 buff
        Rgb(0x41, 0xAF, 0x71), // 5 cyan
        Rgb(0xC8, 0x4E, 0xF0), // 6 magenta
        Rgb(0xD4, 0x7F, 0x00), // 7 orange
        Rgb(0x26, 0x30, 0x16), // 8 graphics black
        Rgb(0x00, 0x7C, 0x00), // 9 alphanumeric dark green
        Rgb(0x6B, 0x27, 0x00), // 10 alphanumeric dark orange
        Rgb(0xFF, 0xB7, 0x00), // 11 alphanumeric bright orange
        Rgb(0x00, 0x00, 0x00), // 12 border black
        Rgb(0x26, 0x5C, 0xF0), // 13 artifact blue
        Rgb(0xE6, 0x6A, 0x16)  // 14 artifact red
    ];

    private readonly CocoBus _bus;
    private readonly bool _t1;
    private readonly CocoArtifactColors _artifacts;
    private readonly byte[] _lineBytes = new byte[ActiveLines * 32];
    private readonly byte[] _lineMode = new byte[ActiveLines];
    private int _unit;
    private int _line;
    private int _counter;
    private int _rowLine;

    /// <summary>
    ///  Builds the video for a bus.
    /// </summary>
    /// <param name="bus">The bus, for RAM, the SAM and PIA 1.</param>
    /// <param name="lowercase">Whether the VDG is the MC6847T1.</param>
    /// <param name="artifacts">The artifact colors of 256-dot two-color graphics.</param>
    internal CocoVideo(CocoBus bus, bool lowercase, CocoArtifactColors artifacts)
    {
        _bus = bus;
        _t1 = lowercase;
        _artifacts = artifacts;
        HorizontalSync = true;
        FieldSync = true;
    }

    /// <inheritdoc/>
    public int Width => 256 + (2 * BorderX);

    /// <inheritdoc/>
    public int Height => ActiveLines + (2 * BorderY);

    /// <inheritdoc/>
    public int CyclesPerFrame => CocoTiming.CyclesPerFrame;

    /// <summary>
    ///  Gets the HS level; low during horizontal sync.
    /// </summary>
    public bool HorizontalSync { get; private set; }

    /// <summary>
    ///  Gets the FS level; low from the last active line until the field ends.
    /// </summary>
    public bool FieldSync { get; private set; }

    /// <summary>
    ///  Gets the line the beam is on, 0-261, the first active line being 25.
    /// </summary>
    public int Line => _line;

    /// <summary>
    ///  Gets the time unit within the line, 0-113.
    /// </summary>
    public int UnitInLine => _unit;

    /// <summary>
    ///  Gets the fields completed since power on.
    /// </summary>
    public long Fields { get; private set; }

    /// <summary>
    ///  Gets whether the VDG shows alphanumerics and semigraphics rather than a graphics mode.
    /// </summary>
    public bool IsText => (_bus.VideoMode & AlphaGraphicsBit) == 0;

    /// <summary>
    ///  Advances the beam.
    /// </summary>
    /// <param name="units">Time units, 1 for a fast cycle and 2 for a slow one.</param>
    internal void Tick(int units)
    {
        for (int unit = 0; unit < units; unit++)
        {
            if (++_unit == CocoTiming.UnitsPerLine)
            {
                _unit = 0;
                NextLine();
            }
            else if (_unit == HsyncLowUnit)
            {
                HorizontalSync = false;
            }
        }
    }

    /// <summary>
    ///  Restarts the beam at the top of a field, as power on does.
    /// </summary>
    internal void Reset()
    {
        _unit = 0;
        _line = 0;
        _counter = _bus.Sam.DisplayOffset;
        _rowLine = 0;
        HorizontalSync = true;
        FieldSync = true;
    }

    /// <summary>
    ///  Reads the 32 x 16 text screen at the SAM's display offset as characters, for the debugger: alphanumerics as
    ///  ASCII, inverse ones lowercase, and semigraphics as spaces.
    /// </summary>
    /// <returns>Sixteen rows of 32 characters.</returns>
    public string[] TextRows()
    {
        string[] rows = new string[16];
        Span<char> line = stackalloc char[32];
        int start = _bus.Sam.DisplayOffset;
        for (int row = 0; row < rows.Length; row++)
        {
            for (int column = 0; column < 32; column++)
            {
                byte value = _bus.VideoRead(start + (row * 32) + column);
                line[column] = Character(value);
            }

            rows[row] = line.ToString();
        }

        return rows;
    }

    /// <summary>
    ///  Gets the character a screen byte shows: its 6-bit code in ASCII, lowercase when inverse; a space for
    ///  semigraphics.
    /// </summary>
    /// <param name="value">The screen byte.</param>
    /// <returns>The character.</returns>
    public static char Character(byte value)
    {
        if ((value & 0x80) != 0) { return ' '; }
        int code = value & 0x3F;
        char ascii = (char)(code < 32 ? code + 64 : code);
        return (value & 0x40) == 0 && char.IsAsciiLetterUpper(ascii) ? char.ToLowerInvariant(ascii) : ascii;
    }

    /// <inheritdoc/>
    public void Render(Span<byte> pixels, bool scanned)
    {
        Span<uint> output = MemoryMarshal.Cast<byte, uint>(pixels);
        int width = Width;
        Span<byte> bytes = stackalloc byte[32];
        byte currentMode = _bus.VideoMode;
        int counter = _bus.Sam.DisplayOffset;
        int rowLine = 0;
        for (int line = 0; line < ActiveLines; line++)
        {
            byte mode;
            if (scanned)
            {
                mode = _lineMode[line];
                _lineBytes.AsSpan(line * 32, 32).CopyTo(bytes);
            }
            else
            {
                mode = currentMode;
                FetchLine(ref counter, ref rowLine, bytes);
            }

            Span<uint> row = output.Slice((line + BorderY) * width, width);
            uint border = BorderColor(mode);
            row[..BorderX].Fill(border);
            row[(BorderX + 256)..].Fill(border);
            RenderLine(row.Slice(BorderX, 256), mode, bytes, line);
        }

        uint frameBorder = BorderColor(scanned ? _lineMode[^1] : currentMode);
        output[..(BorderY * width)].Fill(frameBorder);
        output[((BorderY + ActiveLines) * width)..].Fill(frameBorder);
    }

    private void NextLine()
    {
        HorizontalSync = true;
        if (++_line == CocoTiming.LinesPerField)
        {
            _line = 0;
            Fields++;
        }

        if (_line == 0)
        {
            FieldSync = true;
            _counter = _bus.Sam.DisplayOffset;
            _rowLine = 0;
        }
        else if (_line == FieldSyncLine)
        {
            FieldSync = false;
        }

        int active = _line - FirstActiveLine;
        if ((uint)active < ActiveLines)
        {
            _lineMode[active] = _bus.VideoMode;
            FetchLine(ref _counter, ref _rowLine, _lineBytes.AsSpan(active * 32, 32));
        }
    }

    // The SAM's mode picks the row width (16 or 32 bytes) and how many lines repeat a row.
    private void FetchLine(ref int counter, ref int rowLine, Span<byte> bytes)
    {
        int samMode = _bus.Sam.VideoMode;
        for (int index = 0; index < bytes.Length; index++)
        {
            bytes[index] = _bus.VideoRead(counter + index);
        }

        int linesPerRow = samMode switch
        {
            0 => 12,
            1 or 2 => 3,
            3 or 4 => 2,
            _ => 1
        };

        if (++rowLine >= linesPerRow)
        {
            rowLine = 0;
            counter += samMode is 1 or 3 or 5 ? 16 : 32;
        }
    }

    private static uint BorderColor(byte mode) => (mode & AlphaGraphicsBit) == 0
        ? s_palette[12]
        : s_palette[(mode & ColorSetBit) != 0 ? 4 : 0];

    private void RenderLine(Span<uint> row, byte mode, ReadOnlySpan<byte> bytes, int line)
    {
        bool css = (mode & ColorSetBit) != 0;
        if ((mode & AlphaGraphicsBit) != 0)
        {
            RenderGraphics(row, (mode >> 4) & 7, css, bytes, _artifacts);
            return;
        }

        bool intExt = (mode & GraphicsMode0Bit) != 0;
        int cellRow = line % 12;
        for (int column = 0; column < 32; column++)
        {
            byte value = bytes[column];
            Span<uint> cell = row.Slice(column * 8, 8);
            if ((value & 0x80) != 0 && (_t1 || !intExt))
            {
                // Semigraphics 4: four elements in bits 3-0, the color in bits 6-4.
                int element = cellRow < 6 ? 3 : 1;
                uint on = s_palette[(value >> 4) & 7];
                cell[..4].Fill((value & (1 << element)) != 0 ? on : s_palette[12]);
                cell[4..].Fill((value & (1 << (element - 1))) != 0 ? on : s_palette[12]);
            }
            else if ((value & 0x80) != 0)
            {
                // Semigraphics 6: six elements in bits 5-0, the color in bits 7-6 and CSS.
                int element = cellRow < 4 ? 5 : cellRow < 8 ? 3 : 1;
                uint on = s_palette[((value >> 6) & 3) + (css ? 4 : 0)];
                cell[..4].Fill((value & (1 << element)) != 0 ? on : s_palette[12]);
                cell[4..].Fill((value & (1 << (element - 1))) != 0 ? on : s_palette[12]);
            }
            else
            {
                RenderCharacter(cell, value, mode, css, cellRow);
            }
        }
    }

    private void RenderCharacter(Span<uint> cell, byte value, byte mode, bool css, int cellRow)
    {
        int code = value & 0x3F;
        bool inverse = (value & 0x40) != 0;
        ReadOnlySpan<byte> font = _t1 ? CocoCharacterSet.Mc6847T1 : CocoCharacterSet.Mc6847;
        byte pattern;
        if (_t1 && !inverse && (mode & GraphicsMode0Bit) != 0 && code < 32)
        {
            // The MC6847T1 shows codes 0-31 as its lowercase, dark on light.
            pattern = (byte)~font[((code + 64) * 12) + cellRow];
        }
        else
        {
            pattern = font[(code * 12) + cellRow];
        }

        if (_t1 && (mode & GraphicsMode1Bit) != 0) { inverse = !inverse; }
        if (inverse) { pattern = (byte)~pattern; }

        uint background = s_palette[css ? 10 : 9];
        uint foreground = css ? s_palette[11] : s_palette[0];
        for (int dot = 0; dot < 8; dot++)
        {
            cell[dot] = (pattern & (0x80 >> dot)) != 0 ? foreground : background;
        }
    }

    private static void RenderGraphics(
        Span<uint> row,
        int graphicsMode,
        bool css,
        ReadOnlySpan<byte> bytes,
        CocoArtifactColors artifacts)
    {
        if (graphicsMode == 7 && css && artifacts != CocoArtifactColors.None)
        {
            RenderArtifacts(row, bytes, artifacts);
            return;
        }

        // CG1, RG1, CG2, RG2, CG3, RG3, CG6 and RG6: even modes are four-color, odd ones two-color.
        bool color = (graphicsMode & 1) == 0;
        int bytesPerLine = graphicsMode is 0 or 1 or 3 or 5 ? 16 : 32;
        int pixelsPerLine = color ? bytesPerLine * 4 : bytesPerLine * 8;
        int dotWidth = 256 / pixelsPerLine;
        int set = css ? 4 : 0;
        uint off = s_palette[8];
        uint on = s_palette[css ? 4 : 0];
        int x = 0;
        for (int index = 0; index < bytesPerLine; index++)
        {
            byte value = bytes[index];
            if (color)
            {
                for (int shift = 6; shift >= 0; shift -= 2)
                {
                    row.Slice(x, dotWidth).Fill(s_palette[set + ((value >> shift) & 3)]);
                    x += dotWidth;
                }
            }
            else
            {
                for (int bit = 7; bit >= 0; bit--)
                {
                    row.Slice(x, dotWidth).Fill((value & (1 << bit)) != 0 ? on : off);
                    x += dotWidth;
                }
            }
        }
    }

    // Each pair of dots shows black, buff, or one of two artifact colors on a composite monitor.
    private static void RenderArtifacts(Span<uint> row, ReadOnlySpan<byte> bytes, CocoArtifactColors artifacts)
    {
        uint litDark = s_palette[artifacts == CocoArtifactColors.BlueRed ? 13 : 14];
        uint darkLit = s_palette[artifacts == CocoArtifactColors.BlueRed ? 14 : 13];
        for (int index = 0; index < 32; index++)
        {
            byte value = bytes[index];
            for (int shift = 6; shift >= 0; shift -= 2)
            {
                uint color = ((value >> shift) & 3) switch
                {
                    0 => s_palette[8],
                    1 => darkLit,
                    2 => litDark,
                    _ => s_palette[4]
                };

                int x = (index * 8) + 6 - shift;
                row[x] = color;
                row[x + 1] = color;
            }
        }
    }

    private static uint Rgb(byte red, byte green, byte blue) =>
        (uint)(red | (green << 8) | (blue << 16) | (0xFF << 24));
}
