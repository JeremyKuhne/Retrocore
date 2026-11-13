// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Runtime.InteropServices;

namespace Retrocore.Machines.Coco;

/// <summary>
///  The CoCo 3's video from the GIME: the CoCo 1 and 2's VDG modes through the palette, and its own text (32 to 80
///  columns, with attributes) and graphics (16 to 160 bytes a row, 2, 4 or 16 colors).
/// </summary>
/// <remarks>
///  <para>
///   A field is 262 lines of 114 time units. The active area is 192, 200 or 225 lines (<c>$FF99</c> bits 6-5),
///   after 25, 23 or 8 lines of top border. HS goes low for the last 8 units of each line; FS falls at line 244,
///   in the bottom border, and rises when the field ends. The vertical border interrupt marks the end of the active
///   area and the horizontal one each line.
///  </para>
///  <para>
///   Each active line is captured as it starts: the GIME's video registers, PIA 1's VDG mode bits, the SAM's mode,
///   the line within its character row, and the bytes it shows. Colors are the palette's 6-bit values, shown as a
///   composite or an RGB monitor would show them. The frame is 640 dots wide inside a border; the compatible modes'
///   256 dots are doubled.
///  </para>
/// </remarks>
public sealed class Coco3Video : IVideoSource
{
    private const int MaximumLines = 225;
    private const int MaximumBytes = 160;
    private const int BorderX = 32;
    private const int BorderY = 12;
    private const int FieldSyncLine = 244;
    private const int HsyncLowUnit = CocoTiming.UnitsPerLine - 8;

    private static readonly uint[] s_composite =
    [
        0x000000, 0x004c00, 0x004300, 0x0a3100, 0x2f1b00, 0x550100, 0x6c0000, 0x770006,
        0x71004b, 0x5c008b, 0x3b00b8, 0x1100ca, 0x001499, 0x002c62, 0x004011, 0x004b00,
        0x2d2d2d, 0x069800, 0x288f00, 0x537d00, 0x786700, 0xa04c00, 0xb63402, 0xc3224c,
        0xbd1693, 0xa814d5, 0x881cfe, 0x5e2cff, 0x105ee9, 0x0076b2, 0x008b60, 0x009618,
        0x747474, 0x41d714, 0x62cf00, 0x8ebd00, 0xb4a700, 0xdd8c01, 0xf5733a, 0xfe6085,
        0xfd53ce, 0xe950ff, 0xc958ff, 0x9e67ff, 0x4e9aff, 0x36b3f7, 0x26c9a3, 0x2bd558,
        0xfdfdfe, 0x88e85a, 0xa1e03f, 0xbed238, 0xd8c342, 0xf1b161, 0xfea08d, 0xfe95bf,
        0xfd8ef1, 0xef8eff, 0xd895ff, 0xb9a1ff, 0x86c4ff, 0x78d4f2, 0x71e2b6, 0xffffff
    ];

    private readonly CocoBus _bus;
    private readonly CocoGime _gime;
    private readonly bool _rgb;
    private readonly LineState[] _lines = new LineState[MaximumLines];
    private readonly byte[] _lineBytes = new byte[MaximumLines * MaximumBytes];
    private int _unit;
    private int _line;
    private int _position;
    private int _lineInRow;

    /// <summary>
    ///  Builds the video for a bus.
    /// </summary>
    /// <param name="bus">The bus, for RAM, the SAM and PIA 1.</param>
    /// <param name="gime">The GIME.</param>
    /// <param name="rgb">Whether the monitor is the RGB one rather than composite.</param>
    internal Coco3Video(CocoBus bus, CocoGime gime, bool rgb)
    {
        _bus = bus;
        _gime = gime;
        _rgb = rgb;
        HorizontalSync = true;
        FieldSync = true;
    }

    /// <inheritdoc/>
    public int Width => 640 + (2 * BorderX);

    /// <inheritdoc/>
    public int Height => MaximumLines + (2 * BorderY);

    /// <inheritdoc/>
    public int CyclesPerFrame => CocoTiming.CyclesPerFrame;

    /// <summary>
    ///  Gets the HS level; low during horizontal sync.
    /// </summary>
    public bool HorizontalSync { get; private set; }

    /// <summary>
    ///  Gets the FS level; low from line 244 until the field ends.
    /// </summary>
    public bool FieldSync { get; private set; }

    /// <summary>
    ///  Gets the line the beam is on, 0-261.
    /// </summary>
    public int Line => _line;

    /// <summary>
    ///  Gets the fields completed since power on.
    /// </summary>
    public long Fields { get; private set; }

    /// <summary>
    ///  Gets whether the screen shows text: the compatible mode's alphanumerics or the GIME's text modes.
    /// </summary>
    public bool IsText => _gime.CompatibleVideo
        ? (_bus.VideoMode & 0x80) == 0
        : (_gime.VideoMode & 0x80) == 0;

    /// <summary>
    ///  Gets the active lines: 192, 200 or 225.
    /// </summary>
    public int ActiveLines => (_gime.VideoResolution & 0x60) switch
    {
        0x20 => 200,
        0x60 => 225,
        _ => 192
    };

    private int FirstActiveLine => ActiveLines switch
    {
        200 => 23,
        225 => 8,
        _ => 25
    };

    /// <summary>
    ///  Reads the text screen as characters, for the debugger: the compatible mode's 32 x 16, or the GIME's 32, 40,
    ///  64 or 80 columns.
    /// </summary>
    /// <returns>The rows.</returns>
    public string[] TextRows()
    {
        int start = _gime.VideoBase(_bus.Sam.DisplayOffset);
        if (_gime.CompatibleVideo)
        {
            string[] rows = new string[16];
            Span<char> line = stackalloc char[32];
            for (int row = 0; row < rows.Length; row++)
            {
                for (int column = 0; column < 32; column++)
                {
                    line[column] = CocoVideo.Character(_bus.PhysicalRead(start + (row * 32) + column));
                }

                rows[row] = line.ToString();
            }

            return rows;
        }

        int columns = Columns(_gime.VideoResolution);
        bool attributes = (_gime.VideoResolution & 1) != 0;
        int linesPerRow = LinesPerRow(_gime.VideoMode, legacy: false, 0, 0, 0);
        int rowCount = linesPerRow is 0 or > 225 ? 1 : Math.Max(1, ActiveLines / linesPerRow);
        string[] text = new string[rowCount];
        char[] buffer = new char[columns];
        int stride = columns * (attributes ? 2 : 1);
        for (int row = 0; row < rowCount; row++)
        {
            for (int column = 0; column < columns; column++)
            {
                byte value = _bus.PhysicalRead(start + (row * stride) + (column * (attributes ? 2 : 1)));
                char character = (char)(value & 0x7F);
                buffer[column] = character is >= ' ' and < (char)0x7F ? character : ' ';
            }

            text[row] = new string(buffer);
        }

        return text;
    }

    /// <summary>
    ///  Advances the beam, raising the GIME's border interrupts and counting its timer.
    /// </summary>
    /// <param name="units">Time units.</param>
    internal void Tick(int units)
    {
        bool lineStarted = false;
        for (int unit = 0; unit < units; unit++)
        {
            if (++_unit == CocoTiming.UnitsPerLine)
            {
                _unit = 0;
                NextLine();
                lineStarted = true;
            }
            else if (_unit == HsyncLowUnit)
            {
                HorizontalSync = false;
                _gime.Raise(CocoGime.HorizontalBorderInterrupt);
            }
        }

        _gime.Tick(units, lineStarted);
    }

    /// <summary>
    ///  Restarts the beam at the top of a field.
    /// </summary>
    internal void Reset()
    {
        _unit = 0;
        _line = 0;
        _lineInRow = 0;
        _position = _gime.VideoBase(_bus.Sam.DisplayOffset);
        HorizontalSync = true;
        FieldSync = true;
    }

    /// <inheritdoc/>
    public void Render(Span<byte> pixels, bool scanned)
    {
        Span<uint> output = MemoryMarshal.Cast<byte, uint>(pixels);
        Span<uint> palette = stackalloc uint[16];
        for (int index = 0; index < 16; index++) { palette[index] = Color(_gime.Palette(index)); }

        uint border = Color(_gime.CompatibleVideo ? (byte)0 : _gime.Border);
        output.Fill(border);

        int active = ActiveLines;
        int top = BorderY + ((MaximumLines - active) / 2);
        Span<byte> bytes = stackalloc byte[MaximumBytes];
        LineState live = default;
        int position = _gime.VideoBase(_bus.Sam.DisplayOffset);
        int lineInRow = 0;
        for (int line = 0; line < active; line++)
        {
            LineState state;
            if (scanned)
            {
                state = _lines[line];
                _lineBytes.AsSpan(line * MaximumBytes, MaximumBytes).CopyTo(bytes);
            }
            else
            {
                live = Capture(position, lineInRow);
                state = live;
                Fetch(state, bytes);
                Advance(state, ref position, ref lineInRow);
            }

            Span<uint> row = output.Slice(((top + line) * Width) + BorderX, 640);
            if (state.Legacy) { RenderLegacy(row, state, bytes, palette); }
            else if ((state.Mode & 0x80) != 0) { RenderGraphics(row, state, bytes, palette); }
            else { RenderText(row, state, bytes, palette); }
        }
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
            _position = _gime.VideoBase(_bus.Sam.DisplayOffset);
            _lineInRow = 0;
        }
        else if (_line == FieldSyncLine)
        {
            FieldSync = false;
        }

        int active = _line - FirstActiveLine;
        if (active == ActiveLines)
        {
            _gime.Raise(CocoGime.VerticalBorderInterrupt);
        }

        if ((uint)active < (uint)ActiveLines && active < MaximumLines)
        {
            LineState state = Capture(_position, _lineInRow);
            _lines[active] = state;
            Fetch(state, _lineBytes.AsSpan(active * MaximumBytes, MaximumBytes));
            Advance(state, ref _position, ref _lineInRow);
        }
    }

    private LineState Capture(int position, int lineInRow) => new()
    {
        Legacy = _gime.CompatibleVideo,
        Mode = _gime.VideoMode,
        Resolution = _gime.VideoResolution,
        VdgMode = _bus.VideoMode,
        SamMode = (byte)_bus.Sam.VideoMode,
        VerticalScroll = _gime.VerticalScroll,
        HorizontalOffset = _gime.HorizontalOffset,
        Position = position,
        LineInRow = (byte)lineInRow,
        Blink = _gime.Blink
    };

    // The bytes the line shows, at the row's address plus the horizontal offset, wrapping within 256 bytes.
    private void Fetch(LineState state, Span<byte> bytes)
    {
        int count = BytesPerRow(state);
        int offset = state.Legacy ? 0 : (state.HorizontalOffset & 0x7F) * 2;
        for (int index = 0; index < count && index < bytes.Length; index++)
        {
            int address = offset == 0
                ? state.Position + index
                : (state.Position & ~0xFF) | ((state.Position + offset + index) & 0xFF);

            bytes[index] = _bus.PhysicalRead(address);
        }
    }

    private static void Advance(LineState state, ref int position, ref int lineInRow)
    {
        int linesPerRow = LinesPerRow(state.Mode, state.Legacy, state.VdgMode, state.SamMode, state.VerticalScroll);
        if (linesPerRow == 0) { return; }
        if (++lineInRow >= linesPerRow)
        {
            lineInRow = 0;
            position += !state.Legacy && (state.HorizontalOffset & 0x80) != 0 ? 256 : BytesPerRow(state);
        }
    }

    private static int BytesPerRow(LineState state)
    {
        if (state.Legacy)
        {
            return (state.VdgMode & 0x80) != 0 && (state.SamMode & 1) != 0 ? 16 : 32;
        }

        if ((state.Mode & 0x80) != 0)
        {
            return ((state.Resolution >> 2) & 7) switch
            {
                0 => 16,
                1 => 20,
                2 => 32,
                3 => 40,
                4 => 64,
                5 => 80,
                6 => 128,
                _ => 160
            };
        }

        return Columns(state.Resolution) * ((state.Resolution & 1) != 0 ? 2 : 1);
    }

    private static int Columns(byte resolution) => (resolution & 0x14) switch
    {
        0x04 => 40,
        0x10 => 64,
        0x14 => 80,
        _ => 32
    };

    // Lines per character row: the compatible graphics modes repeat rows as the SAM's mode says, compatible text
    // takes $FF9C's count, and the GIME's own modes take $FF98's. Zero means rows never advance.
    private static int LinesPerRow(byte mode, bool legacy, byte vdgMode, byte samMode, byte scroll)
    {
        if (legacy)
        {
            if ((vdgMode & 0x80) != 0)
            {
                return samMode switch
                {
                    0 or 1 or 2 => 3,
                    3 or 4 => 2,
                    _ => 1
                };
            }

            return (scroll & 0x0F) switch
            {
                0 => 11,
                1 => 10,
                2 => 9,
                3 => 8,
                4 => 7,
                5 => 6,
                6 => 5,
                7 => 4,
                8 => 3,
                9 => 2,
                10 => 1,
                11 => 4,
                12 => 3,
                13 => 2,
                14 => 1,
                _ => 12
            };
        }

        return (mode & 7) switch
        {
            0 or 1 => 1,
            2 => 2,
            3 => 8,
            4 => 9,
            5 => 10,
            6 => 11,
            _ => 0
        };
    }

    // The VDG modes through the palette: 4-color graphics use entries 0-3 or 4-7, 2-color 8-9 or 10-11, text
    // 12-13 or 14-15, and semigraphics 0-7 on entry 8; the GIME's lowercase acts as the MC6847T1's.
    private static void RenderLegacy(Span<uint> row, LineState state, ReadOnlySpan<byte> bytes, ReadOnlySpan<uint> palette)
    {
        bool css = (state.VdgMode & 0x08) != 0;
        if ((state.VdgMode & 0x80) != 0)
        {
            int graphicsMode = (state.VdgMode >> 4) & 7;
            bool color = (graphicsMode & 1) == 0;
            int bytesPerLine = graphicsMode is 0 or 1 or 3 or 5 ? 16 : 32;
            int pixels = color ? bytesPerLine * 4 : bytesPerLine * 8;
            int width = 512 / pixels;
            int x = 64;
            for (int index = 0; index < bytesPerLine; index++)
            {
                byte value = bytes[index];
                if (color)
                {
                    for (int shift = 6; shift >= 0; shift -= 2)
                    {
                        row.Slice(x, width).Fill(palette[(css ? 4 : 0) + ((value >> shift) & 3)]);
                        x += width;
                    }
                }
                else
                {
                    for (int bit = 7; bit >= 0; bit--)
                    {
                        row.Slice(x, width).Fill(palette[(css ? 10 : 8) + ((value >> bit) & 1)]);
                        x += width;
                    }
                }
            }

            return;
        }

        int cellRow = state.LineInRow;
        ReadOnlySpan<byte> font = GimeCharacterSet.LowResolution;
        for (int column = 0; column < 32; column++)
        {
            byte value = bytes[column];
            Span<uint> cell = row.Slice(64 + (column * 16), 16);
            if ((value & 0x80) != 0)
            {
                int element = cellRow < 6 ? 3 : 1;
                uint on = palette[(value >> 4) & 7];
                cell[..8].Fill((value & (1 << element)) != 0 ? on : palette[8]);
                cell[8..].Fill((value & (1 << (element - 1))) != 0 ? on : palette[8]);
                continue;
            }

            int code = value & 0x3F;
            bool inverse = (value & 0x40) != 0;
            byte pattern = cellRow < 12 ? font[(code * 12) + cellRow] : (byte)0;
            if (!inverse && (state.VdgMode & 0x10) != 0 && code < 32)
            {
                pattern = cellRow < 12 ? (byte)~font[((code + 64) * 12) + cellRow] : (byte)0xFF;
            }

            if ((state.VdgMode & 0x20) != 0) { inverse = !inverse; }
            if (inverse) { pattern = (byte)~pattern; }
            uint background = palette[css ? 14 : 12];
            uint foreground = palette[css ? 15 : 13];
            for (int dot = 0; dot < 8; dot++)
            {
                uint pixel = (pattern & (0x80 >> dot)) != 0 ? foreground : background;
                cell[dot * 2] = pixel;
                cell[(dot * 2) + 1] = pixel;
            }
        }
    }

    // Text: a character byte, then with attributes an attribute byte (bit 7 blink, 6 underline, 5-3 the
    // foreground's entry 8-15, 2-0 the background's entry 0-7).
    private static void RenderText(Span<uint> row, LineState state, ReadOnlySpan<byte> bytes, ReadOnlySpan<uint> palette)
    {
        int columns = Columns(state.Resolution);
        bool attributes = (state.Resolution & 1) != 0;
        int width = 640 / columns / 8;
        int underlineLine = (state.Mode & 7) switch
        {
            3 => 7,
            4 or 5 => 8,
            6 => 9,
            _ => -1
        };

        ReadOnlySpan<byte> font = GimeCharacterSet.HighResolution;
        for (int column = 0; column < columns; column++)
        {
            byte character = bytes[column * (attributes ? 2 : 1)];
            byte attribute = attributes ? bytes[(column * 2) + 1] : (byte)0x08;
            if ((attribute & 0x80) != 0 && state.Blink) { character = 0x20; }
            uint background = palette[attributes ? attribute & 7 : 0];
            uint foreground = palette[attributes ? 8 + ((attribute >> 3) & 7) : 1];
            int line = state.LineInRow;
            byte pattern = line < 8 ? font[((character & 0x7F) * 8) + line] : (byte)0;
            if ((attribute & 0x40) != 0 && line == underlineLine) { pattern = 0xFF; }
            Span<uint> cell = row.Slice(column * 8 * width, 8 * width);
            for (int dot = 0; dot < 8; dot++)
            {
                cell.Slice(dot * width, width).Fill((pattern & (0x80 >> dot)) != 0 ? foreground : background);
            }
        }
    }

    // Graphics: 1, 2 or 4 bits a dot ($FF99 bits 1-0), most significant first, each a palette entry.
    private static void RenderGraphics(Span<uint> row, LineState state, ReadOnlySpan<byte> bytes, ReadOnlySpan<uint> palette)
    {
        int bits = (state.Resolution & 3) switch
        {
            0 => 1,
            1 => 2,
            _ => 4
        };

        int bytesPerRow = BytesPerRow(state);
        int dots = bytesPerRow * 8 / bits;
        int width = Math.Max(1, 640 / dots);
        int mask = (1 << bits) - 1;
        int x = 0;
        for (int index = 0; index < bytesPerRow && x < 640; index++)
        {
            byte value = bytes[index];
            for (int shift = 8 - bits; shift >= 0 && x < 640; shift -= bits)
            {
                row.Slice(x, Math.Min(width, 640 - x)).Fill(palette[(value >> shift) & mask]);
                x += width;
            }
        }
    }

    // A 6-bit color as the monitor shows it: RGB takes bits 5 and 2 as red, 4 and 1 as green, 3 and 0 as blue.
    private uint Color(byte color)
    {
        uint rgb = _rgb
            ? (uint)((((((color >> 4) & 2) | ((color >> 2) & 1)) * 0x55) << 16)
                | (((((color >> 3) & 2) | ((color >> 1) & 1)) * 0x55) << 8)
                | ((((color >> 2) & 2) | (color & 1)) * 0x55))
            : s_composite[color & 0x3F];

        return 0xFF000000 | ((rgb & 0xFF) << 16) | (rgb & 0xFF00) | ((rgb >> 16) & 0xFF);
    }
}
