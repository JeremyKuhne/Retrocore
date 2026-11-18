// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Cpu;
using Retrocore.Machines.Chips;

namespace Retrocore.Machines.Commodore;

/// <summary>
///  The PET 2001's memory map and I/O.
/// </summary>
/// <remarks>
///  <para>
///   RAM fills <c>$0000</c> up, 4K to 32K. The 1K of video RAM is at <c>$8000</c>, repeated to <c>$87FF</c>. ROM
///   fills <c>$9000-$FFFF</c> but for <c>$E800-$EFFF</c>, where address bit 4 selects PIA 1, bit 5 PIA 2 and bit 6
///   the VIA; a read that selects more than one sees their bytes ANDed, and one that selects none <c>$FF</c>. What
///   nothing answers reads <c>$00</c>, as in MAME.
///  </para>
///  <para>
///   PIA 1 (<c>$E810</c>): PA0-PA3 select the keyboard row, PA4 and PA5 sense the cassettes' keys, PA6 is EOI from
///   the IEEE-488 bus, PA7 the diagnostic sense line (high: no jumper); port B reads the row. CA1 is cassette 1's
///   read line, CA2 blanks the screen when low (and drives EOI), CB1 is VIDEO ON, whose falling edge starts vertical
///   blanking and interrupts, and CB2 runs cassette 1's motor. PIA 2 (<c>$E820</c>) carries the IEEE-488 data lines
///   and handshakes. VIA (<c>$E840</c>): port A is the user port; PB0 NDAC, PB6 NRFD and PB7 DAV in, PB1 NRFD and
///   PB2 ATN out, PB3 cassette write, PB4 cassette 2's motor, PB5 VIDEO ON in; CA2 selects the character set and
///   CB2 is the sound. PIA 2's port A reads the IEEE-488 data lines and port B drives them; CA2 drives NDAC and CB2
///   DAV, and CA1 and CB1 take ATN and SRQ.
///  </para>
/// </remarks>
public sealed class PetBus : IProcessorBus
{
    private const ushort VideoRamStart = 0x8000;

    private readonly byte[] _ram;
    private readonly byte[] _rom;
    private readonly PetModel _model;
    private readonly Ieee488Port _ieeePort;
    private int _frameCycle;

    /// <summary>
    ///  Creates the bus at power-on.
    /// </summary>
    /// <param name="roms">The ROMs.</param>
    /// <param name="model">The model, whose BASIC says where BASIC's ROM is, and which keyboard it has.</param>
    /// <param name="ramKilobytes">4, 8, 16 or 32.</param>
    internal PetBus(PetRoms roms, PetModel model, int ramKilobytes)
    {
        if (ramKilobytes is not (4 or 8 or 16 or 32))
        {
            throw new ArgumentOutOfRangeException(nameof(ramKilobytes), "The PET has 4K, 8K, 16K or 32K of RAM.");
        }

        _model = model;
        Keyboard = new(model.HasBusinessKeyboard());
        _ram = new byte[ramKilobytes * 1024];
        _rom = roms.Image.ToArray();

        // RAM comes up in runs of $00 and $FF, as MAME fills it.
        Fill(_ram);
        Fill(VideoRam);
        Video = new(VideoRam, roms.Characters);
        _ieeePort = Ieee.Attach();
        UpdateInputs();
    }

    /// <summary>
    ///  Gets RAM.
    /// </summary>
    public Span<byte> Ram => _ram;

    /// <summary>
    ///  Gets the 1K of video RAM.
    /// </summary>
    public byte[] VideoRam { get; } = new byte[0x400];

    /// <summary>
    ///  Gets PIA 1, at <c>$E810</c>: the keyboard, cassette 1 and the retrace interrupt.
    /// </summary>
    public Pia6821 Pia1 { get; } = new();

    /// <summary>
    ///  Gets PIA 2, at <c>$E820</c>: the IEEE-488 data lines.
    /// </summary>
    public Pia6821 Pia2 { get; } = new();

    /// <summary>
    ///  Gets the VIA, at <c>$E840</c>: the user port, the IEEE-488 handshakes, cassette 2 and the sound.
    /// </summary>
    public Via6522 Via { get; } = new();

    /// <summary>
    ///  Gets the IEEE-488 bus, which the PET controls.
    /// </summary>
    public Ieee488Bus Ieee { get; } = new();

    /// <summary>
    ///  Gets the keyboard.
    /// </summary>
    public PetKeyboard Keyboard { get; }

    /// <summary>
    ///  Gets the Datasette on cassette port 1, the 2001's built-in one.
    /// </summary>
    public PetDatasette Cassette1 { get; } = new(1);

    /// <summary>
    ///  Gets the Datasette on cassette port 2.
    /// </summary>
    public PetDatasette Cassette2 { get; } = new(2);

    /// <summary>
    ///  Gets the video.
    /// </summary>
    public PetVideo Video { get; }

    /// <summary>
    ///  Gets the sound.
    /// </summary>
    public PetAudio Audio { get; } = new();

    /// <summary>
    ///  Gets the cycle within the frame, 0 at the start of vertical blanking.
    /// </summary>
    public int FrameCycle => _frameCycle;

    /// <summary>
    ///  Gets whether VIDEO ON is high: the beam is in the 200 displayed lines.
    /// </summary>
    public bool VideoOn => _frameCycle >= PetTiming.BlankingCycles;

    /// <summary>
    ///  Gets whether a chip asserts IRQ.
    /// </summary>
    public bool InterruptRequested =>
        Via.InterruptRequested || Pia1.InterruptA || Pia1.InterruptB || Pia2.InterruptA || Pia2.InterruptB;

    /// <inheritdoc/>
    public byte Read(ushort address)
    {
        switch (address >> 12)
        {
            case < 8:
                return address < _ram.Length ? _ram[address] : (byte)0;
            case 8:
                if ((address & 0x800) != 0) { return 0; }
                byte value = VideoRam[address & 0x3FF];
                Snow(value);
                return value;
            case 0xE when (address & 0x800) != 0:
                return ReadIo(address);
            default:
                return _rom[address - PetRoms.Base];
        }
    }

    /// <inheritdoc/>
    public void Write(ushort address, byte value)
    {
        switch (address >> 12)
        {
            case < 8:
                if (address < _ram.Length) { _ram[address] = value; }
                return;
            case 8:
                if ((address & 0x800) != 0) { return; }
                VideoRam[address & 0x3FF] = value;
                Snow(value);
                return;
            case 0xE when (address & 0x800) != 0:
                UpdateInputs();
                if ((address & 0x10) != 0) { Pia1.Write(address & 3, value); }
                if ((address & 0x20) != 0) { Pia2.Write(address & 3, value); }
                if ((address & 0x40) != 0) { Via.Write((byte)(address & 0xF), value); }
                UpdateOutputs();
                return;
        }
    }

    /// <summary>
    ///  Reads without side effects, for the debugger.
    /// </summary>
    /// <param name="address">The address.</param>
    /// <returns>The byte a read would return.</returns>
    public byte Peek(ushort address)
    {
        if ((address & 0xF800) != 0xE800)
        {
            return address >> 12 == 8
                ? (address & 0x800) != 0 ? (byte)0 : VideoRam[address & 0x3FF]
                : address < 0x8000 ? address < _ram.Length ? _ram[address] : (byte)0 : _rom[address - PetRoms.Base];
        }

        UpdateInputs();
        byte data = 0xFF;
        if ((address & 0x10) != 0) { data &= Pia1.Peek(address & 3); }
        if ((address & 0x20) != 0) { data &= Pia2.Peek(address & 3); }
        if ((address & 0x40) != 0) { data &= Via.Peek((byte)(address & 0xF)); }
        return data;
    }

    /// <summary>
    ///  Gets what backs an address.
    /// </summary>
    /// <param name="address">The address.</param>
    /// <returns>The area.</returns>
    public PetMemoryArea Area(ushort address) => address switch
    {
        < 0x8000 => address < _ram.Length ? PetMemoryArea.Ram : PetMemoryArea.None,
        < 0x8800 => PetMemoryArea.VideoRam,
        < 0x9000 => PetMemoryArea.None,
        < 0xB000 => PetMemoryArea.OptionRom,
        < 0xC000 => _model.BasicVersion() == 4 ? PetMemoryArea.Basic : PetMemoryArea.OptionRom,
        < 0xE000 => PetMemoryArea.Basic,
        < 0xE800 => InBasic(address) ? PetMemoryArea.Basic : PetMemoryArea.Editor,
        < 0xF000 => PetMemoryArea.Io,
        _ => PetMemoryArea.Kernal
    };

    /// <summary>
    ///  Gets whether an address in the editor's chip, <c>$E000-$E7FF</c>, holds BASIC: BASIC runs on past
    ///  <c>$DFFF</c> with the end of its math package, its start-up and its sign-on, to <c>$E1E0</c> in BASIC 1 and
    ///  <c>$E1DD</c> in BASIC 2, and BASIC 1 keeps one more patch at <c>$E7F3-$E7F8</c>. BASIC 4 starts at
    ///  <c>$B000</c> and ends before the editor's chip.
    /// </summary>
    /// <param name="address">The address.</param>
    /// <returns>Whether it is BASIC's.</returns>
    private bool InBasic(ushort address) => _model.BasicVersion() switch
    {
        1 => address is < 0xE1E1 or (>= 0xE7F3 and < 0xE7F9),
        2 => address < 0xE1DE,
        _ => false
    };

    /// <summary>
    ///  Copies bytes into RAM or video RAM, for loading a program.
    /// </summary>
    /// <param name="address">The first address.</param>
    /// <param name="bytes">The bytes.</param>
    /// <exception cref="ArgumentException">An address the bytes would fill is not RAM.</exception>
    public void Load(ushort address, ReadOnlySpan<byte> bytes)
    {
        for (int index = 0; index < bytes.Length; index++)
        {
            int target = address + index;
            if (target > ushort.MaxValue || Area((ushort)target) is not (PetMemoryArea.Ram or PetMemoryArea.VideoRam))
            {
                throw new ArgumentException($"${target:X4} is not RAM.", nameof(bytes));
            }
        }

        for (int index = 0; index < bytes.Length; index++)
        {
            ushort target = (ushort)(address + index);
            if (target < 0x8000) { _ram[target] = bytes[index]; }
            else { VideoRam[target & 0x3FF] = bytes[index]; }
        }
    }

    /// <summary>
    ///  Resets the PIAs and the VIA, as the RESET line does.
    /// </summary>
    internal void ResetDevices()
    {
        Pia1.Reset();
        Pia2.Reset();
        Via.Reset();
        UpdateInputs();
        UpdateOutputs();
    }

    /// <summary>
    ///  Advances the devices and the beam one CPU cycle.
    /// </summary>
    internal void Tick()
    {
        Via.Tick();
        Keyboard.Tick();
        Audio.Tick(Via.CB2Output);
        TickCassettes();

        // A timer or an input edge can move the chips' outputs with no access: CA2's pulse mode, or a handshake on a
        // cassette's edge. ATN and SRQ reach PIA 2's control inputs as other devices move them.
        Video.Lowercase = Via.CA2Output;
        Video.Enabled = Pia1.CA2Output;
        bool atn = Ieee.High(Ieee488Lines.Atn);
        if (Pia2.CA1 != atn) { Pia2.CA1 = atn; }
        bool srq = Ieee.High(Ieee488Lines.Srq);
        if (Pia2.CB1 != srq) { Pia2.CB1 = srq; }

        bool wasOn = VideoOn;
        if (++_frameCycle == PetTiming.CyclesPerFrame) { _frameCycle = 0; }
        bool on = VideoOn;
        if (on != wasOn)
        {
            Pia1.CB1 = on;
            UpdateInputs();
        }

        if (on && (_frameCycle - PetTiming.BlankingCycles) % PetTiming.CyclesPerLine == 0)
        {
            Video.StartLine((_frameCycle - PetTiming.BlankingCycles) / PetTiming.CyclesPerLine);
        }
    }

    // Cassette 1's motor runs while PIA 1's CB2 is low, cassette 2's while the VIA's PB4 is; the VIA's PB3 writes to
    // both. Cassette 1 reads into PIA 1's CA1, cassette 2 into the VIA's CB1.
    private void TickCassettes()
    {
        byte portB = Via.PortBOutput;
        bool write = (portB & 0x08) != 0;
        Cassette1.Tick(motor: !Pia1.CB2Output, write);
        Cassette2.Tick(motor: (portB & 0x10) == 0, write);
        if (Pia1.CA1 != Cassette1.Read) { Pia1.CA1 = Cassette1.Read; }
        if (Via.CB1 != Cassette2.Read) { Via.CB1 = Cassette2.Read; }
    }

    private static void Fill(Span<byte> memory)
    {
        byte data = 0xFF;
        for (int offset = 0; offset < memory.Length; offset++)
        {
            memory[offset] = data;
            if (offset % 64 == 0) { data ^= 0xFF; }
        }
    }

    private byte ReadIo(ushort address)
    {
        UpdateInputs();
        byte data = 0xFF;
        if ((address & 0x10) != 0) { data &= Pia1.Read(address & 3); }
        if ((address & 0x20) != 0) { data &= Pia2.Read(address & 3); }
        if ((address & 0x40) != 0) { data &= Via.Read((byte)(address & 0xF)); }
        UpdateOutputs();
        return data;
    }

    // The levels the chips read from outside.
    private void UpdateInputs()
    {
        // PA4 and PA5 sense the cassettes' keys, low while one is down; PA6 is EOI; PA7: no diagnostic jumper.
        int eoi = Ieee.High(Ieee488Lines.Eoi) ? 0x40 : 0;
        Pia1.PortAInput = (byte)(0x80 | eoi | (Cassette1.KeyDown ? 0 : 0x10) | (Cassette2.KeyDown ? 0 : 0x20));
        Pia1.PortBInput = Keyboard.Read(Pia1.PortAOutput & 0x0F);

        Pia2.PortAInput = Ieee.Data;
        bool atn = Ieee.High(Ieee488Lines.Atn);
        if (Pia2.CA1 != atn) { Pia2.CA1 = atn; }
        bool srq = Ieee.High(Ieee488Lines.Srq);
        if (Pia2.CB1 != srq) { Pia2.CB1 = srq; }

        // PB0 NDAC, PB6 NRFD, PB7 DAV; PB1-PB4 are outputs, which read as MAME's zeros when made inputs.
        int ndac = Ieee.High(Ieee488Lines.Ndac) ? 0x01 : 0;
        int nrfd = Ieee.High(Ieee488Lines.Nrfd) ? 0x40 : 0;
        int dav = Ieee.High(Ieee488Lines.Dav) ? 0x80 : 0;
        Via.PortBInput = (byte)(ndac | nrfd | dav | (VideoOn ? 0x20 : 0));
    }

    private void UpdateOutputs()
    {
        Video.Lowercase = Via.CA2Output;
        Video.Enabled = Pia1.CA2Output;

        byte portB = Via.PortBOutput;
        _ieeePort.Data = Pia2.PortBOutput;
        _ieeePort.Drive(Ieee488Lines.Ndac, Pia2.CA2Output);
        _ieeePort.Drive(Ieee488Lines.Dav, Pia2.CB2Output);
        _ieeePort.Drive(Ieee488Lines.Eoi, Pia1.CA2Output);
        _ieeePort.Drive(Ieee488Lines.Nrfd, (portB & 0x02) != 0);
        _ieeePort.Drive(Ieee488Lines.Atn, (portB & 0x04) != 0);
    }

    // An access to video RAM while the beam draws a character shows the CPU's byte there instead.
    private void Snow(byte value)
    {
        if (!VideoOn) { return; }
        int cycle = (_frameCycle - PetTiming.BlankingCycles) % PetTiming.CyclesPerLine;
        int column = cycle - PetTiming.FirstColumnCycle;
        if (column is >= 0 and < 40)
        {
            Video.ShowSnow((_frameCycle - PetTiming.BlankingCycles) / PetTiming.CyclesPerLine, column, value);
        }
    }
}
