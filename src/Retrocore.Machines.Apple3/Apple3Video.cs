// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Apple3;

/// <summary>
///  The Apple III's video: three text modes and four native graphics modes, on each of two pages, with a
///  128-character set in RAM.
/// </summary>
/// <remarks>
///  <para>
///   <c>$C050-$C057</c> set four switches, GR/TEXT, MIX, PG2 and HIRES (<see cref="Apple3Bus.VideoSwitches"/> bits
///   0-3), which choose the mode as the Service Reference Manual's truth table (6.24) has it. Without HIRES or MIX,
///   40-column text, in color with GR set; with MIX, 80-column text. With HIRES, 280×192 black and white, or with
///   GR a color byte per 7 dots; with HIRES and MIX, 560×192 black and white, or with GR 140×192 in 16 colors.
///  </para>
///  <para>
///   Text is in the system bank (page 1 <c>$0400</c>, page 2 <c>$0800</c>), graphics in bank 0 (seen at
///   <c>$2000-$9FFF</c>). Where two pages are used together, as color text's characters and colors or the 80-column
///   and 560-dot modes' alternate bytes, page 2 swaps or moves them as the manual (6.2-6.8) describes; MAME's page 2
///   differs for the three color and 560-dot graphics modes.
///  </para>
///  <para>
///   Characters $00-$7F show inverse, or, where a glyph row's bit 7 is set, flash; $80-$FF show normally. Color text
///   needs VIA 1's PA6, which Apple II emulation clears. Smooth scrolling moves graphics lines within each group of
///   eight by <see cref="Apple3Bus.ScrollOffset"/>. With <c>$C0DB</c> on, the character set loads from the screen
///   holes as vertical blanking ends, as MAME does: a hole on page 2 names the character and the hole on page 1 below
///   it holds the row.
///  </para>
///  <para>
///   The colors are MAME's, which differ between text and graphics.
///  </para>
/// </remarks>
public sealed class Apple3Video : IVideoSource
{
    private const int Lines = 192;

    // Four bits each of red, green and blue: text colors, then graphics colors.
    private static readonly ushort[] s_palette =
    [
        0x000, 0x505, 0x009, 0xD2D, 0x072, 0xAAA, 0x22F, 0x6AF,
        0x850, 0xF60, 0x555, 0xF9F, 0x1D0, 0xEE0, 0x4ED, 0xFFF,
        0x000, 0xD03, 0x009, 0xD2D, 0x072, 0x555, 0x22F, 0x6AF,
        0x850, 0xF60, 0xAAA, 0xF98, 0x1D0, 0xFF0, 0x4F9, 0xFFF
    ];

    private static readonly int[] s_screenHoles = [0x478, 0x4F8, 0x578, 0x5F8, 0x678, 0x6F8, 0x778, 0x7F8];

    private readonly Apple3Bus _bus;
    private readonly byte[] _characters = new byte[128 * 8];
    private readonly Apple3VideoLine[] _lines = new Apple3VideoLine[Lines];
    private int _frames;

    /// <summary>
    ///  Constructs the video for a bus.
    /// </summary>
    /// <param name="bus">The bus whose memory and switches it shows.</param>
    public Apple3Video(Apple3Bus bus) => _bus = bus;

    /// <summary>
    ///  Gets the frame width: 560 dots, so 40-column and 280-dot modes draw each dot twice.
    /// </summary>
    public int Width => 560;

    /// <summary>
    ///  Gets the frame height.
    /// </summary>
    public int Height => Lines;

    /// <summary>
    ///  Gets the frame's length in 1 MHz cycles, 65 a line; at 2 MHz the CPU runs more.
    /// </summary>
    public int CyclesPerFrame => 65 * 262;

    /// <summary>
    ///  Gets the character set: 128 characters of 8 rows, dots in bits 0-6 from the left, bit 7 to flash.
    /// </summary>
    public Span<byte> CharacterRam => _characters;

    /// <summary>
    ///  Gets the frames counted so far; flashing characters change every 16.
    /// </summary>
    public int Frames => _frames;

    /// <inheritdoc/>
    public void Render(Span<byte> pixels, bool scanned)
    {
        if (pixels.Length != Width * Height * 4)
        {
            throw new ArgumentException("Pixels must be 560×192 RGBA.", nameof(pixels));
        }

        Apple3VideoLine now = Capture();
        for (int y = 0; y < Lines; y++)
        {
            RenderLine(pixels.Slice(y * Width * 4, Width * 4), y, scanned ? _lines[y] : now);
        }
    }

    /// <summary>
    ///  Renders a frame from current memory and switches.
    /// </summary>
    /// <returns>560×192 RGBA.</returns>
    public byte[] RenderBitmap()
    {
        byte[] pixels = new byte[Width * Height * 4];
        Render(pixels, scanned: false);
        return pixels;
    }

    /// <summary>
    ///  Notes the switches as the beam starts a visible line, for <see cref="Render"/> of what was scanned.
    /// </summary>
    /// <param name="line">The line, 0-191.</param>
    internal void StartLine(int line) => _lines[line] = Capture();

    /// <summary>
    ///  Ends vertical blanking: loads the character set from the screen holes when <c>$C0DB</c> asks, and counts the
    ///  frame.
    /// </summary>
    internal void EndVerticalBlank()
    {
        _frames++;
        if (!_bus.CharacterWrite) { return; }
        ReadOnlySpan<byte> ram = _bus.Ram;
        int system = ram.Length - 0x8000;
        for (int i = 0; i < s_screenHoles.Length; i++)
        {
            int hole = system + s_screenHoles[i];
            for (int j = 0; j < 4; j++)
            {
                _characters[(((ram[hole + 0x400 + j] & 0x7F) * 8) + ((i & 3) * 2)) & 0x3FF] = ram[hole + j];
                _characters[(((ram[hole + 0x404 + j] & 0x7F) * 8) + ((i & 3) * 2) + 1) & 0x3FF] = ram[hole + 4 + j];
            }
        }
    }

    private Apple3VideoLine Capture() => new(
        _bus.VideoSwitches,
        (byte)(_bus.SmoothScroll ? _bus.ScrollOffset : 0),
        (_bus.Environment & Apple3Bus.VideoEnable) != 0,
        (_bus.BankRegister & 0x40) != 0);

    private void RenderLine(Span<byte> line, int y, Apple3VideoLine state)
    {
        if (!state.VideoOn)
        {
            line.Clear();
            return;
        }

        bool gr = (state.Switches & 1) != 0;
        bool mix = (state.Switches & 2) != 0;
        bool page2 = (state.Switches & 4) != 0;
        bool hires = (state.Switches & 8) != 0;
        ReadOnlySpan<byte> ram = _bus.Ram;
        if (!hires)
        {
            int system = ram.Length - 0x8000;
            int text = system + TextRow(y >> 3);
            int glyphRow = y & 7;
            int primary = text + (page2 ? 0x800 : 0x400);
            int secondary = text + (page2 ? 0x400 : 0x800);
            if (mix)
            {
                for (int x = 0; x < 40; x++)
                {
                    Glyph(line, x * 14, ram[primary + x], glyphRow, wide: false, 15, 0);
                    Glyph(line, (x * 14) + 7, ram[secondary + x], glyphRow, wide: false, 15, 0);
                }
            }
            else
            {
                bool color = gr && state.ColorText;
                for (int x = 0; x < 40; x++)
                {
                    byte colors = color ? ram[secondary + x] : (byte)0xF0;
                    Glyph(line, x * 14, ram[primary + x], glyphRow, wide: true, colors >> 4, colors & 0x0F);
                }
            }

            return;
        }

        int ly = (y & ~7) | (((y & 7) + state.Scroll) & 7);
        int row = HiresRow(ly);
        if (!mix)
        {
            // 280 dots: black and white from one page, or with a color byte per 7 dots from the other.
            int dots = row + (page2 ? 0x2000 : 0);
            int colors = row + (page2 ? 0 : 0x2000);
            for (int x = 0; x < 40; x++)
            {
                byte b = ram[dots + x];
                int on = gr ? 16 + (ram[colors + x] >> 4) : 15;
                int off = gr ? 16 + (ram[colors + x] & 0x0F) : 0;
                for (int bit = 0; bit < 7; bit++)
                {
                    int index = ((b >> bit) & 1) != 0 ? on : off;
                    Put(line, (x * 14) + (bit * 2), index);
                    Put(line, (x * 14) + (bit * 2) + 1, index);
                }
            }

            return;
        }

        int first = row + (page2 ? 0x4000 : 0);
        int second = row + (page2 ? 0x6000 : 0x2000);
        if (!gr)
        {
            // 560 dots: 7 from the primary byte, then 7 from the secondary.
            for (int x = 0; x < 40; x++)
            {
                for (int bit = 0; bit < 7; bit++)
                {
                    Put(line, (x * 14) + bit, ((ram[first + x] >> bit) & 1) != 0 ? 15 : 0);
                    Put(line, (x * 14) + 7 + bit, ((ram[second + x] >> bit) & 1) != 0 ? 15 : 0);
                }
            }

            return;
        }

        // 140 dots in 16 colors: four bytes, primary and secondary alternately, hold seven 4-bit dots.
        for (int x = 0; x < 20; x++)
        {
            int bits = (ram[first + (2 * x)] & 0x7F)
                | ((ram[second + (2 * x)] & 0x7F) << 7)
                | ((ram[first + (2 * x) + 1] & 0x7F) << 14)
                | ((ram[second + (2 * x) + 1] & 0x7F) << 21);

            for (int dot = 0; dot < 7; dot++)
            {
                int index = 16 + ((bits >> (dot * 4)) & 0x0F);
                for (int i = 0; i < 4; i++) { Put(line, (x * 28) + (dot * 4) + i, index); }
            }
        }
    }

    private void Glyph(Span<byte> line, int x, byte character, int glyphRow, bool wide, int foreground, int background)
    {
        byte dots = _characters[((character & 0x7F) * 8) + glyphRow];
        bool flashOn = ((_frames >> 4) & 1) != 0;
        bool inverse = (character & 0x80) == 0 && ((dots & 0x80) == 0 || flashOn);
        for (int bit = 0; bit < 7; bit++)
        {
            bool lit = ((dots >> bit) & 1) != 0;
            int index = lit != inverse ? foreground : background;
            if (wide)
            {
                Put(line, x + (bit * 2), index);
                Put(line, x + (bit * 2) + 1, index);
            }
            else
            {
                Put(line, x + bit, index);
            }
        }
    }

    // A text row's offset in a page: the II's interleave, rows 0-7, 8-15 and 16-23 sharing each 128-byte block.
    private static int TextRow(int row) => ((row & 7) << 7) + ((row >> 3) * 40);

    // A hi-res line's offset in bank 0, for page 1 at $2000.
    private static int HiresRow(int line) => ((line & 7) << 10) + (((line >> 3) & 7) << 7) + ((line >> 6) * 40);

    private static void Put(Span<byte> line, int x, int index)
    {
        ushort color = s_palette[index];
        int offset = x * 4;
        line[offset] = (byte)(((color >> 8) & 0x0F) * 17);
        line[offset + 1] = (byte)(((color >> 4) & 0x0F) * 17);
        line[offset + 2] = (byte)((color & 0x0F) * 17);
        line[offset + 3] = 0xFF;
    }
}
