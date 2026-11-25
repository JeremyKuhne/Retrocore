// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Cpu;
using Retrocore.Machines.Chips;

namespace Retrocore.Machines.Atari;

/// <summary>
///  The Atari 400 or 800's memory and chips, as the CPU and ANTIC see them.
/// </summary>
/// <remarks>
///  <para>
///   RAM from <c>$0000</c> up to its size; the cartridges at <c>$8000-$BFFF</c>, each unmapping the RAM under it;
///   GTIA at <c>$D000</c>, POKEY at <c>$D200</c>, the PIA at <c>$D300</c> and ANTIC at <c>$D400</c>, each mirrored
///   through its page; and the OS ROM at <c>$D800-$FFFF</c>. Nothing else is connected, and the data bus floats
///   there; as in MAME's <c>a800</c>, <c>$C000-$CFFF</c> reads <c>$00</c> and the rest (<c>$D100</c>,
///   <c>$D500-$D7FF</c>, missing RAM) <c>$FF</c>.
///  </para>
/// </remarks>
public sealed class AtariBus : IProcessorBus
{
    private const byte PageRam = 0;
    private const byte PageRom = 1;
    private const byte PageIo = 2;
    private const byte PageEmpty = 3;
    private const byte PageZero = 4;
    private const byte PageLeft = 5;
    private const byte PageRight = 6;
    private const byte PageCartridgeControl = 7;

    private readonly byte[] _memory = new byte[0x10000];
    private readonly byte[] _pages = new byte[256];
    private readonly Atari810[] _810s;
    private readonly int _cpuHertz;
    private int _driveClock;

    /// <summary>
    ///  Constructs the bus at power-on.
    /// </summary>
    /// <param name="roms">The OS ROM.</param>
    /// <param name="model">The model.</param>
    /// <param name="ramSize">The RAM in bytes: 8 KB to 48 KB, in 8 KB steps.</param>
    /// <param name="standard">The television standard.</param>
    /// <param name="chip">GTIA or CTIA.</param>
    /// <param name="left">The left (or the 400's only) cartridge, or null.</param>
    /// <param name="right">The 800's right cartridge, or null.</param>
    /// <param name="diskDrives">How many disk drives are on the serial bus, 0-4: <c>D1:</c> and up.</param>
    /// <param name="driveKind">How the disk drives are emulated.</param>
    /// <exception cref="ArgumentException">
    ///  810s are asked for and <paramref name="roms"/> has no 810 firmware.
    /// </exception>
    internal AtariBus(
        AtariRoms roms,
        AtariModel model,
        int ramSize,
        AtariVideoStandard standard,
        AtariGraphicsChip chip,
        AtariCartridge? left,
        AtariCartridge? right,
        int diskDrives,
        AtariDiskDriveKind driveKind)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(diskDrives);
        ArgumentOutOfRangeException.ThrowIfGreaterThan(diskDrives, 4);
        if (diskDrives != 0 && driveKind == AtariDiskDriveKind.Atari810 && roms.DiskDrive.IsEmpty)
        {
            throw new ArgumentException("The 810 needs its firmware; the ROMs have none.", nameof(roms));
        }

        if (ramSize is < 0x2000 or > 0xC000 || (ramSize & 0x1FFF) != 0)
        {
            throw new ArgumentOutOfRangeException(nameof(ramSize), "RAM is 8 KB to 48 KB in 8 KB steps.");
        }

        if (right is not null && (model == AtariModel.Atari400 || !right.IsRight))
        {
            throw new ArgumentException("Only the 800 has a right slot, and it takes a right-slot cartridge.", nameof(right));
        }

        if (left?.IsRight == true)
        {
            throw new ArgumentException("A right-slot cartridge goes in the right slot.", nameof(left));
        }

        Model = model;
        Roms = roms;
        RamSize = ramSize;
        Standard = standard;
        Left = left;
        Right = right;

        // Atari RAM powers on in no fixed state; MAME's reads all ones.
        _memory.AsSpan(0, ramSize).Fill(0xFF);
        _pages.AsSpan(0xC0, 0x10).Fill(PageZero);
        MapCartridges();

        _pages[0xD0] = PageIo;
        _pages[0xD1] = PageEmpty;
        _pages[0xD2] = PageIo;
        _pages[0xD3] = PageIo;
        _pages[0xD4] = PageIo;
        _pages[0xD5] = PageCartridgeControl;
        _pages.AsSpan(0xD6, 2).Fill(PageEmpty);
        MapRom(AtariRoms.Base, roms.Image);

        Gtia = new(chip, standard);
        Antic = new(this, Gtia, standard);
        Keyboard = new(Pokey, Gtia, Antic);
        Audio = new(this);
        Cassette = new(this);
        Sio = new(this);
        _cpuHertz = AtariTiming.CpuHertz(standard);
        AtariDiskDrive[] drives = new AtariDiskDrive[diskDrives];
        for (int drive = 0; drive < diskDrives; drive++)
        {
            if (driveKind == AtariDiskDriveKind.Atari810)
            {
                drives[drive] = new Atari810(this, drive + 1, roms.DiskDrive);
                continue;
            }

            AtariSioDiskDrive sio = new(this, drive + 1);
            Sio.Attach(sio);
            drives[drive] = sio;
        }

        Drives = drives;
        _810s = [.. drives.OfType<Atari810>()];
        Pia.PortAInput = 0xFF;
        Pia.PortBInput = 0xFF;
        Pia.CA1 = true;
        Pia.CB1 = true;
    }

    /// <summary>
    ///  Gets the model.
    /// </summary>
    public AtariModel Model { get; }

    /// <summary>
    ///  Gets the ROMs: the OS, the floating point package and the 810's firmware.
    /// </summary>
    public AtariRoms Roms { get; }

    /// <summary>
    ///  Gets the RAM in bytes.
    /// </summary>
    public int RamSize { get; }

    /// <summary>
    ///  Gets the television standard.
    /// </summary>
    public AtariVideoStandard Standard { get; }

    /// <summary>
    ///  Gets the left (or the 400's only) cartridge, or null.
    /// </summary>
    public AtariCartridge? Left { get; }

    /// <summary>
    ///  Gets the 800's right cartridge, or null.
    /// </summary>
    public AtariCartridge? Right { get; }

    /// <summary>
    ///  Gets ANTIC.
    /// </summary>
    public Antic Antic { get; }

    /// <summary>
    ///  Gets GTIA.
    /// </summary>
    public Gtia Gtia { get; }

    /// <summary>
    ///  Gets POKEY.
    /// </summary>
    public Pokey Pokey { get; } = new();

    /// <summary>
    ///  Gets the 6520 PIA: port A joysticks 1 and 2, port B joysticks 3 and 4, CA2 the SIO motor, CB2 the SIO command
    ///  line, CA1 the SIO proceed line and CB1 the SIO interrupt line.
    /// </summary>
    public Pia6821 Pia { get; } = new();

    /// <summary>
    ///  Gets the keyboard, console keys and SYSTEM RESET.
    /// </summary>
    public AtariKeyboard Keyboard { get; }

    /// <summary>
    ///  Gets the sound: POKEY and the console speaker.
    /// </summary>
    public AtariAudio Audio { get; }

    /// <summary>
    ///  Gets the serial bus.
    /// </summary>
    public AtariSioBus Sio { get; }

    /// <summary>
    ///  Gets the 410 Program Recorder on the serial bus.
    /// </summary>
    public Atari410 Cassette { get; }

    /// <summary>
    ///  Gets the disk drives on the serial bus, <c>D1:</c> first.
    /// </summary>
    public IReadOnlyList<AtariDiskDrive> Drives { get; }

    /// <summary>
    ///  Gets the machine cycles since power-on, DMA included.
    /// </summary>
    public long Cycles { get; private set; }

    /// <summary>
    ///  Gets whether a chip is asking for an IRQ: POKEY or either side of the PIA.
    /// </summary>
    public bool InterruptRequested => Pokey.InterruptRequest || Pia.InterruptA || Pia.InterruptB;

    /// <summary>
    ///  Sets the joysticks' directions, as port A and B read them: a clear bit for each direction pushed.
    /// </summary>
    /// <param name="stick">The joystick, 0-3.</param>
    /// <param name="directions">Bits 0-3: up, down, left, right, set when pushed.</param>
    public void SetJoystick(int stick, int directions)
    {
        ArgumentOutOfRangeException.ThrowIfGreaterThan((uint)stick, 3u);
        int shift = (stick & 1) * 4;
        int mask = 0x0F << shift;
        int bits = (~directions & 0x0F) << shift;
        if (stick < 2)
        {
            Pia.PortAInput = (byte)((Pia.PortAInput & ~mask) | bits);
        }
        else
        {
            Pia.PortBInput = (byte)((Pia.PortBInput & ~mask) | bits);
        }
    }

    /// <inheritdoc/>
    public byte Read(ushort address)
    {
        int page = address >> 8;
        return _pages[page] switch
        {
            PageRam or PageRom => _memory[address],
            PageIo => ReadIo(address),
            PageZero => 0x00,
            PageLeft => Left?.Read(address) ?? 0xFF,
            PageRight => Right?.Read(address) ?? 0xFF,
            PageCartridgeControl => CartridgeControl(address, value: null),
            _ => 0xFF
        };
    }

    /// <inheritdoc/>
    public void Write(ushort address, byte value)
    {
        switch (_pages[address >> 8])
        {
            case PageRam:
                _memory[address] = value;
                break;
            case PageIo:
                WriteIo(address, value);
                break;
            case PageCartridgeControl:
                CartridgeControl(address, value);
                break;
        }
    }

    /// <summary>
    ///  Reads memory without side effects, for the debugger.
    /// </summary>
    /// <param name="address">The address.</param>
    /// <returns>The value.</returns>
    public byte Peek(ushort address) => _pages[address >> 8] switch
    {
        PageRam or PageRom => _memory[address],
        PageIo => PeekIo(address),
        PageZero => 0x00,
        PageLeft => Left?.Read(address) ?? 0xFF,
        PageRight => Right?.Read(address) ?? 0xFF,
        _ => 0xFF
    };

    /// <summary>
    ///  Writes RAM directly, as a loader or the debugger does.
    /// </summary>
    /// <param name="address">The address.</param>
    /// <param name="value">The value; ignored where there is no RAM.</param>
    public void Poke(ushort address, byte value)
    {
        if (_pages[address >> 8] == PageRam) { _memory[address] = value; }
    }

    /// <summary>
    ///  Gets the memory area an address is in.
    /// </summary>
    /// <param name="address">The address.</param>
    /// <returns>The area.</returns>
    public AtariMemoryArea Area(ushort address) => address switch
    {
        >= 0xD800 => address >= 0xE000 ? AtariMemoryArea.OperatingSystem : AtariMemoryArea.FloatingPoint,
        >= 0xD000 => AtariMemoryArea.Io,
        >= 0xC000 => AtariMemoryArea.Empty,
        _ => _pages[address >> 8] switch
        {
            PageLeft => AtariMemoryArea.LeftCartridge,
            PageRight => AtariMemoryArea.RightCartridge,
            PageRam => AtariMemoryArea.Ram,
            _ => AtariMemoryArea.Empty
        }
    };

    /// <summary>
    ///  Reads for ANTIC's DMA: memory, or a register as it stands, without side effects.
    /// </summary>
    /// <param name="address">The address.</param>
    /// <returns>The value.</returns>
    internal byte DmaRead(ushort address) => _pages[address >> 8] switch
    {
        PageRam or PageRom => _memory[address],
        PageIo => PeekIo(address),
        PageZero => 0x00,
        PageLeft => Left?.Read(address) ?? 0xFF,
        PageRight => Right?.Read(address) ?? 0xFF,
        _ => 0xFF
    };

    /// <summary>
    ///  Ends a machine cycle: POKEY, the serial bus and its devices, and the sound move on.
    /// </summary>
    internal void Tick()
    {
        Cycles++;
        Pokey.Tick();
        Sio.Tick();
        Cassette.Tick();
        Audio.Tick();

        // Every device can pull the data-in line low; it's high when none does.
        bool level = Cassette.Level;
        if (_810s.Length != 0)
        {
            // The 810s run at 500 kHz, each cycle when its share of the machine's clock comes due.
            _driveClock += Atari810.ClockHertz;
            bool step = _driveClock >= _cpuHertz;
            if (step) { _driveClock -= _cpuHertz; }
            foreach (Atari810 drive in _810s)
            {
                if (step) { drive.StepCycle(); }
                level &= drive.SerialOutput;
            }
        }

        Pokey.SerialInputLevel = level;
    }

    // The Atari wires A0 to the PIA's port select and A1 to its control select: $D300 PORTA, $D301 PORTB,
    // $D302 PACTL, $D303 PBCTL.
    private static int PiaRegister(ushort address) => ((address & 1) << 1) | ((address >> 1) & 1);

    /// <summary>
    ///  Resets the cartridges to their power-on banks.
    /// </summary>
    internal void ResetCartridges()
    {
        Left?.Reset();
        Right?.Reset();
        MapCartridges();
    }

    // The cartridge control page: the left cartridge (or the right) switches banks, and the RAM under $8000-$BFFF
    // follows RD4 and RD5. Reads return $FF.
    private byte CartridgeControl(ushort address, byte? value)
    {
        bool changed = Left?.Control(address, value) == true;
        changed |= Right?.Control(address, value) == true;
        if (changed) { MapCartridges(); }
        return 0xFF;
    }

    // $8000-$9FFF: the right cartridge, the left one with RD4, or RAM; $A000-$BFFF: the left cartridge with RD5, or
    // RAM. RAM keeps its contents while a cartridge covers it.
    private void MapCartridges()
    {
        for (int page = 0; page < 0xC0; page++)
        {
            byte kind = page < RamSize >> 8 ? PageRam : PageEmpty;
            if (page >= 0x80 && page < 0xA0)
            {
                if (Right?.Rd4 == true)
                {
                    kind = PageRight;
                }
                else if (Left?.Rd4 == true)
                {
                    kind = PageLeft;
                }
            }
            else if (page >= 0xA0 && Left?.Rd5 == true)
            {
                kind = PageLeft;
            }

            _pages[page] = kind;
        }
    }

    private void MapRom(ushort start, ReadOnlySpan<byte> rom)
    {
        rom.CopyTo(_memory.AsSpan(start));
        _pages.AsSpan(start >> 8, rom.Length >> 8).Fill(PageRom);
    }

    private byte ReadIo(ushort address) => (address >> 8) switch
    {
        0xD0 => Gtia.Read(address),
        0xD2 => Pokey.Read(address & 0x0F),
        0xD3 => Pia.Read(PiaRegister(address)),
        _ => Antic.Read(address)
    };

    private byte PeekIo(ushort address) => (address >> 8) switch
    {
        0xD0 => Gtia.Read(address),
        0xD2 => Pokey.Peek(address & 0x0F),
        0xD3 => Pia.Peek(PiaRegister(address)),
        _ => Antic.Read(address)
    };

    private void WriteIo(ushort address, byte value)
    {
        switch (address >> 8)
        {
            case 0xD0:
                Gtia.Write(address, value, Antic.Cycle);
                break;
            case 0xD2:
                Pokey.Write(address & 0x0F, value);
                break;
            case 0xD3:
                Pia.Write(PiaRegister(address), value);
                break;
            default:
                Antic.Write(address, value);
                break;
        }
    }
}
