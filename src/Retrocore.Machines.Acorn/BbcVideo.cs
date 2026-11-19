// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Chips;

namespace Retrocore.Machines.Acorn;

/// <summary>
///  The BBC Micro's video: the 6845 addresses RAM and times the picture, and the video ULA turns each byte into pixels
///  through its palette, or passes the SAA5050's teletext through.
/// </summary>
/// <remarks>
///  <para>
///   The ULA's control register (<c>$FE20</c>): bit 0 chooses which of each flashing colour pair shows, bit 1
///   selects teletext, bits 2-3 the pixel rate (2, 4, 8 or 16 MHz: 10, 20, 40 or 80 characters a line), bit 4 the
///   6845's clock (1 or 2 MHz), and bits 5-7 the cursor's width. Its palette (<c>$FE21</c>) maps the 16 logical
///   colours: the high nibble picks one, the low nibble is the physical colour with its bits 0-2 inverted, and bit 3
///   makes it flash, showing the colour itself instead while control bit 0 is set.
///  </para>
///  <para>
///   Each pixel's logical colour is bits 7, 5, 3 and 1 of the byte; then the byte shifts left, a 1 coming in. So a
///   byte holds eight 2-colour pixels, four 4-colour ones or two 16-colour ones, and the operating system programs
///   all the palette entries each mode's pixels can reach. Raster lines 8-15 of a row are blank, the gaps between
///   modes 3 and 6's text rows.
///  </para>
///  <para>
///   The address: in modes 0-6 the 6845's MA0-MA11 are address bits 3-14 and its raster line bits 0-2. When the
///   screen runs past <c>$7FFF</c> (MA12 high), an adder on MA8-MA11 adds 12K, 16K, 22K or 24K, as the addressable
///   latch's C0 and C1 choose, to bring it back into the screen's memory: hardware scrolling. MA13 high selects
///   teletext addressing, <c>$3C00</c> or <c>$7C00</c> up, the adder choosing which.
///  </para>
///  <para>
///   The frame is 704 × 576: 44 µs of each line from 13 µs after the horizontal sync starts, at 16 pixels a
///   microsecond, and 288 lines from the 16th after the vertical sync starts, each two pixels high. Interlaced fields
///   draw alternate pixel rows; otherwise a line fills both. The operating system's modes start their picture 15 µs
///   and 32 lines after the syncs, so its 40 µs by 256 lines (250 in mode 7) sits inside a border.
///  </para>
/// </remarks>
public sealed class BbcVideo : IVideoSource
{
    /// <summary>
    ///  The frame's width in pixels: 44 µs at 16 MHz.
    /// </summary>
    internal const int FrameWidth = 704;

    /// <summary>
    ///  The frame's height in pixels: 288 lines, two rows each.
    /// </summary>
    internal const int FrameHeight = 576;

    private const int FirstCycle = 26;
    private const int FirstLine = 16;

    // The characters teletext's data lags its address by, through the latch and the SAA5050: three, as beebjit's
    // pipeline has it, which the MOS's mode 7 cursor matches with a cursor skew of 2 and the cursor's segment 1.
    private const int TeletextDelay = 3;

    // The control register's bit for each character of the cursor, from the 6845's cursor output: segment 0 (bit 7)
    // the first, segment 1 (bit 6) the second, and segment 2 (bit 5) the third and fourth.
    private static readonly int[] s_cursorSegments = [0x80, 0x40, 0x20, 0x20];

    private readonly byte[] _ram;
    private readonly int _ramMask;
    private readonly byte[] _scanned = new byte[FrameWidth * FrameHeight * 4];
    private readonly byte[] _palette = new byte[16];
    private readonly byte[] _colours = new byte[16];
    private BbcTeletext _teletext;
    private BbcBeam _beam;

    /// <summary>
    ///  Creates the video.
    /// </summary>
    /// <param name="ram">RAM, which the 6845 addresses.</param>
    /// <param name="characters">The SAA5050's character ROM.</param>
    internal BbcVideo(byte[] ram, ReadOnlySpan<byte> characters)
    {
        _ram = ram;
        _ramMask = ram.Length - 1;
        _teletext = new(characters);
        _beam = new() { Pixels = _scanned };
        for (int index = 0; index < _scanned.Length; index += 4) { _scanned[index + 3] = 0xFF; }
        for (int index = 0; index < 16; index++) { _colours[index] = 7; }
    }

    /// <summary>
    ///  Gets the 6845.
    /// </summary>
    public Crtc6845 Crtc { get; } = new();

    /// <summary>
    ///  Gets the video ULA's control register.
    /// </summary>
    public byte Control { get; private set; }

    /// <summary>
    ///  Gets the screen wrap, the addressable latch's C0 (bit 0) and C1 (bit 1).
    /// </summary>
    public int ScreenWrap { get; internal set; }

    /// <summary>
    ///  Gets whether the 6845 runs at 2 MHz (modes 0-3) rather than 1 MHz.
    /// </summary>
    public bool FastClock => (Control & 0x10) != 0;

    /// <summary>
    ///  Gets whether the ULA shows the teletext chip's output.
    /// </summary>
    public bool Teletext => (Control & 0x02) != 0;

    /// <inheritdoc/>
    public int Width => FrameWidth;

    /// <inheritdoc/>
    public int Height => FrameHeight;

    /// <inheritdoc/>
    public int CyclesPerFrame => BbcTiming.CyclesPerFrame;

    /// <summary>
    ///  Gets a palette entry as written: the physical colour, inverted, in bits 0-2, and bit 3 to flash.
    /// </summary>
    /// <param name="logical">The logical colour, 0-15.</param>
    /// <returns>The entry.</returns>
    public byte Palette(int logical) => _palette[logical];

    /// <summary>
    ///  Gets the physical colour a logical colour shows now: bit 0 red, bit 1 green, bit 2 blue.
    /// </summary>
    /// <param name="logical">The logical colour, 0-15.</param>
    /// <returns>The colour.</returns>
    public int PhysicalColour(int logical) => _colours[logical];

    /// <summary>
    ///  Gets the RAM address the 6845's address and raster line select, through the wrap-around adder.
    /// </summary>
    /// <param name="address">The 6845's 14-bit address.</param>
    /// <param name="line">The raster line.</param>
    /// <returns>The RAM address.</returns>
    public int ScreenAddress(int address, int line)
    {
        // The adder's B inputs come from NAND gates of C0, C1 and MA12; with MA12 low they are all high, and with the
        // carry in the sum is MA8-MA11 unchanged. Its A inputs are MA8-MA11; the sum is address bits 11-14.
        int c0 = ScreenWrap & 1;
        int c1 = (ScreenWrap >> 1) & 1;
        int ma12 = (address >> 12) & 1;
        int b1 = ~(c1 & c0 & ma12) & 1;
        int b3 = ~(c0 & ma12) & 1;
        int b2 = ~(c1 & b3 & ma12) & 1;
        int b4 = ~(b3 & ma12) & 1;
        int sum = (((address >> 8) & 0x0F) + (b1 | (b2 << 1) | (b3 << 2) | (b4 << 3)) + 1) & 0x0F;

        int result = (address & 0x2000) != 0
            ? 0x3C00 | (address & 0x3FF) | ((sum & 8) << 11)
            : ((address & 0xFF) << 3) | (sum << 11) | (line & 7);

        return result & _ramMask;
    }

    /// <inheritdoc/>
    public void Render(Span<byte> pixels, bool scanned)
    {
        if (pixels.Length != _scanned.Length)
        {
            throw new ArgumentException("Pixels must be 704×576 RGBA.", nameof(pixels));
        }

        if (scanned)
        {
            _scanned.CopyTo(pixels);
            return;
        }

        // Draw a whole frame, both fields if interlaced, from copies of the 6845 and the teletext chip.
        // Opaque black where the beam does not reach, as the scanned frame starts.
        byte[] frame = new byte[_scanned.Length];
        for (int index = 3; index < frame.Length; index += 4) { frame[index] = 0xFF; }
        Crtc6845 crtc = Crtc.Clone();
        BbcTeletext teletext = _teletext.Clone();
        BbcBeam beam = new() { Pixels = frame };
        int fields = 0;
        bool sync = crtc.VerticalSync;
        for (int cycle = 0; cycle < BbcTiming.CyclesPerFrame * 3 && fields < 3; cycle++)
        {
            beam.Cycle++;
            if (!FastClock && (cycle & 1) == 0) { continue; }
            crtc.Tick();
            Draw(ref beam, crtc, teletext);
            if (crtc.VerticalSync && !sync) { fields++; }
            sync = crtc.VerticalSync;
        }

        frame.CopyTo(pixels);
    }

    /// <summary>
    ///  Renders the scanned frame.
    /// </summary>
    /// <returns>704×576 RGBA.</returns>
    public byte[] RenderBitmap()
    {
        byte[] pixels = new byte[_scanned.Length];
        Render(pixels, scanned: true);
        return pixels;
    }

    /// <summary>
    ///  Writes the ULA's control register (<paramref name="register"/> even) or its palette (odd).
    /// </summary>
    /// <param name="register">The register select.</param>
    /// <param name="value">The value.</param>
    internal void Write(int register, byte value)
    {
        if ((register & 1) == 0)
        {
            Control = value;
        }
        else
        {
            _palette[value >> 4] = (byte)(value & 0x0F);
        }

        for (int logical = 0; logical < 16; logical++)
        {
            byte entry = _palette[logical];
            _colours[logical] = (byte)(((entry & 8) != 0 && (Control & 1) != 0 ? entry : entry ^ 7) & 7);
        }
    }

    /// <summary>
    ///  Advances one 2 MHz cycle: the 6845 steps when its clock does, and the beam draws its character.
    /// </summary>
    /// <param name="phase">Whether this is the second half of a 1 MHz cycle, when the slow 6845 clock ticks.</param>
    /// <returns>Whether the 6845 stepped.</returns>
    internal bool Tick(bool phase)
    {
        _beam.Cycle++;
        if (!FastClock && !phase) { return false; }
        Crtc.Tick();
        Draw(ref _beam, Crtc, _teletext);
        return true;
    }

    private void Draw(ref BbcBeam beam, Crtc6845 crtc, BbcTeletext teletext)
    {
        bool horizontal = crtc.HorizontalSync;
        if (horizontal && !beam.HorizontalSync)
        {
            beam.Cycle = 0;
            beam.Line++;
            beam.Clear();
        }

        beam.HorizontalSync = horizontal;

        bool vertical = crtc.VerticalSync;
        if (vertical && !beam.VerticalSync)
        {
            beam.Line = -FirstLine;
            teletext.StartField();
        }

        beam.VerticalSync = vertical;
        beam.OddField = crtc.OddField;
        beam.Interlaced = crtc.Interlaced;

        // The skews let the picture lag the address while the byte goes through the latches and, for teletext, the
        // SAA5050: the address, raster line and display enable go down the same pipeline, as long as the path's delay.
        // Teletext's is the hardware's own three characters, which the MOS's mode 7 cursor matches with its skew of 2
        // and segment 1, so turning the cursor off (skew 3) does not move the text; the graphics path lags as long as
        // the display skew.
        beam.Push(crtc.Address, crtc.RowAddress, crtc.Displayed);
        // A display skew of 3 is no delay with the display off; teletext's own delay of 3 is a delay.
        int skew = Teletext ? TeletextDelay : crtc.DisplaySkew == 3 ? 0 : crtc.DisplaySkew;
        (int address, int line, bool display) = beam.Delayed(skew);
        if (crtc.DisplaySkew == 3) { display = false; }
        if (display && !beam.Display) { teletext.StartLine(); }
        beam.Display = display;

        // The cursor's four characters start with the 6845's cursor output; the control register picks which show.
        if (crtc.Cursor) { beam.CursorLeft = s_cursorSegments.Length; }
        bool cursor = false;
        if (beam.CursorLeft > 0)
        {
            cursor = (Control & s_cursorSegments[s_cursorSegments.Length - beam.CursorLeft]) != 0;
            beam.CursorLeft--;
        }

        int width = FastClock ? 8 : 16;
        int x = (beam.Cycle - FirstCycle) * 8;
        Span<byte> row = beam.Row(x, width);

        if (Teletext)
        {
            int code = display ? _ram[ScreenAddress(address, line)] & 0x7F : 0x40;
            ushort dots = teletext.Character(code, (line & 1) != 0);
            int foreground = teletext.Foreground ^ (cursor ? 7 : 0);
            int background = teletext.Background ^ (cursor ? 7 : 0);
            if (row.IsEmpty) { return; }
            for (int pixel = 0; pixel < width; pixel++)
            {
                int half = 11 - (pixel * 12 / width);
                int colour = !display ? 0 : (dots & (1 << half)) != 0 ? foreground : background;
                Put(row, pixel, colour);
            }

            return;
        }

        if (row.IsEmpty) { return; }
        if (!display)
        {
            for (int pixel = 0; pixel < width; pixel++) { Put(row, pixel, 0); }
            return;
        }

        int data = (line & 8) != 0 ? -1 : _ram[ScreenAddress(address, line)];

        // A pixel lasts 8, 4, 2 or 1 of the frame's 16 MHz pixels at 2, 4, 8 or 16 MHz.
        int span = 8 >> ((Control >> 2) & 3);
        for (int pixel = 0; pixel < width; pixel += span)
        {
            int colour = data < 0
                ? 0
                : _colours[((data >> 4) & 8) | ((data >> 3) & 4) | ((data >> 2) & 2) | ((data >> 1) & 1)];

            if (cursor) { colour ^= 7; }
            for (int dot = 0; dot < span && pixel + dot < width; dot++) { Put(row, pixel + dot, colour); }
            if (data >= 0) { data = ((data << 1) | 1) & 0xFF; }
        }
    }

    private static void Put(Span<byte> row, int pixel, int colour)
    {
        int offset = pixel * 4;
        row[offset] = (colour & 1) != 0 ? (byte)0xFF : (byte)0;
        row[offset + 1] = (colour & 2) != 0 ? (byte)0xFF : (byte)0;
        row[offset + 2] = (colour & 4) != 0 ? (byte)0xFF : (byte)0;
        row[offset + 3] = 0xFF;
    }
}
