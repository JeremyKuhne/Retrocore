// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Cpu;
using Retrocore.Machines.Chips;
using Retrocore.Machines.Commodore.Serial;
using Retrocore.Media.Commodore;

namespace Retrocore.Machines.Commodore.Vic20;

/// <summary>
///  The VIC-20's memory map and I/O.
/// </summary>
/// <remarks>
///  <para>
///   RAM is at <c>$0000-$03FF</c> and <c>$1000-$1FFF</c>, with expansion RAM where <see cref="Vic20Expansion"/>
///   says, and a cartridge's ROM in the blocks it fills, over any RAM there. The character ROM is at <c>$8000-$8FFF</c>, the VIC at <c>$9000-$90FF</c> (repeating every 16 bytes), the
///   VIAs at <c>$9100-$93FF</c>, where address bit 4 selects VIA 1 and bit 5 VIA 2, the colour RAM's nybbles at
///   <c>$9400-$97FF</c>, BASIC at <c>$C000</c> and the kernal at <c>$E000</c>. A read that nothing answers sees the
///   byte the VIC fetched last, and so do a colour RAM read's top four bits.
///  </para>
///  <para>
///   The VIC sees 16K of its own: its addresses <c>$0000-$1FFF</c> are the processor's <c>$8000-$9FFF</c>, and
///   <c>$2000-$3FFF</c> the processor's <c>$0000-$1FFF</c>, since its address line 13 is wired to the inverse of
///   A15. So it can show the character ROM and the RAM on the board, but not the expansion port's: not the 3K at
///   <c>$0400</c>, nor anything in blocks 1-5.
///  </para>
///  <para>
///   VIA 1 (<c>$9110</c>), whose interrupt is the processor's NMI: PA0 and PA1 read the serial bus's CLK and DATA,
///   PA2-PA4 joystick up, down and left, PA5 its fire button, PA6 the cassette's key sense, and PA7 drives the bus's
///   ATN through an inverter; port B is the user port; CA1 is RESTORE and CA2 the cassette motor. VIA 2
///   (<c>$9120</c>), whose interrupt is the IRQ: port B drives the keyboard's columns (PB3 is also the cassette write
///   line, and PB7 reads joystick right), port A reads its rows; CA1 is the cassette read line, CA2 and CB2 drive the
///   bus's CLK and DATA through inverters, and CB1 reads SRQ.
///  </para>
/// </remarks>
public sealed class Vic20Bus : IProcessorBus, IVicMemory
{
    private readonly byte[] _memory = new byte[0x10000];
    private const byte Unmapped = 0;
    private const byte RamPage = 1;
    private const byte CartridgePage = 2;

    // What each 1K page is: nothing (the I/O and ROMs are decoded by address), RAM, or the cartridge's ROM, which is
    // copied into the memory array.
    private readonly byte[] _pages = new byte[64];
    private readonly byte[] _colourRam = new byte[0x400];
    private readonly byte[] _basic;
    private readonly byte[] _kernal;
    private readonly byte[] _characters;
    private bool _restore;

    /// <summary>
    ///  Creates the bus at power-on.
    /// </summary>
    /// <param name="roms">The ROMs.</param>
    /// <param name="standard">The video standard, which picks the 6560 or 6561.</param>
    /// <param name="expansion">The RAM in the expansion port.</param>
    /// <param name="cartridge">The cartridge, or null.</param>
    internal Vic20Bus(Vic20Roms roms, VicVideoStandard standard, Vic20Expansion expansion, Vic20Cartridge? cartridge)
    {
        Cartridge = cartridge;
        expansion |= cartridge?.Ram ?? Vic20Expansion.None;
        Expansion = expansion;
        _basic = roms.Basic.ToArray();
        _kernal = roms.Kernal.ToArray();
        _characters = roms.Characters.ToArray();

        MapRam(0x0000, 0x0400);
        MapRam(0x1000, 0x1000);
        if ((expansion & Vic20Expansion.Ram3K) != 0) { MapRam(0x0400, 0x0C00); }
        if ((expansion & Vic20Expansion.Block1) != 0) { MapRam(0x2000, 0x2000); }
        if ((expansion & Vic20Expansion.Block2) != 0) { MapRam(0x4000, 0x2000); }
        if ((expansion & Vic20Expansion.Block3) != 0) { MapRam(0x6000, 0x2000); }
        if ((expansion & Vic20Expansion.Block5) != 0) { MapRam(0xA000, 0x2000); }

        // RAM below $8000 comes up in runs of $00 and $FF; block 5's comes up as $00.
        byte data = 0xFF;
        for (int offset = 0; offset < 0x8000; offset++)
        {
            _memory[offset] = data;
            if (offset % 64 == 0) { data ^= 0xFF; }
        }

        if (cartridge is not null)
        {
            for (int address = 0x2000; address < 0xC000; address += 0x400)
            {
                if (!cartridge.Fills(address)) { continue; }
                _pages[address >> 10] = CartridgePage;
                for (int offset = 0; offset < 0x400; offset++)
                {
                    _memory[address + offset] = cartridge.Read(address + offset);
                }
            }
        }

        SerialPort = Serial.Attach();
        Vic = new(this, standard);
        Keyboard = new(Vic.CpuHertz);
        Cassette = new(
            "cassette",
            "Cassette",
            "VIA 2: CA1 reads the tape, PB3 writes; VIA 1: PA6 senses the keys, CA2 runs the motor",
            Vic.CpuHertz,
            TapFormat.Vic20Machine,
            standard == VicVideoStandard.Ntsc ? TapFormat.Ntsc : TapFormat.Pal);

        UpdateInputs();

        void MapRam(int start, int length)
        {
            for (int page = start >> 10; page < (start + length) >> 10; page++) { _pages[page] = RamPage; }
        }
    }

    /// <summary>
    ///  Gets the cartridge in the expansion port, or null.
    /// </summary>
    public Vic20Cartridge? Cartridge { get; }

    /// <summary>
    ///  Gets the Datasette on the cassette port.
    /// </summary>
    public CommodoreDatasette Cassette { get; }

    /// <summary>
    ///  Gets the RAM in the expansion port, with any a cartridge brings.
    /// </summary>
    public Vic20Expansion Expansion { get; }

    /// <summary>
    ///  Gets the VIC: the video, sound and paddles.
    /// </summary>
    public Vic6560 Vic { get; }

    /// <summary>
    ///  Gets VIA 1, at <c>$9110</c>: RESTORE, the joystick, the cassette's sense and motor, ATN and the user port.
    /// </summary>
    public Via6522 Via1 { get; } = new();

    /// <summary>
    ///  Gets VIA 2, at <c>$9120</c>: the keyboard, the jiffy timer, the cassette's read and write, CLK and DATA.
    /// </summary>
    public Via6522 Via2 { get; } = new();

    /// <summary>
    ///  Gets the keyboard.
    /// </summary>
    public Vic20Keyboard Keyboard { get; }

    /// <summary>
    ///  Gets or sets the joystick's switches.
    /// </summary>
    public CommodoreJoystick Joystick { get; set; }

    /// <summary>
    ///  Gets the colour RAM's nybbles.
    /// </summary>
    public Span<byte> ColourRam => _colourRam;

    /// <summary>
    ///  Gets whether VIA 2 asserts IRQ.
    /// </summary>
    public bool InterruptRequested => Via2.InterruptRequested;

    /// <summary>
    ///  Gets whether VIA 1 asserts NMI.
    /// </summary>
    public bool NonMaskableInterruptRequested => Via1.InterruptRequested;

    /// <summary>
    ///  Gets the serial bus, which the drives join.
    /// </summary>
    public SerialBus Serial { get; } = new();

    /// <summary>
    ///  Gets the VIC-20's connection to the serial bus: VIA 1's PA7 pulls ATN, VIA 2's CA2 CLK and its CB2 DATA,
    ///  each through an inverter.
    /// </summary>
    public SerialPort SerialPort { get; }

    /// <summary>
    ///  Gets the serial bus's ATN line: high unless VIA 1's PA7 or another device pulls it low.
    /// </summary>
    public bool Atn => Serial.High(SerialLines.Atn);

    /// <summary>
    ///  Gets the serial bus's CLK line: high unless VIA 2's CA2 or a device pulls it low.
    /// </summary>
    public bool Clock => Serial.High(SerialLines.Clock);

    /// <summary>
    ///  Gets the serial bus's DATA line: high unless VIA 2's CB2 or a device pulls it low.
    /// </summary>
    public bool Data => Serial.High(SerialLines.Data);

    /// <inheritdoc/>
    public byte Read(ushort address)
    {
        if (_pages[address >> 10] != Unmapped) { return _memory[address]; }
        switch (address >> 12)
        {
            case 8:
                return _characters[address & 0xFFF];
            case 9:
                return ReadIo(address, sideEffects: true);
            case 0xC or 0xD:
                return _basic[address & 0x1FFF];
            case 0xE or 0xF:
                return _kernal[address & 0x1FFF];
            default:
                return Vic.LastFetch;
        }
    }

    /// <inheritdoc/>
    public void Write(ushort address, byte value)
    {
        if (_pages[address >> 10] == RamPage)
        {
            _memory[address] = value;
            return;
        }

        if (address >> 12 != 9) { return; }
        switch ((address >> 8) & 0xF)
        {
            case 0:
                Vic.Write(address & 0xF, value);
                return;
            case 1 or 2 or 3:
                UpdateInputs();
                if ((address & 0x10) != 0) { Via1.Write((byte)(address & 0xF), value); }
                if ((address & 0x20) != 0) { Via2.Write((byte)(address & 0xF), value); }
                UpdateInputs();
                return;
            case 4 or 5 or 6 or 7:
                _colourRam[address & 0x3FF] = (byte)(value & 0x0F);
                return;
        }
    }

    /// <summary>
    ///  Reads without a read's side effects, such as clearing a VIA's interrupt flags, for the debugger. A read of
    ///  the VIAs still brings their inputs up to date with the serial bus and the joystick, as a read does.
    /// </summary>
    /// <param name="address">The address.</param>
    /// <returns>The byte a read would return.</returns>
    public byte Peek(ushort address) =>
        _pages[address >> 10] != Unmapped || address >> 12 != 9 ? Read(address) : ReadIo(address, sideEffects: false);

    /// <summary>
    ///  Gets what backs an address.
    /// </summary>
    /// <param name="address">The address.</param>
    /// <returns>The area.</returns>
    public Vic20MemoryArea Area(ushort address)
    {
        switch (_pages[address >> 10])
        {
            case RamPage:
                return address is < 0x0400 or (>= 0x1000 and < 0x2000) ? Vic20MemoryArea.Ram : Vic20MemoryArea.ExpansionRam;
            case CartridgePage:
                return Vic20MemoryArea.Cartridge;
        }

        return address switch
        {
            >= 0x8000 and < 0x9000 => Vic20MemoryArea.CharacterRom,
            >= 0x9000 and < 0x9100 => Vic20MemoryArea.Vic,
            >= 0x9100 and < 0x9400 => (address & 0x30) != 0 ? Vic20MemoryArea.Via : Vic20MemoryArea.None,
            >= 0x9400 and < 0x9800 => Vic20MemoryArea.ColourRam,
            >= 0xC000 and < 0xE000 => Vic20MemoryArea.Basic,
            >= 0xE000 => Vic20MemoryArea.Kernal,
            _ => Vic20MemoryArea.None
        };
    }

    /// <summary>
    ///  Copies bytes into RAM, for loading a program.
    /// </summary>
    /// <param name="address">The first address.</param>
    /// <param name="bytes">The bytes.</param>
    /// <exception cref="ArgumentException">An address the bytes would fill is not RAM.</exception>
    public void Load(ushort address, ReadOnlySpan<byte> bytes)
    {
        for (int index = 0; index < bytes.Length; index++)
        {
            int target = address + index;
            if (target > ushort.MaxValue || _pages[target >> 10] != RamPage)
            {
                throw new ArgumentException($"${target:X4} is not RAM.", nameof(bytes));
            }
        }

        bytes.CopyTo(_memory.AsSpan(address));
    }

    /// <inheritdoc/>
    byte IVicMemory.FetchVideo(int address)
    {
        // The VIC's A13 is the processor's A15 inverted, so its $0000-$1FFF is the processor's $8000-$9FFF: the
        // character ROM, then the I/O, which answers it nothing, and colour RAM, whose four bits it reads under the
        // high nybble left on its bus. What answers nothing, there and where the expansion's 3K would be, reads as
        // the chip's last fetch, as the processor's reads do (see Vic6560's remarks for how MAME differs).
        if ((address & 0x2000) == 0)
        {
            return address switch
            {
                < 0x1000 => _characters[address],
                >= 0x1400 and < 0x1800 => (byte)((Vic.LastFetch & 0xF0) | (_colourRam[address & 0x3FF] & 0x0F)),
                _ => Vic.LastFetch
            };
        }

        int cpu = address & 0x1FFF;
        return cpu is < 0x0400 or >= 0x1000 ? _memory[cpu] : Vic.LastFetch;
    }

    /// <inheritdoc/>
    byte IVicMemory.FetchColour(int address) => _colourRam[address];

    /// <summary>
    ///  Resets the VIAs, as the RESET line does.
    /// </summary>
    internal void ResetDevices()
    {
        Via1.Reset();
        Via2.Reset();
        UpdateInputs();
    }

    /// <summary>
    ///  Advances the devices one bus cycle.
    /// </summary>
    internal void Tick()
    {
        Via1.Tick();
        Via2.Tick();
        Cassette.Tick(motor: !Via1.CA2Output, write: (Via2.PortBOutput & 0x08) != 0);
        if (Via2.CA1 != Cassette.Read) { Via2.CA1 = Cassette.Read; }
        Vic.Tick();
        Keyboard.Tick();
        if (_restore != Keyboard.Restore)
        {
            _restore = Keyboard.Restore;
            Via1.CA1 = !_restore;
        }

        // A timer can move CA2 and CB2, which drive the serial bus the inputs read back.
        UpdateInputs();
    }

    private byte ReadIo(ushort address, bool sideEffects)
    {
        switch ((address >> 8) & 0xF)
        {
            case 0:
                return Vic.Read(address & 0xF);
            case 1 or 2 or 3:
                if ((address & 0x30) == 0) { return Vic.LastFetch; }
                UpdateInputs();
                byte data = 0xFF;
                byte register = (byte)(address & 0xF);
                if ((address & 0x10) != 0) { data &= sideEffects ? Via1.Read(register) : Via1.Peek(register); }
                if ((address & 0x20) != 0) { data &= sideEffects ? Via2.Read(register) : Via2.Peek(register); }
                if (sideEffects) { UpdateInputs(); }
                return data;
            case 4 or 5 or 6 or 7:
                return (byte)((Vic.LastFetch & 0xF0) | _colourRam[address & 0x3FF]);
            default:
                return Vic.LastFetch;
        }
    }

    /// <summary>
    ///  Sets the serial bus's levels VIA 1's PA0 and PA1 and VIA 2's CB1 read, as a drive's cycle can change them.
    /// </summary>
    internal void UpdateSerialInputs()
    {
        SerialLines low = Serial.Low;
        int clock = (low & SerialLines.Clock) == 0 ? 0x01 : 0;
        int data = (low & SerialLines.Data) == 0 ? 0x02 : 0;
        Via1.PortAInput = (byte)((Via1.PortAInput & 0xFC) | clock | data);
        bool srq = (low & SerialLines.Srq) == 0;
        if (Via2.CB1 != srq) { Via2.CB1 = srq; }
    }

    /// <summary>
    ///  Sets the levels the VIAs read from outside, after pulling the serial bus's lines as they drive them.
    /// </summary>
    internal void UpdateInputs()
    {
        CommodoreJoystick joystick = Joystick;
        SerialPort.Pull(SerialLines.Atn, (Via1.PortAOutput & 0x80) != 0);
        SerialPort.Pull(SerialLines.Clock, Via2.CA2Output);
        SerialPort.Pull(SerialLines.Data, Via2.CB2Output);
        bool srq = Serial.High(SerialLines.Srq);
        if (Via2.CB1 != srq) { Via2.CB1 = srq; }

        // VIA 1's port A: CLK and DATA as the bus has them, the joystick's switches low while closed, the cassette's
        // sense low while a key is down, and ATN out.
        int portA1 = (Clock ? 0x01 : 0) | (Data ? 0x02 : 0) | (Cassette.KeyDown ? 0 : 0x40) | 0x80;
        if ((joystick & CommodoreJoystick.Up) == 0) { portA1 |= 0x04; }
        if ((joystick & CommodoreJoystick.Down) == 0) { portA1 |= 0x08; }
        if ((joystick & CommodoreJoystick.Left) == 0) { portA1 |= 0x10; }
        if ((joystick & CommodoreJoystick.Fire) == 0) { portA1 |= 0x20; }
        Via1.PortAInput = (byte)portA1;

        // VIA 2: the rows for the columns port B drives; PB7 reads joystick right.
        Via2.PortAInput = Keyboard.ReadRows(Via2.PortBOutput);
        Via2.PortBInput = (joystick & CommodoreJoystick.Right) != 0 ? (byte)0x7F : (byte)0xFF;
    }
}
