// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Apple2;

/// <summary>
///  IIe NTSC memory scanning and lookup-colour video. Output is 560 by 192 RGBA pixels.
///  Scanner rules are cross-checked against Clock Signal's AppleII/Video.hpp, which documents
///  Sather's Understanding the Apple II/IIe blanking fetches. The DHGR palette and four-bit
///  grouping match Apple2TS ca16c7f487d5980003a2fa87ffc60bbbf3fc8ee3, ui/graphics.ts.
///  This is not a composite NTSC signal decoder.
/// </summary>
/// <remarks>
///  <para>
///   References:
///   <see href="https://github.com/TomHarte/CLK/blob/main/Machines/Apple/AppleII/Video.hpp">Clock Signal scanner</see>,
///   <see href="https://github.com/ct6502/apple2ts/blob/ca16c7f487d5980003a2fa87ffc60bbbf3fc8ee3/src/ui/graphics.ts">Apple2TS lookup renderer</see>.
///  </para>
///  <para>
///   Scanned frames are rolling raster histories: completed cells retain their last fetch until
///   scanned again. HGR uses a six-colour lookup with half-dot delay, not analog colour fringing.
///   Mode changes are sampled at CPU-clock boundaries; sub-cycle propagation is not modeled.
///  </para>
/// </remarks>
public sealed class Apple2Video : IVideoSource
{
    /// <summary>
    ///  Number of CPU clocks in an NTSC frame.
    /// </summary>
    public const int CyclesPerFrame = 65 * 262;

    /// <summary>
    ///  Width in 14 MHz dots, including the half-pixel HGR delay.
    /// </summary>
    public const int Width = 560;

    /// <summary>
    ///  Number of visible scanlines.
    /// </summary>
    public const int Height = 192;

    private readonly Apple2Bus _bus;
    private readonly Apple2Roms _roms;
    private readonly byte[] _main = new byte[40 * Height];
    private readonly byte[] _auxiliary = new byte[40 * Height];
    private readonly Apple2Switches[] _switches = new Apple2Switches[40 * Height];
    private readonly bool[] _flash = new bool[40 * Height];
    private ulong? _fetchCycle;
    private ushort _fetchAddress;
    private byte _floatingBus;

    /// <summary>
    ///  Attaches the scanner to physical RAM and caller-supplied character firmware.
    /// </summary>
    /// <param name="bus">The owning bus.</param>
    /// <param name="roms">The firmware.</param>
    internal Apple2Video(Apple2Bus bus, Apple2Roms roms)
    {
        _bus = bus;
        _roms = roms;
    }

    /// <summary>
    ///  Gets or sets whether the board is an Apple II revision 0, whose hi-res has no half-dot delay: bit 7 of a byte
    ///  is ignored, so hi-res has four colors, black, white, green and violet, and not orange or blue.
    /// </summary>
    public bool Revision0 { get; set; }

    /// <summary>
    ///  Gets the beam position for the next CPU cycle.
    /// </summary>
    public Apple2Beam Beam => new(_bus.Scanline, _bus.ColumnClock, (int)(_bus.CycleCount % CyclesPerFrame));

    /// <summary>
    ///  Gets the physical main/auxiliary address fetched at the current beam position.
    ///  Blanking still fetches RAM, including the repeated first HBL byte and VBL wraparound.
    /// </summary>
    public ushort FetchAddress
    {
        get
        {
            return _fetchCycle == _bus.CycleCount ? _fetchAddress : CurrentFetchAddress(_bus.Scanline, _bus.ColumnClock);
        }
    }

    private ushort CurrentFetchAddress(int scanline, int columnClock)
    {
        int row = scanline;
        int column = columnClock == 0 ? 1 : columnClock;
        if (scanline >= 192) { column -= 8; }
        row = row >= 256 ? 58 + (row & 255) : row % 192;
        int rowOffset = ((row >> 3) & 7) * 128 + (row >> 6) * 40;
        int offset = (rowOffset & ~127) + ((rowOffset + column - 25) & 127);
        Apple2Switches switches = _bus.Switches;
        bool hires = Has(switches, Apple2Switches.HiRes) && !IsText(switches, row);
        int page = Has(switches, Apple2Switches.Page2) && !Has(switches, Apple2Switches.Store80) ? 2 : 1;
        return (ushort)(page * (hires ? 0x2000 : 0x400) + offset + (hires ? (row & 7) * 1024 : 0));
    }

    /// <summary>
    ///  Gets the main-memory byte on the floating bus. Auxiliary data is shifted out first
    ///  in double modes; the main fetch remains the byte visible to a CPU read.
    /// </summary>
    public byte FloatingBus => _fetchCycle == _bus.CycleCount ? _floatingBus : _bus.MainMemory[FetchAddress];

    /// <summary>
    ///  Captures video RAM before the CPU access on the current clock, at most once per clock.
    ///  Does not advance time; Apple2Bus.Tick completes the clock after the CPU access.
    /// </summary>
    public void ScanCycle()
    {
        ulong cycle = _bus.CycleCount;
        if (_fetchCycle == cycle) { return; }

        // The beam, worked out once: the same as Beam's scanline and column clock.
        int columnClock = (int)(cycle % 65);
        int scanline = (int)(cycle / 65 % 262);
        ushort address = CurrentFetchAddress(scanline, columnClock);
        _fetchAddress = address;
        _floatingBus = _bus.MainMemory[address];
        _fetchCycle = cycle;
        if (columnClock < 25 || scanline >= 192) { return; }
        int index = scanline * 40 + columnClock - 25;
        _main[index] = _bus.MainMemory[address];
        _auxiliary[index] = _bus.AuxiliaryMemory[address];
        _switches[index] = _bus.Switches;
        _flash[index] = FlashPhase;
    }

    /// <summary>
    ///  Renders the bytes and switches actually captured at each visible fetch, preserving
    ///  mid-frame memory and mode changes. Unscanned cells initially contain black graphics.
    /// </summary>
    /// <returns>A newly allocated, opaque RGBA image.</returns>
    public byte[] RenderScannedBitmap()
    {
        byte[] pixels = new byte[Width * Height * 4];
        RenderScannedBitmap(pixels);
        return pixels;
    }

    /// <summary>
    ///  Renders a side-effect-free view of current RAM and switches, useful for inspecting
    ///  a graphics page while the CPU is paused. Unlike the scanned image, this is not a raster history.
    /// </summary>
    /// <returns>A newly allocated, opaque RGBA image.</returns>
    public byte[] RenderBitmap()
    {
        byte[] pixels = new byte[Width * Height * 4];
        RenderBitmap(pixels);
        return pixels;
    }

    /// <summary>
    ///  Renders the captured raster into reusable, caller-owned RGBA storage without allocating a frame.
    /// </summary>
    /// <param name="pixels">Exactly 560 * 192 * 4 destination bytes.</param>
    public void RenderScannedBitmap(Span<byte> pixels) => Render(pixels, scanned: true);

    /// <summary>
    ///  Renders current video RAM into reusable, caller-owned RGBA storage without allocating a frame.
    /// </summary>
    /// <param name="pixels">Exactly 560 * 192 * 4 destination bytes.</param>
    public void RenderBitmap(Span<byte> pixels) => Render(pixels, scanned: false);

    /// <inheritdoc/>
    int IVideoSource.Width => Width;

    /// <inheritdoc/>
    int IVideoSource.Height => Height;

    /// <inheritdoc/>
    int IVideoSource.CyclesPerFrame => CyclesPerFrame;

    /// <inheritdoc/>
    void IVideoSource.Render(Span<byte> pixels, bool scanned) => Render(pixels, scanned);

    private bool FlashPhase => (_bus.CycleCount / (65 * 4203)) % 2 != 0;

    private void Render(Span<byte> pixels, bool scanned)
    {
        if (pixels.Length != Width * Height * 4)
        {
            throw new ArgumentException("A 560x192 RGBA destination is required.", nameof(pixels));
        }

        Span<byte> main = stackalloc byte[40];
        Span<byte> auxiliary = stackalloc byte[40];
        Span<Apple2Switches> switches = stackalloc Apple2Switches[40];
        Span<bool> flash = stackalloc bool[40];
        for (int row = 0; row < Height; row++)
        {
            if (scanned)
            {
                _main.AsSpan(row * 40, 40).CopyTo(main);
                _auxiliary.AsSpan(row * 40, 40).CopyTo(auxiliary);
                _switches.AsSpan(row * 40, 40).CopyTo(switches);
                _flash.AsSpan(row * 40, 40).CopyTo(flash);
            }
            else
            {
                Apple2Switches state = _bus.Switches;
                int page = Has(state, Apple2Switches.Page2) && !Has(state, Apple2Switches.Store80) ? 2 : 1;
                bool hires = Has(state, Apple2Switches.HiRes) && !IsText(state, row);
                int address = page * (hires ? 0x2000 : 0x400)
                    + ((row >> 3) & 7) * 128
                    + (row >> 6) * 40
                    + (hires ? (row & 7) * 1024 : 0);

                _bus.MainMemory.Slice(address, 40).CopyTo(main);
                _bus.AuxiliaryMemory.Slice(address, 40).CopyTo(auxiliary);
                switches.Fill(state);
                flash.Fill(FlashPhase);
            }

            RenderLine(pixels.Slice(row * Width * 4, Width * 4), row, main, auxiliary, switches, flash);
        }
    }

    private void RenderLine(
        Span<byte> pixels,
        int row,
        ReadOnlySpan<byte> main,
        ReadOnlySpan<byte> auxiliary,
        ReadOnlySpan<Apple2Switches> switches,
        ReadOnlySpan<bool> flash)
    {
        for (int dot = 0; dot < Width; dot++) { SetPixel(pixels, dot, color: 0); }
        for (int column = 0; column < 40; column++)
        {
            Apple2Switches state = switches[column];
            int start = column * 14;
            bool doubleMode = Has(state, Apple2Switches.Column80) && Has(state, Apple2Switches.DoubleHiRes);
            if (IsText(state, row))
            {
                bool wide = Has(state, Apple2Switches.Column80);
                for (int dot = 0; dot < 14; dot++)
                {
                    int code = wide && dot < 7 ? auxiliary[column] : main[column];
                    if (code is >= 0x40 and < 0x80 && !Has(state, Apple2Switches.AlternateCharacters))
                    {
                        code = (code & 0x3F) | (flash[column] ? 0 : 0x80);
                    }

                    int bit = wide ? dot % 7 : dot / 2;
                    bool lit = ((_roms.Characters[code * 8 + (row & 7)] >> bit) & 1) == 0;
                    SetTextPixel(pixels, start + dot, lit);
                }
            }
            else if (!Has(state, Apple2Switches.HiRes))
            {
                for (int dot = 0; dot < 14; dot++)
                {
                    bool aux = doubleMode && dot < 7;
                    int color = ((aux ? auxiliary[column] : main[column]) >> (row & 4)) & 15;
                    if (aux) { color = ((color << 1) & 15) | (color >> 3); }
                    SetPixel(pixels, start + dot, color);
                }
            }
            else if (doubleMode)
            {
                for (int dot = start; dot < start + 14; dot++)
                {
                    int group = dot & ~3;
                    int value = 0;
                    for (int bit = 0; bit < 4; bit++)
                    {
                        int position = group + bit;
                        int cell = position / 14;
                        int within = position % 14;
                        byte source = within < 7 ? auxiliary[cell] : main[cell];
                        value = (value << 1) | ((source >> (within % 7)) & 1);
                    }

                    int color = (value & 5) | ((value & 2) << 2) | ((value & 8) >> 2);
                    SetPixel(pixels, dot, color);
                }
            }
            else
            {
                for (int dot = 0; dot < 14; dot++)
                {
                    bool delayed = !Revision0 && (main[column] & 128) != 0;
                    int within = dot - (delayed ? 1 : 0);
                    int position = within < 0 ? column * 7 - 1 : column * 7 + within / 2;
                    if (!HiresBit(main, position)) { continue; }
                    if (within < 0 && column != 0) { delayed = !Revision0 && (main[column - 1] & 128) != 0; }
                    bool white = HiresBit(main, position - 1) || HiresBit(main, position + 1);
                    int color = white ? 3 : delayed ? (position & 1) == 0 ? 6 : 5 : (position & 1) == 0 ? 2 : 1;
                    HiresPalette.Slice(color * 4, 4).CopyTo(pixels.Slice((start + dot) * 4, 4));
                }
            }
        }
    }

    private static bool HiresBit(ReadOnlySpan<byte> bytes, int position) =>
        position is >= 0 and < 280 && (bytes[position / 7] & (1 << (position % 7))) != 0;
    private static bool Has(Apple2Switches switches, Apple2Switches flag) => (switches & flag) != 0;
    private static bool IsText(Apple2Switches switches, int row) =>
        Has(switches, Apple2Switches.Text) || (Has(switches, Apple2Switches.Mixed) && row is >= 160 and < 192);

    private static void SetTextPixel(Span<byte> pixels, int position, bool lit)
    {
        Span<byte> pixel = pixels.Slice(position * 4, 4);
        pixel[0] = lit ? (byte)182 : (byte)16;
        pixel[1] = lit ? (byte)243 : (byte)21;
        pixel[2] = lit ? (byte)182 : (byte)16;
        pixel[3] = 255;
    }

    private static void SetPixel(Span<byte> pixels, int position, int color) =>
        Palette.Slice(color * 4, 4).CopyTo(pixels.Slice(position * 4, 4));

    private static ReadOnlySpan<byte> Palette =>
    [
        0,0,0,255, 221,0,51,255, 0,0,153,255, 221,34,221,255,
        0,119,34,255, 85,85,85,255, 34,34,255,255, 102,170,255,255,
        136,85,0,255, 255,102,0,255, 170,170,170,255, 255,153,136,255,
        17,221,0,255, 255,255,0,255, 74,253,197,255, 255,255,255,255
    ];

    private static ReadOnlySpan<byte> HiresPalette =>
    [
        0,0,0,255, 1,255,1,255, 255,1,255,255, 255,255,255,255,
        0,0,0,255, 255,150,1,255, 1,150,255,255, 255,255,255,255
    ];
}