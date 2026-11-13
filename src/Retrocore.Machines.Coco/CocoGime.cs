// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Coco;

/// <summary>
///  The CoCo 3's GIME (Graphics, Interrupt and Memory Enhancement): its MMU, ROM map, palette, timer and
///  interrupts, and the video registers <see cref="Coco3Video"/> reads.
/// </summary>
/// <remarks>
///  <para>
///   Registers: <c>$FF90</c> INIT0 (bit 7 CoCo-compatible video, 6 MMU enable, 5 GIME IRQ enable, 4 GIME FIRQ
///   enable, 3 constant RAM at <c>$FE00-$FEFF</c>, 1-0 the ROM map), <c>$FF91</c> INIT1 (bit 5 the timer's
///   input, 0 the task), <c>$FF92</c> and <c>$FF93</c> the IRQ and FIRQ enables (reading returns and clears the
///   pending ones: bit 5 timer, 4 horizontal border, 3 vertical border, 2 serial, 1 keyboard, 0 cartridge),
///   <c>$FF94-$FF95</c> the 12-bit timer, <c>$FF98-$FF9F</c> video, <c>$FFA0-$FFAF</c> the MMU's two tasks of eight
///   8 KB pages, and <c>$FFB0-$FFBF</c> the palette. The SAM's switches at <c>$FFC0-$FFDF</c> remain for the
///   compatible video mode, the rate and the ROM/RAM map type.
///  </para>
///  <para>
///   With the MMU off, the 64 KB address space is blocks <c>$38-$3F</c>. Blocks <c>$3C-$3F</c> are ROM unless the
///   SAM's TY selects all RAM: the internal ROM, or the cartridge, as the ROM map says. <c>$FFE0-$FFFF</c> always
///   reads the internal ROM's vectors.
///  </para>
/// </remarks>
public sealed class CocoGime
{
    /// <summary>
    ///  The timer interrupt bit.
    /// </summary>
    public const byte TimerInterrupt = 0x20;

    /// <summary>
    ///  The horizontal border interrupt bit.
    /// </summary>
    public const byte HorizontalBorderInterrupt = 0x10;

    /// <summary>
    ///  The vertical border interrupt bit.
    /// </summary>
    public const byte VerticalBorderInterrupt = 0x08;

    /// <summary>
    ///  The keyboard interrupt bit.
    /// </summary>
    public const byte KeyboardInterrupt = 0x02;

    /// <summary>
    ///  The cartridge interrupt bit.
    /// </summary>
    public const byte CartridgeInterrupt = 0x01;

    private readonly byte[] _registers = new byte[16];
    private readonly byte[] _mmu = new byte[16];
    private readonly byte[] _palette = new byte[16];
    private int _timer;
    private int _timerHalfUnits;

    /// <summary>
    ///  Creates a reset GIME.
    /// </summary>
    public CocoGime() => Reset();

    /// <summary>
    ///  Gets the pending IRQ sources.
    /// </summary>
    public byte PendingIrq { get; private set; }

    /// <summary>
    ///  Gets the pending FIRQ sources.
    /// </summary>
    public byte PendingFirq { get; private set; }

    /// <summary>
    ///  Gets whether the GIME asks for an IRQ.
    /// </summary>
    public bool InterruptRequested => (_registers[0] & 0x20) != 0 && PendingIrq != 0;

    /// <summary>
    ///  Gets whether the GIME asks for an FIRQ.
    /// </summary>
    public bool FastInterruptRequested => (_registers[0] & 0x10) != 0 && PendingFirq != 0;

    /// <summary>
    ///  Gets whether the video is CoCo 1 and 2 compatible (INIT0 bit 7).
    /// </summary>
    public bool CompatibleVideo => (_registers[0] & 0x80) != 0;

    /// <summary>
    ///  Gets <c>$FF98</c>: bit 7 graphics, 5 burst phase, 4 monochrome, 2-0 lines per row.
    /// </summary>
    public byte VideoMode => _registers[8];

    /// <summary>
    ///  Gets <c>$FF99</c>: bits 6-5 lines per field, 4-2 bytes per row, 1-0 colors.
    /// </summary>
    public byte VideoResolution => _registers[9];

    /// <summary>
    ///  Gets <c>$FF9A</c>, the border's color.
    /// </summary>
    public byte Border => (byte)(_registers[10] & 0x3F);

    /// <summary>
    ///  Gets <c>$FF9C</c>, the vertical scroll.
    /// </summary>
    public byte VerticalScroll => _registers[12];

    /// <summary>
    ///  Gets <c>$FF9F</c>: bit 7 the 256-byte virtual width, 6-0 the horizontal offset in pairs of bytes.
    /// </summary>
    public byte HorizontalOffset => _registers[15];

    /// <summary>
    ///  Gets the physical address video starts at, from <c>$FF9D-$FF9E</c>; in the compatible mode only bits 18-16
    ///  of <c>$FF9D</c> and 15-9 of <c>$FF9E</c> count, and the SAM's display offset is added.
    /// </summary>
    /// <param name="samOffset">The SAM's display offset.</param>
    /// <returns>The address.</returns>
    public int VideoBase(int samOffset) => CompatibleVideo
        ? samOffset + ((_registers[14] & 0x3F) << 3) + ((_registers[13] & 0xE0) << 11)
        : (_registers[14] << 3) | (_registers[13] << 11);

    /// <summary>
    ///  Gets a palette entry's 6-bit color.
    /// </summary>
    /// <param name="index">The entry, 0-15.</param>
    /// <returns>The color.</returns>
    public byte Palette(int index) => _palette[index & 15];

    /// <summary>
    ///  Gets the physical 8 KB block a page of the address space maps to: through the MMU's task registers when
    ///  INIT0 enables it, else blocks <c>$38-$3F</c> in order.
    /// </summary>
    /// <param name="page">The page, 0-7.</param>
    /// <returns>The block, 0-63.</returns>
    public int Block(int page) => (_registers[0] & 0x40) != 0
        ? _mmu[page + ((_registers[1] & 1) != 0 ? 8 : 0)] & 0x3F
        : page + 0x38;

    /// <summary>
    ///  Gets whether <c>$FE00-$FEFF</c> is always block <c>$3F</c>'s RAM (INIT0 bit 3).
    /// </summary>
    public bool ConstantVectorPage => (_registers[0] & 0x08) != 0;

    /// <summary>
    ///  Gets the ROM map, INIT0 bits 1-0: 0 or 1 16 KB internal and 16 KB cartridge, 2 32 KB internal, 3 32 KB
    ///  cartridge.
    /// </summary>
    public int RomMap => _registers[0] & 3;

    /// <summary>
    ///  Reads a register at <c>$FF90-$FFBF</c>; unreadable bits and registers read the floating bus.
    /// </summary>
    /// <param name="address">The address.</param>
    /// <param name="floating">The floating bus's value.</param>
    /// <returns>The value.</returns>
    public byte Read(ushort address, byte floating)
    {
        int offset = address & 0x0F;
        switch (address & 0xF0)
        {
            case 0x90:
                if (offset == 2)
                {
                    byte irq = PendingIrq;
                    PendingIrq = 0;
                    return irq;
                }

                if (offset == 3)
                {
                    byte firq = PendingFirq;
                    PendingFirq = 0;
                    return firq;
                }

                return floating;
            case 0xA0:
                return (byte)((_mmu[offset] & 0x3F) | (floating & 0xC0));
            default:
                return (byte)((_palette[offset] & 0x3F) | (floating & 0xC0));
        }
    }

    /// <summary>
    ///  Reads a register without side effects.
    /// </summary>
    /// <param name="address">The address.</param>
    /// <param name="floating">The floating bus's value.</param>
    /// <returns>The value.</returns>
    public byte Peek(ushort address, byte floating) => (address & 0xF0) switch
    {
        0x90 when (address & 0x0F) == 2 => PendingIrq,
        0x90 when (address & 0x0F) == 3 => PendingFirq,
        0x90 => floating,
        0xA0 => (byte)((_mmu[address & 0x0F] & 0x3F) | (floating & 0xC0)),
        _ => (byte)((_palette[address & 0x0F] & 0x3F) | (floating & 0xC0))
    };

    /// <summary>
    ///  Writes a register at <c>$FF90-$FFBF</c>.
    /// </summary>
    /// <param name="address">The address.</param>
    /// <param name="value">The value.</param>
    public void Write(ushort address, byte value)
    {
        int offset = address & 0x0F;
        switch (address & 0xF0)
        {
            case 0x90:
                byte old = _registers[offset];
                _registers[offset] = value;
                switch (offset)
                {
                    case 1 when ((old ^ value) & 0x20) != 0:
                    case 4:
                        ResetTimer();
                        break;
                    case 2:
                        // Disabling a source acknowledges it, as reading does.
                        PendingIrq &= value;
                        break;
                    case 3:
                        PendingFirq &= value;
                        break;
                }

                return;
            case 0xA0:
                _mmu[offset] = value;
                return;
            default:
                _palette[offset] = (byte)(value & 0x3F);
                return;
        }
    }

    /// <summary>
    ///  Marks a source's rising edge, pending it as an IRQ, an FIRQ or both as <c>$FF92</c> and <c>$FF93</c>
    ///  enable it.
    /// </summary>
    /// <param name="source">The source's bit.</param>
    public void Raise(byte source)
    {
        if ((_registers[2] & source) != 0) { PendingIrq |= source; }
        if ((_registers[3] & source) != 0) { PendingFirq |= source; }
    }

    /// <summary>
    ///  Counts the timer down: once a line at the slow input, or twice a time unit (279 ns) at the fast one.
    /// </summary>
    /// <param name="units">Time units.</param>
    /// <param name="lineStarted">Whether a scanline started.</param>
    internal void Tick(int units, bool lineStarted)
    {
        if (_timer == 0) { return; }
        int ticks;
        if ((_registers[1] & 0x20) != 0)
        {
            ticks = units * 2;
        }
        else
        {
            ticks = lineStarted ? 1 : 0;
        }

        _timerHalfUnits += ticks;
        while (_timerHalfUnits > 0 && _timer > 0)
        {
            _timerHalfUnits--;
            if (--_timer == 0)
            {
                Raise(TimerInterrupt);
                Blink = !Blink;
                ResetTimer();
            }
        }

        _timerHalfUnits = 0;
    }

    /// <summary>
    ///  Gets whether blinking text is in its blank half; the timer's underflow toggles it.
    /// </summary>
    public bool Blink { get; private set; }

    /// <summary>
    ///  Clears every register and restores the MMU's default blocks, as RESET does.
    /// </summary>
    public void Reset()
    {
        _registers.AsSpan().Clear();
        _palette.AsSpan().Clear();
        for (int page = 0; page < 8; page++)
        {
            _mmu[page] = (byte)(0x38 + page);
            _mmu[page + 8] = (byte)(0x38 + page);
        }

        PendingIrq = 0;
        PendingFirq = 0;
        _timer = 0;
        _timerHalfUnits = 0;
        Blink = false;
    }

    // The 1987 GIME reloads the timer with its value plus one; zero stops it.
    private void ResetTimer()
    {
        int value = ((_registers[4] & 0x0F) << 8) | _registers[5];
        _timer = value == 0 ? 0 : value + 1;
    }
}
