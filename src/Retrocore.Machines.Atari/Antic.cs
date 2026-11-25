// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Atari;

/// <summary>
///  ANTIC (CO12296): the display list processor. It counts the beam, runs the display list, takes the bus from the
///  CPU for its DMA, hands the playfield and the player/missile data to GTIA, raises the display list and vertical
///  blank interrupts, and holds the CPU for <c>WSYNC</c>.
/// </summary>
/// <remarks>
///  <para>
///   Timing follows the Altirra Hardware Reference Manual, chapter 4. On each scan line of 114 cycles: missile DMA
///   on cycle 0, the display list instruction on cycle 1, players on cycles 2-5 and an LMS or jump address on cycles
///   6-7. NMIST changes on cycle 7 and the NMI is pulled on cycle 8. Nine refresh cycles fall due from cycle 25, every
///   four cycles, each put off to the next free cycle when playfield DMA has the bus, but only one at a time.
///   Playfield DMA follows the fetch width (64, 80 or 96 cycles, one step wider with horizontal scrolling): bitmap
///   fetches from cycle 28, 20 or 12, character names from 26, 18 or 10 and their data three cycles after each name,
///   each start one cycle later for each two colour clocks of <c>HSCROL</c>. Fetches from cycle 106 on don't take the
///   bus. A bitmap byte fetched on cycle <c>c</c> shows from colour clock <c>2c + 8</c>, and character data from
///   <c>2c + 6</c>, one clock later again for an odd <c>HSCROL</c>.
///  </para>
///  <para>
///   The playfield is handed to GTIA as a code per colour clock in <see cref="Gtia.Playfield"/>: <c>0</c> for the
///   background, <c>1</c>-<c>4</c> for PF0-PF3 in the low-resolution modes, or <see cref="Gtia.HiresFlag"/> with
///   the two half-clock pixels in bits 1 and 0 in modes 2, 3 and F.
///  </para>
/// </remarks>
public sealed class Antic
{
    // Scan lines per mode line, by mode (0 and 1 are worked out from the instruction).
    private static readonly byte[] s_heights = [1, 1, 8, 10, 8, 16, 8, 16, 8, 4, 4, 2, 1, 2, 1, 1];

    private readonly AtariBus _bus;
    private readonly Gtia _gtia;
    private readonly int _linesPerFrame;

    // What each cycle of the line's playfield DMA does: 0 nothing, 1 a name or bitmap fetch, 2 a character data fetch,
    // 3 a bitmap byte replayed from the line buffer on a later scan line.
    private readonly byte[] _playfieldKind = new byte[AtariTiming.CyclesPerLine + 8];

    // The index into the line buffer of each fetch.
    private readonly byte[] _playfieldIndex = new byte[AtariTiming.CyclesPerLine + 8];

    // Character names, or bitmap bytes, from the first line of the mode line.
    private readonly byte[] _lineBuffer = new byte[48];

    private ushort _displayList;
    private byte _addressLow;
    private ushort _memoryScan;
    private byte _instruction;
    private int _mode;
    private int _row;
    private int _endRow;
    private bool _previousVerticalScroll;
    private bool _firstLine;
    private bool _modeLineDone = true;
    private bool _waitForVerticalBlank;
    private bool _hires;
    private int _dmaStartLine;

    // Playfield set up for this line.
    private bool _playfieldLine;
    private int _scroll;
    private int _displayLeft;
    private int _displayRight;

    private bool _refreshPending;
    private long _wsyncFrom = -1;
    private bool _nmiRequested;
    private bool _nmiLate;
    private bool _nmiForced;
    private byte _nmiCandidates;
    private byte _nmiEnableAtSeven;
    private bool _nmiEdge;
    private bool _resetHeld;

    /// <summary>
    ///  Constructs ANTIC at power-on.
    /// </summary>
    /// <param name="bus">The bus it reads for DMA.</param>
    /// <param name="gtia">The GTIA it drives.</param>
    /// <param name="standard">The television standard, which sets the frame length.</param>
    internal Antic(AtariBus bus, Gtia gtia, AtariVideoStandard standard)
    {
        _bus = bus;
        _gtia = gtia;
        _linesPerFrame = AtariTiming.LinesPerFrame(standard);
    }

    /// <summary>
    ///  Gets the scan line, 0 to 261 (NTSC) or 311 (PAL).
    /// </summary>
    public int Line { get; private set; }

    /// <summary>
    ///  Gets the cycle within the scan line, 0-113.
    /// </summary>
    public int Cycle { get; private set; }

    /// <summary>
    ///  Gets <c>DMACTL</c>: bits 0-1 the playfield width (off, narrow, normal, wide), bit 2 missile DMA, bit 3 player
    ///  DMA, bit 4 one-line player resolution, bit 5 display list DMA.
    /// </summary>
    public byte DmaControl { get; private set; }

    /// <summary>
    ///  Gets <c>CHACTL</c>: bit 0 blanks, and bit 1 inverts, mode 2 and 3 characters with bit 7 set; bit 2 turns every
    ///  character upside down.
    /// </summary>
    public byte CharacterControl { get; private set; }

    /// <summary>
    ///  Gets the display list pointer, <c>DLISTL</c> and <c>DLISTH</c>.
    /// </summary>
    public ushort DisplayList => _displayList;

    /// <summary>
    ///  Gets the memory scan counter.
    /// </summary>
    public ushort MemoryScan => _memoryScan;

    /// <summary>
    ///  Gets the instruction register: the display list instruction now running.
    /// </summary>
    public byte Instruction => _instruction;

    /// <summary>
    ///  Gets <c>HSCROL</c>, the fine horizontal scroll in colour clocks.
    /// </summary>
    public byte HorizontalScroll { get; private set; }

    /// <summary>
    ///  Gets <c>VSCROL</c>, the fine vertical scroll in scan lines.
    /// </summary>
    public byte VerticalScroll { get; private set; }

    /// <summary>
    ///  Gets <c>PMBASE</c>, the page of player/missile data.
    /// </summary>
    public byte PlayerMissileBase { get; private set; }

    /// <summary>
    ///  Gets <c>CHBASE</c>, the page of the character set.
    /// </summary>
    public byte CharacterBase { get; private set; }

    /// <summary>
    ///  Gets <c>NMIEN</c>: bit 6 enables the vertical blank interrupt, bit 7 the display list interrupt.
    /// </summary>
    public byte NmiEnable { get; private set; }

    /// <summary>
    ///  Gets <c>NMIST</c>'s status bits: 7 a display list interrupt, 6 vertical blank, 5 SYSTEM RESET.
    /// </summary>
    public byte NmiStatus { get; private set; }

    /// <summary>
    ///  Gets or sets whether SYSTEM RESET is held. On the 400 and 800 it raises ANTIC's reset NMI at the start of
    ///  vertical blank.
    /// </summary>
    public bool ResetKey
    {
        get => _resetHeld;
        set => _resetHeld = value;
    }

    /// <summary>
    ///  Gets <c>VCOUNT</c>: bits 1-8 of the scan line, changing on cycle 111 of the line before.
    /// </summary>
    public byte VerticalCount
    {
        get
        {
            int line = Line;
            if (Cycle >= 111)
            {
                // The counter wraps one cycle late, so the last line's cycle 111 shows line 262 (or 312).
                line = line + 1 == _linesPerFrame && Cycle > 111 ? 0 : line + 1;
            }

            return (byte)(line >> 1);
        }
    }

    /// <summary>
    ///  Gets whether the next CPU cycle is held by <c>WSYNC</c> (the RDY line).
    /// </summary>
    internal bool HoldsCpu => _wsyncFrom >= 0 && _bus.Cycles >= _wsyncFrom;

    /// <summary>
    ///  Takes a pending NMI edge, which the CPU latches.
    /// </summary>
    /// <returns>Whether ANTIC pulled NMI since the last call.</returns>
    internal bool TakeNmi()
    {
        bool edge = _nmiEdge;
        _nmiEdge = false;
        return edge;
    }

    /// <summary>
    ///  Reads a register.
    /// </summary>
    /// <param name="register">The register, the address's low four bits.</param>
    /// <returns>The value; registers that can't be read return <c>$FF</c>.</returns>
    public byte Read(int register) => (register & 0x0F) switch
    {
        0x0B => VerticalCount,
        0x0C => 0x00,
        0x0D => 0xFF,
        0x0F => (byte)(NmiStatus | 0x1F),
        _ => 0xFF
    };

    /// <summary>
    ///  Writes a register.
    /// </summary>
    /// <param name="register">The register, the address's low four bits.</param>
    /// <param name="value">The value.</param>
    public void Write(int register, byte value)
    {
        switch (register & 0x0F)
        {
            case 0x00: DmaControl = (byte)(value & 0x3F); break;
            case 0x01: CharacterControl = (byte)(value & 0x07); break;
            case 0x02: _displayList = (ushort)((_displayList & 0xFF00) | value); break;
            case 0x03: _displayList = (ushort)((_displayList & 0x00FF) | (value << 8)); break;
            case 0x04: HorizontalScroll = (byte)(value & 0x0F); break;
            case 0x05: VerticalScroll = (byte)(value & 0x0F); break;
            case 0x07: PlayerMissileBase = value; break;
            case 0x09: CharacterBase = value; break;
            case 0x0A:
                // The CPU runs one more cycle, then waits for cycle 105 (Altirra 4.9).
                _wsyncFrom = _bus.Cycles + 2;
                break;
            case 0x0E: NmiEnable = (byte)(value & 0xC0); break;
            case 0x0F: NmiStatus = 0; break;
        }
    }

    /// <summary>
    ///  Starts a machine cycle: ANTIC either takes the bus for DMA or leaves it to the CPU.
    /// </summary>
    /// <returns>Whether ANTIC used the bus, so the CPU is halted.</returns>
    internal bool BeginCycle()
    {
        int cycle = Cycle;
        if (cycle == 0) { StartLine(); }

        // Release WSYNC on cycle 105.
        if (_wsyncFrom >= 0 && cycle == 105 && _bus.Cycles >= _wsyncFrom) { _wsyncFrom = -1; }

        bool display = Line >= AtariTiming.FirstDisplayLine && Line < AtariTiming.VerticalBlankLine;
        bool busy = false;
        switch (cycle)
        {
            case 0:
                if (display && (DmaControl & 0x0C) != 0)
                {
                    _gtia.LoadMissiles(_bus.DmaRead(PlayerMissileAddress(0x180, 0x300)), Line);
                    busy = true;
                }

                break;
            case 1:
                busy = FetchInstruction(display);
                break;
            case 2:
            case 3:
            case 4:
            case 5:
                if (display && (DmaControl & 0x08) != 0)
                {
                    int player = cycle - 2;
                    ushort address = PlayerMissileAddress(0x200 + (player * 0x80), 0x400 + (player * 0x100));
                    _gtia.LoadPlayer(player, _bus.DmaRead(address), Line);
                    busy = true;
                }

                break;
            case 6:
            case 7:
                busy = FetchAddress(cycle);
                if (cycle == 7) { RaiseNmis(); }
                break;
            case 8:
                // NMIEN must be written by cycle 7 to enable an interrupt (Altirra 4.8): this runs before cycle 8's
                // write, so it sees cycle 7's. One enabled on cycle 7 itself comes a cycle late.
                _nmiRequested = _nmiForced || (_nmiCandidates & NmiEnable) != 0;
                _nmiLate = !_nmiForced && (_nmiCandidates & _nmiEnableAtSeven) == 0;
                if (display) { SetUpPlayfield(); }
                break;
            case 9:
                // ... and by cycle 8 to disable it.
                if (!_nmiForced && (_nmiCandidates & NmiEnable) == 0) { _nmiRequested = false; }
                _nmiCandidates = 0;
                _nmiForced = false;
                break;
            case 10:
            case 11:
                // ANTIC pulls NMI on cycle 8; the 6502 takes two cycles to see it, so the interrupt sequence
                // starts on cycle 10 at the earliest, or 11 for an interrupt enabled on cycle 7 (Altirra 4.8). This
                // 6502 takes a latched NMI at its next instruction boundary, so the edge reaches it from then.
                if (_nmiRequested && _nmiLate == (cycle == 11))
                {
                    _nmiRequested = false;
                    _nmiEdge = true;
                }

                break;
        }

        if (!busy && _playfieldLine && cycle < _playfieldKind.Length && _playfieldKind[cycle] != 0)
        {
            busy = PlayfieldFetch(cycle);
        }

        // Refresh: due on cycles 25, 29, ... 57; a blocked one waits for a free cycle, and only one can wait.
        bool due = cycle >= 25 && cycle <= 57 && ((cycle - 25) & 3) == 0;
        if (busy)
        {
            if (due) { _refreshPending = true; }
        }
        else if (due || _refreshPending)
        {
            _refreshPending = false;
            busy = true;
        }

        return busy;
    }

    /// <summary>
    ///  Ends a machine cycle: GTIA draws its two colour clocks and the beam moves on.
    /// </summary>
    internal void EndCycle()
    {
        _gtia.RenderCycle(Line, Cycle);
        if (++Cycle == AtariTiming.CyclesPerLine)
        {
            Cycle = 0;
            EndLine();
        }
    }

    /// <summary>
    ///  Resets ANTIC at power-on: <c>NMIEN</c> and <c>DMACTL</c> clear. On the 400 and 800 the reset button doesn't
    ///  reach ANTIC.
    /// </summary>
    internal void PowerOn()
    {
        NmiEnable = 0;
        DmaControl = 0;
    }

    private ushort PlayerMissileAddress(int twoLineOffset, int oneLineOffset)
    {
        int line = Line;
        return (DmaControl & 0x10) != 0
            ? (ushort)(((PlayerMissileBase & 0xF8) << 8) + oneLineOffset + line)
            : (ushort)(((PlayerMissileBase & 0xFC) << 8) + twoLineOffset + (line >> 1));
    }

    private void StartLine()
    {
        int line = Line;
        if (line == AtariTiming.FirstDisplayLine)
        {
            _waitForVerticalBlank = false;
            _modeLineDone = true;
        }

        _gtia.StartLine(line);
        _playfieldLine = false;
    }

    // Cycle 1: a new mode line fetches its instruction.
    private bool FetchInstruction(bool display)
    {
        if (!display || !_modeLineDone) { return false; }

        _firstLine = true;
        bool fetched = false;
        if (!_waitForVerticalBlank && (DmaControl & 0x20) != 0)
        {
            _instruction = _bus.DmaRead(_displayList);
            _displayList = NextDisplayListAddress(_displayList);
            fetched = true;
        }

        _mode = _instruction & 0x0F;
        _dmaStartLine = Line;
        _hires = _mode is 2 or 3 or 0x0F;

        bool verticalScroll = _mode >= 2 && (_instruction & 0x20) != 0;
        int height = _mode switch
        {
            0 => ((_instruction >> 4) & 7) + 1,
            1 => 1,
            _ => s_heights[_mode]
        };

        _row = verticalScroll && !_previousVerticalScroll ? VerticalScroll : 0;
        _endRow = !verticalScroll && _previousVerticalScroll ? VerticalScroll : (height - 1) & 0x0F;
        _previousVerticalScroll = verticalScroll;
        _modeLineDone = false;
        return fetched;
    }

    // Cycles 6 and 7: the address of an LMS or a jump, on the mode line's first scan line; a jump that vertical
    // scrolling stretches over more scan lines fetches it again on each (Altirra 4.x, "Mode lines with unusual
    // height").
    private bool FetchAddress(int cycle)
    {
        if (_waitForVerticalBlank || (DmaControl & 0x20) == 0) { return false; }
        bool jump = _mode == 1;
        bool lms = _mode >= 2 && (_instruction & 0x40) != 0;
        if (!jump && !lms) { return false; }

        // A fetched instruction is already in the register; JVB's address is fetched once.
        if (!jump && (!_firstLine || Line != _dmaStartLine)) { return false; }

        byte value = _bus.DmaRead(_displayList);
        _displayList = NextDisplayListAddress(_displayList);
        if (cycle == 6)
        {
            _addressLow = value;
            return true;
        }

        ushort address = (ushort)(_addressLow | (value << 8));
        if (jump)
        {
            _displayList = address;
            if ((_instruction & 0x40) != 0) { _waitForVerticalBlank = true; }
        }
        else
        {
            _memoryScan = address;
        }

        return true;
    }

    // Cycle 7: NMIST changes, and the NMI follows on cycle 8 if NMIEN allows it then (and still on cycle 9).
    private void RaiseNmis()
    {
        _nmiEnableAtSeven = NmiEnable;
        int line = Line;
        if (line == AtariTiming.VerticalBlankLine)
        {
            NmiStatus = (byte)((NmiStatus & 0x20) | 0x40);
            _nmiCandidates = 0x40;
            if (_resetHeld)
            {
                NmiStatus |= 0x20;
                _nmiForced = true;
            }

            return;
        }

        bool display = line >= AtariTiming.FirstDisplayLine && line < AtariTiming.VerticalBlankLine;
        if (display && (_instruction & 0x80) != 0 && _row == _endRow)
        {
            NmiStatus = (byte)((NmiStatus & 0x20) | 0x80);
            _nmiCandidates = 0x80;
        }
    }

    // Cycle 8: plan the line's playfield DMA from DMACTL, HSCROL and the mode.
    private void SetUpPlayfield()
    {
        Array.Clear(_playfieldKind);
        int width = DmaControl & 3;
        _gtia.Hires = _hires && width != 0;
        if (_mode < 2 || width == 0) { return; }

        bool scrolled = (_instruction & 0x10) != 0;
        int fetchWidth = scrolled && width < 3 ? width + 1 : width;
        int delay = scrolled ? HorizontalScroll >> 1 : 0;
        _scroll = scrolled ? HorizontalScroll & 1 : 0;
        (_displayLeft, _displayRight) = width switch
        {
            1 => (0x40, 0xC0),
            2 => (0x30, 0xD0),
            _ => (0x2C, 0xDE)
        };

        int window = 48 + (fetchWidth * 16);
        bool character = _mode <= 7;
        int step = _mode switch
        {
            <= 5 => 2,
            6 or 7 => 4,
            8 or 9 => 8,
            0x0A or 0x0B or 0x0C => 4,
            _ => 2
        };

        int count = window / step;
        if (character)
        {
            int start = 34 - (fetchWidth * 8) + delay;
            for (int index = 0; index < count; index++)
            {
                int name = start + (index * step);
                if (_firstLine)
                {
                    _playfieldKind[name] = 1;
                    _playfieldIndex[name] = (byte)index;
                }

                _playfieldKind[name + 3] = 2;
                _playfieldIndex[name + 3] = (byte)index;
            }
        }
        else
        {
            int start = 36 - (fetchWidth * 8) + delay;
            for (int index = 0; index < count; index++)
            {
                int fetch = start + (index * step);
                _playfieldKind[fetch] = _firstLine ? (byte)1 : (byte)3;
                _playfieldIndex[fetch] = (byte)index;
            }
        }

        _playfieldLine = true;
    }

    // A playfield fetch, or on later lines of a bitmap mode the replay of one: returns whether it took the bus.
    private bool PlayfieldFetch(int cycle)
    {
        int kind = _playfieldKind[cycle];
        int index = _playfieldIndex[cycle];
        bool enabled = (DmaControl & 3) != 0;

        // Fetches from cycle 106 don't take the bus, though the counter still moves on.
        bool real = cycle < 106 && enabled;
        if (kind == 3)
        {
            if (enabled) { DrawBitmap(cycle, _lineBuffer[index]); }
            return false;
        }

        if (kind == 1)
        {
            byte data = real ? _bus.DmaRead(_memoryScan) : (byte)0xFF;
            _memoryScan = (ushort)((_memoryScan & 0xF000) | ((_memoryScan + 1) & 0x0FFF));
            if (enabled) { _lineBuffer[index] = data; }
            if (_mode >= 8 && enabled) { DrawBitmap(cycle, data); }
            return real;
        }

        // Character data: the name came from the first line's fetch.
        byte name = _lineBuffer[index];
        int row = _row & 0x0F;
        ushort address;
        bool blankRow = false;
        if (_mode <= 5)
        {
            int dataRow = _mode == 5 ? row >> 1 : row;
            if (_mode <= 3)
            {
                if (dataRow >= 10) { dataRow -= 8; }
                if (_mode == 3 || dataRow >= 8)
                {
                    bool descender = (name & 0x60) == 0x60;
                    blankRow = descender ? dataRow < 2 : dataRow >= 8;
                }
            }

            dataRow &= 7;
            if ((CharacterControl & 4) != 0) { dataRow = 7 - dataRow; }
            address = (ushort)(((CharacterBase & 0xFC) << 8) | ((name & 0x7F) << 3) | dataRow);
        }
        else
        {
            int dataRow = _mode == 7 ? row >> 1 : row;
            dataRow &= 7;
            if ((CharacterControl & 4) != 0) { dataRow = 7 - dataRow; }
            address = (ushort)(((CharacterBase & 0xFE) << 8) | ((name & 0x3F) << 3) | dataRow);
        }

        byte glyph = real ? _bus.DmaRead(address) : (byte)0xFF;
        if (blankRow) { glyph = 0; }
        if (enabled) { DrawCharacter(cycle, name, glyph); }
        return real;
    }

    private void DrawBitmap(int cycle, byte data)
    {
        int clock = (2 * cycle) + 8 + _scroll;
        Span<byte> playfield = _gtia.Playfield;
        switch (_mode)
        {
            case 0x08:
                for (int pixel = 0; pixel < 4; pixel++)
                {
                    Fill(playfield, clock + (pixel * 4), 4, FourColor((data >> (6 - (pixel * 2))) & 3));
                }

                break;
            case 0x09:
                for (int pixel = 0; pixel < 8; pixel++)
                {
                    Fill(playfield, clock + (pixel * 2), 2, (byte)((data >> (7 - pixel)) & 1));
                }

                break;
            case 0x0A:
                for (int pixel = 0; pixel < 4; pixel++)
                {
                    Fill(playfield, clock + (pixel * 2), 2, FourColor((data >> (6 - (pixel * 2))) & 3));
                }

                break;
            case 0x0B:
            case 0x0C:
                for (int pixel = 0; pixel < 8; pixel++)
                {
                    Fill(playfield, clock + pixel, 1, (byte)((data >> (7 - pixel)) & 1));
                }

                break;
            case 0x0D:
            case 0x0E:
                for (int pixel = 0; pixel < 4; pixel++)
                {
                    Fill(playfield, clock + pixel, 1, FourColor((data >> (6 - (pixel * 2))) & 3));
                }

                break;
            default:
                for (int pixel = 0; pixel < 4; pixel++)
                {
                    Fill(playfield, clock + pixel, 1, (byte)(Gtia.HiresFlag | ((data >> (6 - (pixel * 2))) & 3)));
                }

                break;
        }
    }

    private void DrawCharacter(int cycle, byte name, byte glyph)
    {
        int clock = (2 * cycle) + 6 + _scroll;
        Span<byte> playfield = _gtia.Playfield;
        if (_mode <= 3)
        {
            if ((name & 0x80) != 0)
            {
                if ((CharacterControl & 1) != 0) { glyph = 0; }
                if ((CharacterControl & 2) != 0) { glyph ^= 0xFF; }
            }

            for (int pixel = 0; pixel < 4; pixel++)
            {
                Fill(playfield, clock + pixel, 1, (byte)(Gtia.HiresFlag | ((glyph >> (6 - (pixel * 2))) & 3)));
            }
        }
        else if (_mode <= 5)
        {
            for (int pixel = 0; pixel < 4; pixel++)
            {
                int bits = (glyph >> (6 - (pixel * 2))) & 3;
                byte code = bits == 3 && (name & 0x80) != 0 ? (byte)4 : FourColor(bits);
                Fill(playfield, clock + pixel, 1, code);
            }
        }
        else
        {
            byte color = (byte)((name >> 6) + 1);
            for (int pixel = 0; pixel < 8; pixel++)
            {
                Fill(playfield, clock + pixel, 1, (glyph & (0x80 >> pixel)) != 0 ? color : (byte)0);
            }
        }
    }

    private void Fill(Span<byte> playfield, int clock, int count, byte code)
    {
        for (int index = 0; index < count; index++)
        {
            int at = clock + index;
            if (at >= _displayLeft && at < _displayRight && at < playfield.Length) { playfield[at] = code; }
        }
    }

    private static byte FourColor(int bits) => (byte)bits;

    private void EndLine()
    {
        int line = Line;
        bool display = line >= AtariTiming.FirstDisplayLine && line < AtariTiming.VerticalBlankLine;
        if (display && !_modeLineDone)
        {
            _firstLine = false;
            if (_row == _endRow)
            {
                _modeLineDone = true;
            }
            else
            {
                _row = (_row + 1) & 0x0F;
            }

            // A jump-and-wait repeats as a one-line blank until vertical blank.
            if (_waitForVerticalBlank && _mode == 1) { _modeLineDone = true; }
        }

        _gtia.EndLine(line);
        if (++line == _linesPerFrame) { line = 0; }
        Line = line;
        if (line == AtariTiming.VerticalBlankLine)
        {
            // A mode line running into vertical blank is cut short.
            _modeLineDone = true;
        }
    }

    // The display list counter's low 10 bits count; the top 6 don't.
    private static ushort NextDisplayListAddress(ushort address) =>
        (ushort)((address & 0xFC00) | ((address + 1) & 0x03FF));
}
