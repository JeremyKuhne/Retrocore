// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Cpu;
using Retrocore.Machines.Chips;

namespace Retrocore.Machines.Coco;

/// <summary>
///  The CoCo 1 and 2's bus: the SAM's memory map over RAM, the BASIC ROMs and the cartridge port, and the two PIAs
///  wired to the keyboard, video, sound, cassette and interrupts.
/// </summary>
/// <remarks>
///  <para>
///   Map type 0: RAM at <c>$0000-$7FFF</c> (the upper 32 KB of 64 when P1 is set), Extended Color BASIC at
///   <c>$8000-$9FFF</c>, Color BASIC at <c>$A000-$BFFF</c>, the cartridge at <c>$C000-$FEFF</c>, PIA 0 at
///   <c>$FF00</c> and PIA 1 at <c>$FF20</c> (each mirrored every 4 bytes), the cartridge's I/O at <c>$FF40</c>,
///   the SAM's switches at <c>$FFC0-$FFDF</c>, and the vectors from Color BASIC's last 32 bytes at
///   <c>$FFE0-$FFFF</c>. Map type 1 with 64 KB puts RAM over <c>$8000-$FEFF</c> too.
///  </para>
///  <para>
///   Unmapped addresses read the floating bus. On the hardware a dead cycle before most accesses leaves
///   <c>$FFFF</c>'s byte on it, so they read the reset vector's low byte, as this does.
///  </para>
///  <para>
///   PIA 0: port A bits 0-6 read the keyboard's rows and bit 7 the joystick comparator; port B strobes the
///   keyboard's columns; CA1 is HS and CB1 FS; CA2 and CB2 select the joystick and sound source; both IRQ outputs
///   drive the CPU's IRQ. PIA 1: port A bit 0 reads the cassette, bit 1 sends serial data and bits 2-7 drive the
///   DAC; port B bit 0 reads serial data, bit 1 drives single-bit sound, bit 2 reads the RAM-size strap, and bits
///   3-7 set the VDG's CSS, GM0-GM2 and A/G; CA2 runs the cassette motor and CB2 enables sound; both IRQ outputs
///   drive FIRQ; CB1 is the cartridge's CART line.
///  </para>
/// </remarks>
public sealed partial class CocoBus : IProcessorBus
{
    private readonly byte[] _ram;
    private readonly int _ramMask;
    private readonly byte[] _colorBasic;
    private readonly byte[] _extendedBasic;
    private readonly byte _floating;
    private readonly byte[] _rom3;
    private readonly CocoVideo? _video;
    private readonly Coco3Video? _video3;
    private int _keyboardVersion = -1;
    private bool _cartLine = true;

    /// <summary>
    ///  Builds the bus for a configuration and its ROMs.
    /// </summary>
    /// <param name="configuration">The configuration.</param>
    /// <param name="roms">The ROMs.</param>
    internal CocoBus(CocoConfiguration configuration, CocoRoms roms)
    {
        Configuration = configuration;
        _ram = new byte[configuration.RamBytes];

        // DRAM powers up holding no particular values; MAME fills it with $FF, and so does this, so that what
        // programs leave unwritten, such as the rest of a disk sector's buffer, matches.
        _ram.AsSpan().Fill(0xFF);
        _ramMask = _ram.Length - 1;
        _colorBasic = roms.ColorBasic.ToArray();
        _extendedBasic = roms.ExtendedBasic.ToArray();
        if (roms.IsCoco3)
        {
            _rom3 = roms.Coco3.ToArray();
            _floating = _rom3[0x7FFF];
            Gime = new();
            _video3 = new(this, Gime, configuration.RgbMonitor);
        }
        else
        {
            _rom3 = [];
            _floating = _colorBasic[0x1FFF];
            _video = new(this, configuration.LowercaseVdg, configuration.ArtifactColors);
        }

        Reset();
    }

    /// <summary>
    ///  Gets the configuration.
    /// </summary>
    public CocoConfiguration Configuration { get; }

    /// <summary>
    ///  Gets the SAM.
    /// </summary>
    public CocoSam Sam { get; } = new();

    /// <summary>
    ///  Gets PIA 0: the keyboard, joystick comparator and video sync.
    /// </summary>
    public Pia6821 Pia0 { get; } = new();

    /// <summary>
    ///  Gets PIA 1: the DAC, cassette, serial port, VDG mode and cartridge interrupt.
    /// </summary>
    public Pia6821 Pia1 { get; } = new();

    /// <summary>
    ///  Gets the keyboard.
    /// </summary>
    public CocoKeyboard Keyboard { get; } = new();

    /// <summary>
    ///  Gets the video.
    /// </summary>
    public CocoVideo Video => _video ?? throw new InvalidOperationException("The CoCo 3's video is Coco3Video.");

    /// <summary>
    ///  Gets the CoCo 3's video.
    /// </summary>
    public Coco3Video Coco3Video => _video3 ?? throw new InvalidOperationException("Only the CoCo 3 has the GIME's video.");

    /// <summary>
    ///  Gets the video output, whichever model.
    /// </summary>
    public IVideoSource VideoOutput => _video3 is not null ? _video3 : Video;

    /// <summary>
    ///  Gets the CoCo 3's GIME, or null for a CoCo 1 or 2.
    /// </summary>
    public CocoGime? Gime { get; }

    /// <summary>
    ///  Reads the text screen as characters, for the debugger.
    /// </summary>
    /// <returns>The rows.</returns>
    public string[] TextRows() => _video3 is not null ? _video3.TextRows() : Video.TextRows();

    /// <summary>
    ///  Gets the joysticks.
    /// </summary>
    public CocoJoysticks Joysticks { get; } = new();

    /// <summary>
    ///  Gets the cassette.
    /// </summary>
    public CocoCassette Cassette { get; } = new();

    /// <summary>
    ///  Gets the sound output.
    /// </summary>
    public CocoAudio Audio { get; } = new();

    /// <summary>
    ///  Gets or sets the ROM pack in the cartridge port, or null.
    /// </summary>
    public CocoCartridge? Cartridge { get; set; }

    /// <summary>
    ///  Gets or sets the disk controller cartridge, or null; a ROM pack in <see cref="Cartridge"/> takes the slot's
    ///  ROM space from it, as a Multi-Pak's switch would.
    /// </summary>
    public CocoDiskController? DiskController { get; set; }

    // The ROM in the cartridge slot.
    private CocoCartridge? Slot => Cartridge ?? DiskController?.Rom;

    /// <summary>
    ///  Gets the analog multiplexer's selection, PIA 0's CA2 in bit 0 and CB2 in bit 1: the joystick axis the
    ///  comparator reads, and the sound source (0 the DAC, 1 the cassette, 2 the cartridge, 3 none).
    /// </summary>
    public int MultiplexerSelection => (Pia0.CA2Output ? 1 : 0) | (Pia0.CB2Output ? 2 : 0);

    /// <summary>
    ///  Gets the sound level, -1 to 1: the multiplexer's source while PIA 1's CB2 enables sound, plus the
    ///  single-bit output on PIA 1's PB1.
    /// </summary>
    public float SoundLevel
    {
        get
        {
            float level = 0;
            if (Pia1.CB2Output)
            {
                level = MultiplexerSelection switch
                {
                    0 => (DacValue / 63f) - 0.5f,
                    1 => Cassette.Input ? 0.25f : -0.25f,
                    _ => 0
                };
            }

            return level + ((Pia1.PortBOutput & 0x02) != 0 && (Pia1.PortBDirection & 0x02) != 0 ? 0.25f : 0);
        }
    }

    /// <summary>
    ///  Gets the RAM.
    /// </summary>
    public Span<byte> Ram => _ram;

    /// <summary>
    ///  Gets Color BASIC's ROM, for the debugger to match against its source.
    /// </summary>
    internal ReadOnlySpan<byte> ColorBasicRom => _colorBasic;

    /// <summary>
    ///  Gets whether Extended Color BASIC's ROM is fitted.
    /// </summary>
    internal bool HasExtendedBasic => _extendedBasic.Length != 0;

    /// <summary>
    ///  Gets Extended Color BASIC's ROM, empty when none is fitted, for the debugger to match against its source.
    /// </summary>
    internal ReadOnlySpan<byte> ExtendedBasicRom => _extendedBasic;

    /// <summary>
    ///  Gets the CoCo 3's 32 KB ROM, empty on a CoCo 1 or 2, for the debugger to match against its source.
    /// </summary>
    internal ReadOnlySpan<byte> Coco3Rom => _rom3;

    /// <summary>
    ///  Gets the VDG's mode bits as PIA 1's port B drives them: CSS in bit 3, GM0-GM2 in bits 4-6 and A/G in bit 7.
    /// </summary>
    public byte VideoMode => (byte)(Pia1.PortBOutput & 0xF8);

    /// <summary>
    ///  Gets the 6-bit DAC's value, PIA 1's port A bits 2-7.
    /// </summary>
    public int DacValue => Pia1.PortAOutput >> 2;

    /// <summary>
    ///  Gets whether the cassette motor relay is closed (PIA 1's CA2).
    /// </summary>
    public bool CassetteMotor => Pia1.CA2Output;

    /// <summary>
    ///  Gets whether either PIA 0 output, or on a CoCo 3 the GIME, asks for an IRQ.
    /// </summary>
    public bool InterruptRequested => Pia0.InterruptA || Pia0.InterruptB || Gime is { InterruptRequested: true };

    /// <summary>
    ///  Gets whether either PIA 1 output, or on a CoCo 3 the GIME, asks for an FIRQ.
    /// </summary>
    public bool FastInterruptRequested =>
        Pia1.InterruptA || Pia1.InterruptB || Gime is { FastInterruptRequested: true };

    /// <summary>
    ///  Gets the time units the last access takes at the SAM's rate: 2 at the slow rate, 1 at the fast rate, and in
    ///  the address-dependent rate 2 for RAM and PIA 0 and 1 elsewhere.
    /// </summary>
    /// <param name="cycle">The CPU's last cycle.</param>
    /// <returns>The units.</returns>
    internal int CycleUnits(in ProcessorCycle cycle) => Sam.Rate switch
    {
        _ when Gime is not null => Sam.Rate == 0 ? CocoTiming.UnitsPerSlowCycle : 1,
        0 => CocoTiming.UnitsPerSlowCycle,
        1 => IsSlowAccess(in cycle) ? CocoTiming.UnitsPerSlowCycle : 1,
        _ => 1
    };

    // RAM and PIA 0 stay slow in the address-dependent rate; dead cycles run fast.
    private bool IsSlowAccess(in ProcessorCycle cycle)
    {
        if (cycle.Operation == BusOperation.None) { return false; }
        ushort address = cycle.Address;
        if ((address & 0xFFE0) == 0xFF00) { return true; }
        return address < 0x8000 || (Sam.MapType1 && Sam.MemorySize >= 2 && address < 0xFF00);
    }

    /// <inheritdoc/>
    public byte Read(ushort address)
    {
        if (Gime is not null) { return ReadCoco3(address); }
        if (address < 0x8000) { return _ram[LowRam(address)]; }
        if (address < 0xFF00) { return ReadHigh(address); }
        return address switch
        {
            < 0xFF20 => ReadPia0(address),
            < 0xFF40 => Pia1.Read(address & 3),
            < 0xFF60 => DiskController is { } disk ? disk.Read(address, _floating) : _floating,
            < 0xFFE0 => _floating,
            _ => _colorBasic[0x1FE0 + (address & 0x1F)]
        };
    }

    /// <inheritdoc/>
    public void Write(ushort address, byte value)
    {
        if (Gime is not null)
        {
            WriteCoco3(address, value);
            return;
        }

        if (address < 0x8000)
        {
            _ram[LowRam(address)] = value;
            return;
        }

        if (address < 0xFF00)
        {
            if (Sam.MapType1 && Sam.MemorySize >= 2) { _ram[address & _ramMask] = value; }
            return;
        }

        if (address < 0xFF20)
        {
            Pia0.Write(address & 3, value);
            RefreshKeyboard(force: true);
        }
        else if (address < 0xFF40)
        {
            Pia1.Write(address & 3, value);
        }
        else if (address < 0xFF60)
        {
            DiskController?.Write(address, value);
        }
        else if (address is >= 0xFFC0 and < 0xFFE0)
        {
            Sam.Write(address);
        }
    }

    /// <summary>
    ///  Reads what the CPU would see at an address, without side effects.
    /// </summary>
    /// <param name="address">The address.</param>
    /// <returns>The value.</returns>
    public byte Peek(ushort address)
    {
        if (Gime is not null) { return PeekCoco3(address); }
        if (address < 0x8000) { return _ram[LowRam(address)]; }
        if (address < 0xFF00) { return ReadHigh(address); }
        return address switch
        {
            < 0xFF20 => Pia0.Peek(address & 3),
            < 0xFF40 => Pia1.Peek(address & 3),
            < 0xFF60 => DiskController is { } disk ? disk.Peek(address, _floating) : _floating,
            < 0xFFE0 => _floating,
            _ => _colorBasic[0x1FE0 + (address & 0x1F)]
        };
    }

    /// <summary>
    ///  Gets what backs an address.
    /// </summary>
    /// <param name="address">The address.</param>
    /// <returns>The area.</returns>
    public CocoMemoryArea Area(ushort address) => Gime is not null ? AreaCoco3(address) : address switch
    {
        < 0x8000 => CocoMemoryArea.Ram,
        < 0xFF00 when Sam.MapType1 && Sam.MemorySize >= 2 => CocoMemoryArea.Ram,
        < 0xA000 => _extendedBasic.Length == 0 ? CocoMemoryArea.None : CocoMemoryArea.ExtendedBasic,
        < 0xC000 => CocoMemoryArea.ColorBasic,
        < 0xFF00 => Slot is null ? CocoMemoryArea.None : CocoMemoryArea.Cartridge,
        < 0xFF40 => CocoMemoryArea.Io,
        < 0xFF60 when DiskController is not null => CocoMemoryArea.Io,
        < 0xFFC0 => CocoMemoryArea.None,
        < 0xFFE0 => CocoMemoryArea.Io,
        _ => CocoMemoryArea.ColorBasic
    };

    /// <summary>
    ///  Reads RAM through the SAM's video address counter, which the memory size masks.
    /// </summary>
    /// <param name="counter">The counter's address.</param>
    /// <returns>The byte.</returns>
    internal byte VideoRead(int counter)
    {
        int address = Sam.MemorySize switch
        {
            0 => counter & 0x0FFF,
            1 => counter & 0x3FFF,
            _ => counter & 0xFFFF
        };

        return _ram[address & _ramMask];
    }

    /// <summary>
    ///  Advances the video and keyboard and passes the sync lines to PIA 0.
    /// </summary>
    /// <param name="units">The cycle's time units.</param>
    internal void Tick(int units)
    {
        if (_video3 is not null)
        {
            _video3.Tick(units);
            Pia0.CA1 = _video3.HorizontalSync;
            Pia0.CB1 = _video3.FieldSync;
        }
        else
        {
            Video.Tick(units);
            Pia0.CA1 = Video.HorizontalSync;
            Pia0.CB1 = Video.FieldSync;
        }

        Keyboard.Tick();
        RefreshKeyboard(force: false);
        Cassette.Tick(units, CassetteMotor, DacValue);
        Pia1.PortAInput = (byte)(Cassette.Input ? 0xFF : 0xFE);

        // A ROM pack ties CART to the Q clock, so CB1 sees an edge every cycle.
        if (Cartridge is { Autostart: true })
        {
            _cartLine = !_cartLine;
            Pia1.CB1 = _cartLine;
            if (_cartLine) { Gime?.Raise(CocoGime.CartridgeInterrupt); }
        }

        DiskController?.Tick(units);
        Audio.Tick(units, SoundLevel);
    }

    /// <summary>
    ///  Resets the SAM and PIAs, as the RESET button does; RAM is kept.
    /// </summary>
    internal void Reset()
    {
        Sam.Reset();
        Pia0.Reset();
        Pia1.Reset();
        Gime?.Reset();
        DiskController?.Reset();
        _video?.Reset();
        _video3?.Reset();
        UpdatePia1Inputs();
        RefreshKeyboard(force: true);
    }

    // $0000-$7FFF through the SAM: the memory size masks the address, P1 picks the upper half of 64 KB in map type
    // 0, and smaller RAM repeats.
    private int LowRam(ushort address)
    {
        int physical = Sam.MemorySize switch
        {
            0 => address & 0x0FFF,
            1 => address & 0x3FFF,
            _ => Sam.Page1 && !Sam.MapType1 ? address | 0x8000 : address
        };

        return physical & _ramMask;
    }

    private byte ReadHigh(ushort address)
    {
        if (Sam.MapType1 && Sam.MemorySize >= 2) { return _ram[address & _ramMask]; }
        if (address < 0xA000) { return _extendedBasic.Length == 0 ? _floating : _extendedBasic[address - 0x8000]; }
        if (address < 0xC000) { return _colorBasic[address - 0xA000]; }
        return Slot is { } cartridge ? cartridge.Read(address - 0xC000) : _floating;
    }

    private byte ReadPia0(ushort address)
    {
        RefreshKeyboard(force: true);
        return Pia0.Read(address & 3);
    }

    // The keyboard matrix connects port B's column strobes to port A's row inputs, and back for a reverse scan; the
    // joystick buttons pull rows low too, and PA7 reads the comparator.
    private void RefreshKeyboard(bool force)
    {
        if (!force && _keyboardVersion == Keyboard.Version) { return; }
        _keyboardVersion = Keyboard.Version;
        byte buttons = Joysticks.Buttons;
        Keyboard.Scan(Pia0.PortBOutput, (byte)(Pia0.PortAOutput & ~buttons), out byte rows, out byte columns);
        bool comparator = Joysticks.Axis(MultiplexerSelection) >= DacValue;
        byte input = (byte)(rows & ~buttons & 0x7F);

        // The GIME's keyboard interrupt fires as a row goes low.
        if (Gime is not null && (Pia0.PortAInput & ~input & 0x7F) != 0) { Gime.Raise(CocoGime.KeyboardInterrupt); }
        Pia0.PortAInput = (byte)((comparator ? 0x80 : 0) | input);
        Pia0.PortBInput = columns;
    }

    // RAMSZ (PIA 1 PB2) is strapped for the RAM chips: low for 4 KB chips, high for 16 KB, and PIA 0's PB6 for
    // 64 KB chips, which Color BASIC reads to choose the SAM's memory size.
    private void UpdatePia1Inputs()
    {
        bool sense = _ram.Length switch
        {
            < 0x4000 => false,
            < 0x8000 => true,
            _ => (Pia0.PortBOutput & 0x40) != 0
        };

        Pia1.PortBInput = (byte)(sense ? 0xFF : 0xFB);
    }

    /// <summary>
    ///  Updates inputs that follow other outputs; called after each CPU cycle.
    /// </summary>
    internal void AfterCycle() => UpdatePia1Inputs();
}
