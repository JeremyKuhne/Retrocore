// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Atari;

/// <summary>
///  GTIA (CO14805), or the CTIA before it: the colours, the four players and four missiles, their priorities and
///  collisions, the console keys, the speaker and the joystick triggers.
/// </summary>
/// <remarks>
///  <para>
///   Behaviour follows the Altirra Hardware Reference Manual, chapter 6. GTIA draws two colour clocks a machine cycle
///   from the playfield codes ANTIC leaves in <see cref="Playfield"/>, over the visible clocks <c>$22-$DD</c> of
///   scan lines 8-247, into a 376 × 240 frame: two pixels a colour clock, so high-resolution modes keep their half
///   clocks.
///  </para>
///  <para>
///   Priority is the manual's gate logic (6.7), so the unofficial <c>PRIOR</c> combinations mix and black out as the
///   chip does. A write to a position or size register takes effect three colour clocks after the cycle that wrote
///   it, and to a graphics register one clock after, as section 6.10 times them. Other writes take effect from the
///   next cycle's two clocks: a colour change shows a clock later than 6.10's table gives, and a <c>PRIOR</c> mode
///   change one to three clocks earlier.
///  </para>
/// </remarks>
public sealed class Gtia
{
    /// <summary>
    ///  The frame's width: 188 visible colour clocks of two pixels each.
    /// </summary>
    public const int FrameWidth = (AtariTiming.EndVisibleClock - AtariTiming.FirstVisibleClock) * 2;

    /// <summary>
    ///  The frame's height: scan lines 8-247.
    /// </summary>
    public const int FrameHeight = AtariTiming.VerticalBlankLine - AtariTiming.FirstDisplayLine;

    /// <summary>
    ///  Marks a high-resolution playfield clock in <see cref="Playfield"/>; bits 1 and 0 are its two half-clock pixels.
    /// </summary>
    public const byte HiresFlag = 0x10;

    private const int PendingSize = 16;

    private readonly byte[] _playfield = new byte[AtariTiming.ColorClocksPerLine + 32];
    private readonly byte[] _frame = new byte[FrameWidth * FrameHeight * 4];
    private readonly byte[] _colors = new byte[9];
    private readonly byte[] _playerPosition = new byte[4];
    private readonly byte[] _missilePosition = new byte[4];
    private readonly byte[] _playerSize = new byte[4];
    private readonly byte[] _playerGraphics = new byte[4];
    private readonly byte[] _playerShift = new byte[4];
    private readonly byte[] _playerState = new byte[4];
    private readonly byte[] _missileShift = new byte[4];
    private readonly byte[] _missileState = new byte[4];
    private readonly byte[] _missileToPlayfield = new byte[4];
    private readonly byte[] _playerToPlayfield = new byte[4];
    private readonly byte[] _missileToPlayer = new byte[4];
    private readonly byte[] _playerToPlayer = new byte[4];
    private readonly (int Clock, byte Register, byte Value)[] _pending = new (int, byte, byte)[PendingSize];
    private readonly uint[] _palette;
    private readonly AtariGraphicsChip _chip;
    private readonly AtariVideoStandard _standard;

    private int _pendingCount;
    private byte _missileSize;
    private byte _missileGraphics;
    private byte _consoleOutput;
    private byte _triggerLatch = 0x0F;
    private int _line;

    /// <summary>
    ///  Constructs a GTIA at power-on.
    /// </summary>
    /// <param name="chip">GTIA or the earlier CTIA.</param>
    /// <param name="standard">The television standard, for the <c>PAL</c> register and the palette.</param>
    internal Gtia(AtariGraphicsChip chip, AtariVideoStandard standard)
    {
        _chip = chip;
        _standard = standard;
        _palette = AtariPalette.Create(standard);
    }

    /// <summary>
    ///  Gets the playfield codes for the current scan line, by colour clock, which ANTIC fills ahead of the beam.
    /// </summary>
    internal Span<byte> Playfield => _playfield;

    /// <summary>
    ///  Gets or sets whether ANTIC is sending a high-resolution mode (2, 3 or F) on this line.
    /// </summary>
    internal bool Hires { get; set; }

    /// <summary>
    ///  Gets or sets the console keys held, as <c>CONSOL</c> bits: 0 START, 1 SELECT, 2 OPTION.
    /// </summary>
    public byte ConsoleKeys { get; set; }

    /// <summary>
    ///  Gets or sets the joystick triggers held, bits 0-3 for triggers 0-3.
    /// </summary>
    public byte Triggers { get; set; }

    /// <summary>
    ///  Gets the console speaker's level: <c>CONSOL</c> bit 3 as written.
    /// </summary>
    public bool Speaker => (_consoleOutput & 0x08) != 0;

    /// <summary>
    ///  Gets <c>PRIOR</c>.
    /// </summary>
    public byte Priority { get; private set; }

    /// <summary>
    ///  Gets <c>GRACTL</c>: bit 0 takes missile DMA, bit 1 player DMA, bit 2 latches the triggers.
    /// </summary>
    public byte GraphicsControl { get; private set; }

    /// <summary>
    ///  Gets <c>VDELAY</c>: bits 0-3 missiles and 4-7 players load their DMA only on odd scan lines.
    /// </summary>
    public byte VerticalDelay { get; private set; }

    /// <summary>
    ///  Gets a colour register: 0-3 <c>COLPM0</c>-<c>COLPM3</c>, 4-7 <c>COLPF0</c>-<c>COLPF3</c>, 8 <c>COLBK</c>.
    /// </summary>
    /// <param name="index">The register.</param>
    /// <returns>The colour: the hue in bits 4-7 and the luminance in bits 1-3.</returns>
    public byte Color(int index) => _colors[index];

    /// <summary>
    ///  Gets the frame as it was drawn, 376 × 240 RGBA.
    /// </summary>
    public ReadOnlySpan<byte> Frame => _frame;

    /// <summary>
    ///  Gets the RGBA of a colour value.
    /// </summary>
    /// <param name="color">The colour: hue in bits 4-7, luminance in bits 0-3.</param>
    /// <returns>The colour as <c>0xAABBGGRR</c>.</returns>
    public uint Rgba(byte color) => _palette[color];

    /// <summary>
    ///  Reads a register.
    /// </summary>
    /// <param name="register">The register, the address's low five bits.</param>
    /// <returns>The value.</returns>
    public byte Read(int register)
    {
        register &= 0x1F;
        return register switch
        {
            <= 0x03 => _missileToPlayfield[register],
            <= 0x07 => _playerToPlayfield[register - 4],
            <= 0x0B => _missileToPlayer[register - 8],
            <= 0x0F => _playerToPlayer[register - 12],
            <= 0x13 => (byte)(((GraphicsControl & 4) != 0 ? _triggerLatch : ~Triggers) >> (register - 0x10) & 1),
            0x14 => _standard == AtariVideoStandard.Pal ? (byte)0x01 : (byte)0x0F,
            0x1F => (byte)(~ConsoleKeys & ~_consoleOutput & 0x0F),
            _ => 0x0F
        };
    }

    /// <summary>
    ///  Writes a register.
    /// </summary>
    /// <param name="register">The register, the address's low five bits.</param>
    /// <param name="value">The value.</param>
    /// <param name="cycle">The cycle within the scan line, which times a delayed write.</param>
    public void Write(int register, byte value, int cycle)
    {
        register &= 0x1F;
        if (register <= 0x0C)
        {
            // Positions and sizes: three clocks late. GRAFP0-3 and GRAFM: one clock late.
            Defer((2 * cycle) + 3, register, value);
            return;
        }

        if (register <= 0x11)
        {
            Defer((2 * cycle) + 1, register, value);
            return;
        }

        Apply(register, value);
    }

    /// <summary>
    ///  Loads missile DMA for a scan line, if <c>GRACTL</c> takes it and <c>VDELAY</c> allows it.
    /// </summary>
    /// <param name="data">The missiles' bits: missile 3 in bits 7-6 down to missile 0 in bits 1-0.</param>
    /// <param name="line">The scan line.</param>
    internal void LoadMissiles(byte data, int line)
    {
        if ((GraphicsControl & 1) == 0) { return; }
        if ((line & 1) == 0 && (VerticalDelay & 0x0F) != 0)
        {
            // Missiles with VDELAY set keep their old bits on even lines.
            byte keep = 0;
            for (int missile = 0; missile < 4; missile++)
            {
                if ((VerticalDelay & (1 << missile)) != 0) { keep |= (byte)(3 << (missile * 2)); }
            }

            _missileGraphics = (byte)((_missileGraphics & keep) | (data & ~keep));
            return;
        }

        _missileGraphics = data;
    }

    /// <summary>
    ///  Loads a player's DMA for a scan line, if <c>GRACTL</c> takes it and <c>VDELAY</c> allows it.
    /// </summary>
    /// <param name="player">The player, 0-3.</param>
    /// <param name="data">The player's byte.</param>
    /// <param name="line">The scan line.</param>
    internal void LoadPlayer(int player, byte data, int line)
    {
        if ((GraphicsControl & 2) == 0) { return; }
        if ((line & 1) == 0 && (VerticalDelay & (0x10 << player)) != 0) { return; }
        _playerGraphics[player] = data;
    }

    /// <summary>
    ///  Starts a scan line: the playfield codes clear and the line's mode is taken.
    /// </summary>
    /// <param name="line">The scan line.</param>
    internal void StartLine(int line)
    {
        _line = line;
        Array.Clear(_playfield);
        Hires = false;
    }

    /// <summary>
    ///  Ends a scan line, and latches the triggers.
    /// </summary>
    /// <param name="line">The scan line.</param>
    internal void EndLine(int line)
    {
        _ = line;

        // With latching off (GRACTL bit 2 clear) the latches are held reset.
        if ((GraphicsControl & 4) != 0) { _triggerLatch &= (byte)~Triggers; }
    }

    /// <summary>
    ///  Draws the two colour clocks of a machine cycle.
    /// </summary>
    /// <param name="line">The scan line.</param>
    /// <param name="cycle">The cycle within the line.</param>
    internal void RenderCycle(int line, int cycle)
    {
        int clock = cycle * 2;
        Clock(line, clock);
        Clock(line, clock + 1);
    }

    private void Defer(int clock, int register, byte value)
    {
        if (_pendingCount == PendingSize) { ApplyPending(int.MaxValue); }
        _pending[_pendingCount++] = (clock, (byte)register, value);
    }

    private void ApplyPending(int clock)
    {
        int kept = 0;
        for (int index = 0; index < _pendingCount; index++)
        {
            (int at, byte register, byte value) = _pending[index];
            if (at <= clock)
            {
                Apply(register, value);
            }
            else
            {
                _pending[kept++] = _pending[index];
            }
        }

        _pendingCount = kept;
    }

    private void Apply(int register, byte value)
    {
        switch (register)
        {
            case <= 0x03: _playerPosition[register] = value; break;
            case <= 0x07: _missilePosition[register - 4] = value; break;
            case <= 0x0B: _playerSize[register - 8] = (byte)(value & 3); break;
            case 0x0C: _missileSize = value; break;
            case <= 0x10: _playerGraphics[register - 0x0D] = value; break;
            case 0x11: _missileGraphics = value; break;
            case <= 0x1A: _colors[register - 0x12] = (byte)(value & 0xFE); break;
            case 0x1B: Priority = value; break;
            case 0x1C: VerticalDelay = value; break;
            case 0x1D:
                GraphicsControl = (byte)(value & 7);
                if ((value & 4) == 0) { _triggerLatch = 0x0F; }
                break;
            case 0x1E:
                Array.Clear(_missileToPlayfield);
                Array.Clear(_playerToPlayfield);
                Array.Clear(_missileToPlayer);
                Array.Clear(_playerToPlayer);
                break;
            case 0x1F: _consoleOutput = (byte)(value & 0x0F); break;
        }
    }

    private void Clock(int line, int clock)
    {
        if (_pendingCount != 0) { ApplyPending(clock); }

        // The players' and missiles' shifters run all the time, across blanking.
        int players = 0;
        for (int player = 0; player < 4; player++)
        {
            if (_playerPosition[player] == clock)
            {
                _playerShift[player] |= _playerGraphics[player];
                _playerState[player] = 0;
            }

            if ((_playerShift[player] & 0x80) != 0) { players |= 1 << player; }
            int size = _playerSize[player];
            int state = (_playerState[player] + 1) & size;
            _playerState[player] = (byte)state;
            if (state == 0) { _playerShift[player] <<= 1; }
        }

        int missiles = 0;
        for (int missile = 0; missile < 4; missile++)
        {
            int shift = missile * 2;
            if (_missilePosition[missile] == clock)
            {
                _missileShift[missile] |= (byte)(((_missileGraphics >> shift) & 3) << 6);
                _missileState[missile] = 0;
            }

            if ((_missileShift[missile] & 0x80) != 0) { missiles |= 1 << missile; }
            int size = (_missileSize >> shift) & 3;
            int state = (_missileState[missile] + 1) & size;
            _missileState[missile] = (byte)state;
            if (state == 0) { _missileShift[missile] <<= 1; }
        }

        bool visibleLine = line >= AtariTiming.FirstDisplayLine && line < AtariTiming.VerticalBlankLine;
        bool visibleClock = clock >= AtariTiming.FirstVisibleClock && clock < AtariTiming.EndVisibleClock;
        if (!visibleLine || !visibleClock)
        {
            return;
        }

        byte code = _playfield[clock];
        int mode = _chip == AtariGraphicsChip.Gtia ? Priority >> 6 : 0;
        bool hires = Hires && mode == 0;

        // The playfield signals PF0-PF3 as bits 0-3, and what collides with them.
        int playfield;
        int collides;
        int special = -1;
        if (mode != 0)
        {
            // GTIA modes pair colour clocks into 4-bit pixels from the 2-bit ANTIC data; mode 10 shows a clock late.
            int pair = mode == 2 ? (clock - 1) & ~1 : clock & ~1;
            int pixel = (AnBits(_playfield[pair]) << 2) | AnBits(_playfield[pair + 1]);
            if (mode == 2)
            {
                // Nine colours: 0-3 the players' registers, 4-7 and 12-15 the playfields, 8-11 the background.
                playfield = pixel switch
                {
                    >= 4 and <= 7 or >= 12 => 1 << (pixel & 3),
                    _ => 0
                };

                collides = playfield;
                if (pixel <= 3) { special = pixel; }
            }
            else
            {
                playfield = 0;
                collides = 0;
                special = 0x100 | pixel;
            }
        }
        else if (hires)
        {
            playfield = (code & HiresFlag) != 0 ? 4 : 0;
            collides = (code & HiresFlag) != 0 && (code & 3) != 0 ? 4 : 0;
        }
        else
        {
            playfield = code == 0 ? 0 : 1 << (code - 1);
            collides = playfield;
        }

        // Collisions, which see the players and missiles whatever their colours or priorities.
        if (players != 0 || missiles != 0)
        {
            for (int missile = 0; missile < 4; missile++)
            {
                if ((missiles & (1 << missile)) == 0) { continue; }
                _missileToPlayfield[missile] |= (byte)collides;
                _missileToPlayer[missile] |= (byte)players;
            }

            for (int player = 0; player < 4; player++)
            {
                if ((players & (1 << player)) == 0) { continue; }
                _playerToPlayfield[player] |= (byte)collides;
                _playerToPlayer[player] |= (byte)(players & ~(1 << player));
            }
        }

        byte color = Resolve(players, missiles, playfield, special);
        uint left = _palette[color];
        uint right = left;
        if (hires && (code & HiresFlag) != 0)
        {
            byte luminance = (byte)(_colors[5] & 0x0E);
            if ((code & 2) != 0) { left = _palette[(color & 0xF0) | luminance]; }
            if ((code & 1) != 0) { right = _palette[(color & 0xF0) | luminance]; }
        }

        int offset = ((((line - AtariTiming.FirstDisplayLine) * FrameWidth) + ((clock - AtariTiming.FirstVisibleClock) * 2)) * 4);
        Unsafe.WriteUnaligned(ref _frame[offset], left);
        Unsafe.WriteUnaligned(ref _frame[offset + 4], right);
    }

    // The two bits ANTIC sends on AN0-AN1 for a playfield code: a high-resolution pair as it is, and in the
    // low-resolution modes BAK and PF0 both as 00, PF1 01, PF2 10, PF3 11.
    private static int AnBits(byte code) => (code & HiresFlag) != 0
        ? code & 3
        : code switch
        {
            2 => 1,
            3 => 2,
            4 => 3,
            _ => 0
        };

    // The manual's priority gates (6.7): the selected objects' colours OR together.
    private byte Resolve(int players, int missiles, int playfield, int special)
    {
        byte prior = Priority;
        bool fifth = (prior & 0x10) != 0;
        bool multi = (prior & 0x20) != 0;
        int objects = fifth ? players : players | missiles;
        if (special is >= 0 and < 0x100) { objects |= 1 << special; }

        bool p0 = (objects & 1) != 0, p1 = (objects & 2) != 0, p2 = (objects & 4) != 0, p3 = (objects & 8) != 0;
        bool pf0 = (playfield & 1) != 0, pf1 = (playfield & 2) != 0, pf2 = (playfield & 4) != 0;
        bool pf3 = (playfield & 8) != 0 || (fifth && missiles != 0);
        bool pri0 = (prior & 1) != 0, pri1 = (prior & 2) != 0, pri2 = (prior & 4) != 0, pri3 = (prior & 8) != 0;
        bool pri01 = pri0 | pri1, pri12 = pri1 | pri2, pri23 = pri2 | pri3, pri03 = pri0 | pri3;
        bool pf01 = pf0 | pf1, pf23 = pf2 | pf3, p01 = p0 | p1, p23 = p2 | p3;

        bool sp0 = p0 && !(pf01 && pri23) && !(pri2 && pf23);
        bool sp1 = p1 && !(pf01 && pri23) && !(pri2 && pf23) && (!p0 || multi);
        bool sp2 = p2 && !p01 && !(pf23 && pri12) && !(pf01 && !pri0);
        bool sp3 = p3 && !p01 && !(pf23 && pri12) && !(pf01 && !pri0) && (!p2 || multi);
        bool sf3 = pf3 && !(p23 && pri03) && !(p01 && !pri2);
        bool sf0 = pf0 && !(p23 && pri0) && !(p01 && pri01) && !sf3;
        bool sf1 = pf1 && !(p23 && pri0) && !(p01 && pri01) && !sf3;
        bool sf2 = pf2 && !(p23 && pri03) && !(p01 && !pri2) && !sf3;
        bool sb = !p01 && !p23 && !pf01 && !pf23;

        int color = 0;
        if (sp0) { color |= _colors[0]; }
        if (sp1) { color |= _colors[1]; }
        if (sp2) { color |= _colors[2]; }
        if (sp3) { color |= _colors[3]; }
        if (sf0) { color |= _colors[4]; }
        if (sf1) { color |= _colors[5]; }
        if (sf2) { color |= _colors[6]; }
        if (sf3) { color |= _colors[7]; }
        if (sb)
        {
            if (special >= 0x100)
            {
                // GTIA modes 9 and 11 are the background, with the pixel's luminance or hue.
                int pixel = special & 0x0F;
                int mode = Priority >> 6;
                color |= mode == 1
                    ? _colors[8] | pixel
                    : pixel == 0 ? _colors[8] & 0xF0 : _colors[8] | (pixel << 4);
            }
            else
            {
                color |= _colors[8];
            }
        }

        return (byte)color;
    }
}
