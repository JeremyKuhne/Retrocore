// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Cpu;

namespace Retrocore.Machines.Trs80;

/// <summary>
///  The Model III family's memory maps and ports.
/// </summary>
/// <remarks>
///  <para>
///   A Model III has the ROM at <c>$0000</c>-<c>$37FF</c> (printer status at <c>$37E8</c>), the keyboard at
///   <c>$3800</c>, 1K of video RAM at <c>$3C00</c> and RAM from <c>$4000</c>. A Model 4 selects one of four maps
///   with port <c>$84</c>: map 0 is the Model III's; map 1 writes RAM under the ROM; map 2 is RAM to <c>$F3FF</c>
///   with the keyboard at <c>$F400</c> and 2K of video RAM at <c>$F800</c>; map 3 is all RAM. With 128K, port
///   <c>$84</c> bits 4-6 swap a 32K half of the second 64K into either half of the address space. The 4P's ROM is
///   a 4K boot loader that port <c>$9C</c> bit 0 switches out.
///  </para>
///  <para>
///   The ports are the interrupt mask and status (<c>$E0</c>: bit 2 the 30 Hz clock), the disk NMI mask and
///   status (<c>$E4</c>: bit 7 the controller's INTRQ, bit 6 the motor timeout, bit 5 reset), the RS-232 board's
///   UART (<c>$E8</c>-<c>$EB</c>, reading <c>$FF</c> as with no board fitted), the options latch (<c>$EC</c>: bit 1 cassette motor, bit 2
///   wide characters, bit 3 alternate characters, bit 6 the Model 4's 4 MHz; a read acknowledges the clock), the
///   FD1793 (<c>$F0</c>-<c>$F3</c>), drive select (<c>$F4</c>: bits 0-3 drive, bit 4 side, bit 6 wait, bit 7
///   double density), the printer (<c>$F8</c>) and the cassette (<c>$FF</c>); and on a Model 4 the memory map
///   (<c>$84</c>), the 6845 (<c>$88</c>-<c>$89</c>) and the speaker (<c>$90</c>).
///  </para>
/// </remarks>
public sealed class Trs80Model3Bus : IProcessorBus, IIoBus
{
    private const byte PrinterIdle = 0x30;
    private const byte ClockInterrupt = 0x04;
    private const byte CassetteRiseInterrupt = 0x01;
    private const byte CassetteFallInterrupt = 0x02;
    private const byte IntrqNmi = 0x80;
    private const byte MotorTimeoutNmi = 0x40;
    private const byte ResetNmi = 0x20;

    private readonly Trs80Model3Configuration _configuration;
    private readonly byte[] _rom;
    private readonly byte[] _ram;
    private readonly bool _model4;
    private readonly bool _model4P;
    private readonly bool _banked;
    private readonly bool _controller;

    private int _tick;
    private byte _interruptMask;
    private byte _interrupts;
    private byte _nmiMask;
    private byte _options;
    private bool _motorTimedOut;
    private bool _wasMotorOn;
    // The reset button's signal: device T-states left before the press ends, if the ROM has not read port $E4.
    private int _resetLatched;

    // How long a press of the reset button lasts, about 20 ms.
    private const int ResetPressTicks = Trs80Model3Timing.ClockHertz / 50;
    private bool _waitRequested;

    // Model 4: port $84 and the 4P's port $9C.
    private int _map;
    private int _paging;
    private bool _bootRom = true;

    /// <summary>
    ///  Creates the bus.
    /// </summary>
    /// <param name="configuration">The machine's options.</param>
    /// <param name="roms">The ROM and the character generator.</param>
    internal Trs80Model3Bus(Trs80Model3Configuration configuration, Trs80Model3Roms roms)
    {
        _configuration = configuration;
        _rom = roms.System.ToArray();
        _model4 = configuration.IsModel4;
        _model4P = configuration.Variant == Trs80Model3Variant.Model4P;
        _ram = new byte[configuration.RamKilobytes * 1024];
        _banked = _model4 && configuration.RamKilobytes == 128;
        _controller = configuration.DiskController;
        Video = new(roms.CharacterGenerator, _model4);
        Keyboard = new(Trs80Model3Timing.ClockHertz);
        bool level1 = configuration.Rom == Trs80Rom.Level1;
        Cassette = new(level1 ? 250 : 500, Trs80Model3Timing.ClockHertz, highSpeed: !level1);
        Disks = new(Trs80Doubler.None, Trs80Model3Timing.ClockHertz, wd179x: true);
    }

    /// <summary>
    ///  Gets whether the disk controller is fitted.
    /// </summary>
    public bool HasDiskController => _controller;

    /// <summary>
    ///  Gets the keyboard.
    /// </summary>
    public Trs80Keyboard Keyboard { get; }

    /// <summary>
    ///  Gets the video.
    /// </summary>
    public Trs80Model3Video Video { get; }

    /// <summary>
    ///  Gets the cassette interface.
    /// </summary>
    public Trs80Cassette Cassette { get; }

    /// <summary>
    ///  Gets the FD1793 and its drives.
    /// </summary>
    public Trs80DiskController Disks { get; }

    /// <summary>
    ///  Gets the bytes sent to the printer.
    /// </summary>
    public List<byte> PrinterOutput { get; } = [];

    /// <summary>
    ///  Gets whether the Model 4 runs at 4 MHz (port <c>$EC</c> bit 6).
    /// </summary>
    public bool Fast => _model4 && (_options & 0x40) != 0;

    /// <summary>
    ///  Gets the speaker's level, which port <c>$90</c> bit 0 drives on a Model 4.
    /// </summary>
    public bool Speaker { get; private set; }

    /// <summary>
    ///  Gets the Model 4's memory map, 0-3 (port <c>$84</c> bits 0-1); a Model III's is always 0.
    /// </summary>
    public int Map => _map;

    /// <summary>
    ///  Gets whether the Model 4P's boot ROM is switched in (port <c>$9C</c> bit 0).
    /// </summary>
    public bool BootRomEnabled => _model4P && _bootRom;

    /// <summary>
    ///  Gets whether an enabled device requests a maskable interrupt.
    /// </summary>
    public bool InterruptRequested => (_interrupts & _interruptMask) != 0;

    /// <summary>
    ///  Gets whether an enabled disk event, or the reset button, requests a non-maskable interrupt.
    /// </summary>
    public bool NmiRequested => (NmiStatus() & (_nmiMask | ResetNmi)) != 0;

    /// <summary>
    ///  Gets whether drive select's wait holds the CPU until the controller asks for data or finishes.
    /// </summary>
    public bool WaitRequested => _waitRequested && !Disks.DataRequest && !Disks.InterruptRequest;

    /// <inheritdoc/>
    public byte Read(ushort address)
    {
        switch (Area(address))
        {
            case Trs80Model3MemoryArea.Rom:
                // Level I's 4K ROM leaves the ROM space above it empty.
                return address < _rom.Length ? _rom[address] : (byte)0xFF;
            case Trs80Model3MemoryArea.Printer:
                return PrinterIdle;
            case Trs80Model3MemoryArea.Keyboard:
                return Keyboard.Read(address);
            case Trs80Model3MemoryArea.Video:
                return Video.Read(VideoOffset(address));
            case Trs80Model3MemoryArea.Ram:
                return _ram[Physical(address)];
            default:
                return 0xFF;
        }
    }

    /// <inheritdoc/>
    public void Write(ushort address, byte value)
    {
        if (WriteArea(address) is { } physical)
        {
            _ram[physical] = value;
            return;
        }

        if (Area(address) == Trs80Model3MemoryArea.Video) { Video.Write(VideoOffset(address), value); }
        else if (Area(address) == Trs80Model3MemoryArea.Printer) { PrinterOutput.Add(value); }
    }

    /// <summary>
    ///  Reads without side effects, for the debugger.
    /// </summary>
    /// <param name="address">The address.</param>
    /// <returns>The byte a read would return.</returns>
    public byte Peek(ushort address) => Read(address);

    /// <summary>
    ///  Gets the region an address reads from.
    /// </summary>
    /// <param name="address">The address.</param>
    /// <returns>The region.</returns>
    public Trs80Model3MemoryArea Area(ushort address)
    {
        if (_map >= 2)
        {
            if (_map == 2 && address >= 0xF400)
            {
                return address >= 0xF800 ? Trs80Model3MemoryArea.Video : Trs80Model3MemoryArea.Keyboard;
            }

            return RamArea(address);
        }

        if (address >= 0x4000) { return RamArea(address); }
        if (address >= 0x3C00) { return Trs80Model3MemoryArea.Video; }
        if (address >= 0x3800) { return Trs80Model3MemoryArea.Keyboard; }
        if (address is 0x37E8 or 0x37E9) { return Trs80Model3MemoryArea.Printer; }
        if (!_model4P) { return Trs80Model3MemoryArea.Rom; }

        // The 4P's boot ROM fills only the first 4K; the rest of the ROM space reads RAM.
        return _bootRom && address < Trs80Model3Roms.BootSize ? Trs80Model3MemoryArea.Rom : RamArea(address);
    }

    /// <inheritdoc/>
    public byte In(ushort port)
    {
        byte low = (byte)port;
        switch (low)
        {
            case >= 0xE0 and <= 0xE3:
                return (byte)~(_interrupts & _interruptMask);
            case >= 0xE4 and <= 0xE7:
            {
                byte status = NmiStatus();
                _motorTimedOut = false;
                _resetLatched = 0;
                return (byte)~status;
            }

            // No RS-232 board: the UART's ports read $FF, which the ROM's set-up takes as none fitted.
            case >= 0xE8 and <= 0xEB:
                return 0xFF;
            case >= 0xEC and <= 0xEF:
                _interrupts &= unchecked((byte)~ClockInterrupt);
                return 0xFF;
            case >= 0xF0 and <= 0xF3:
                return _controller ? Disks.Read(low - 0xF0) : (byte)0xFF;
            case >= 0xF8 and <= 0xFB:
                return PrinterIdle;
            case >= 0xFC:
                return ReadCassette();
            default:
                return 0xFF;
        }
    }

    /// <inheritdoc/>
    public void Out(ushort port, byte value)
    {
        byte low = (byte)port;
        switch (low)
        {
            case >= 0x84 and <= 0x87 when _model4:
                MemoryControl(value);
                break;
            case >= 0x88 and <= 0x8B when _model4:
                Video.CrtcWrite((low & 1) != 0, value);
                break;
            case >= 0x90 and <= 0x93 when _model4:
                Speaker = (value & 1) != 0;
                break;
            case >= 0x9C and <= 0x9F when _model4P:
                _bootRom = (value & 1) != 0;
                break;
            case >= 0xE0 and <= 0xE3:
                _interruptMask = value;
                break;
            case >= 0xE4 and <= 0xE7:
                _nmiMask = value;
                break;
            case >= 0xEC and <= 0xEF:
                _options = value;
                Video.WideCharacters = (value & 0x04) != 0;
                Video.AlternateCharacters = (value & 0x08) != 0;
                if (!_model4P) { Cassette.SetMotor((value & 0x02) != 0); }
                break;
            case >= 0xF0 and <= 0xF3 when _controller:
                Disks.Write(low - 0xF0, value);
                break;
            case >= 0xF4 and <= 0xF7 when _controller:
                DriveSelect(value);
                break;
            case >= 0xF8 and <= 0xFB:
                PrinterOutput.Add(value);
                break;
            case >= 0xFC:
                if (_model4P) { Speaker = (value & 1) != 0; }
                else { Cassette.WriteLevel(value); }

                break;
        }
    }

    // Port $FF: bit 7 the 500 baud latch, bit 0 the 1500 baud level. Reading acknowledges the 1500 baud edges.
    private byte ReadCassette()
    {
        _interrupts &= unchecked((byte)~(CassetteRiseInterrupt | CassetteFallInterrupt));
        return (byte)((Cassette.Latch ? 0x80 : 0) | (_options & 0x7E) | (Cassette.Level ? 0x01 : 0));
    }

    /// <summary>
    ///  Holds the reset button's signal until the NMI handler reads port <c>$E4</c>, or the press ends for a handler
    ///  that does not read it, as Level I's does not, so the next press raises the NMI again.
    /// </summary>
    internal void PressReset() => _resetLatched = ResetPressTicks;

    /// <summary>
    ///  Advances the devices one device T-state.
    /// </summary>
    internal void Tick()
    {
        Video.Tick();
        Keyboard.Tick();
        if (_resetLatched > 0) { _resetLatched--; }
        if (!_model4P)
        {
            Cassette.Tick();

            // A 1500 baud edge latches its interrupt when the mask enables it, until port $FF is read.
            byte edges = (byte)((Cassette.Rose ? CassetteRiseInterrupt : 0) | (Cassette.Fell ? CassetteFallInterrupt : 0));
            _interrupts |= (byte)(edges & _interruptMask);
            Cassette.TakeEdges();
        }

        if (++_tick == Trs80Model3Timing.CyclesPerTick)
        {
            _tick = 0;
            _interrupts |= ClockInterrupt;
        }

        if (!_controller) { return; }
        Disks.Tick();
        bool motor = Disks.MotorOn;
        if (_wasMotorOn && !motor) { _motorTimedOut = true; }
        _wasMotorOn = motor;
    }

    private byte NmiStatus()
    {
        int status = _controller && Disks.InterruptRequest ? IntrqNmi : 0;
        if (_motorTimedOut) { status |= MotorTimeoutNmi; }
        if (_resetLatched > 0) { status |= ResetNmi; }
        return (byte)status;
    }

    private void DriveSelect(byte value)
    {
        int drive = (value & 0x0F) switch
        {
            0x01 => 0,
            0x02 => 1,
            0x04 => 2,
            0x08 => 3,
            _ => -1
        };

        Disks.SelectTimed(drive, (value >> 4) & 1, (value & 0x80) != 0);
        _waitRequested = (value & 0x40) != 0;
        _motorTimedOut = false;
    }

    // Port $84: bits 0-1 the map, 2 80x24, 3 inverse video, 4-6 paging, 7 the video page.
    private void MemoryControl(byte value)
    {
        _map = value & 0x03;
        _paging = (value >> 4) & 0x07;
        Video.Eighty = (value & 0x04) != 0;
        Video.Inverse = (value & 0x08) != 0;
        Video.Page = value >> 7;
    }

    private int VideoOffset(ushort address) => _map == 2 ? address - 0xF800 : (Video.Page << 10) | (address & 0x3FF);

    private Trs80Model3MemoryArea RamArea(ushort address) => Physical(address) < _ram.Length
        ? Trs80Model3MemoryArea.Ram
        : Trs80Model3MemoryArea.Unmapped;

    // Where RAM writes go: maps 1-3 write RAM wherever ROM would read, and a 4P writes the RAM under its boot ROM
    // in map 1. Map 0 writes RAM only where it reads RAM.
    private int? WriteArea(ushort address)
    {
        Trs80Model3MemoryArea area = Area(address);
        if (area == Trs80Model3MemoryArea.Ram)
        {
            // In map 0 a 4P's RAM in the ROM space reads but cannot be written.
            return _model4P && _map == 0 && address < 0x3800 ? null : Physical(address);
        }

        if (area == Trs80Model3MemoryArea.Rom && _model4 && _map == 1)
        {
            int physical = Physical(address);
            return physical < _ram.Length ? physical : null;
        }

        return null;
    }

    // The physical RAM behind an address. A Model III's RAM starts at $4000; a Model 4's fills the address space,
    // and with 128K, paging (port $84 bit 5) puts the second 64K's lower (bit 4 clear) or upper 32K in the upper
    // (bit 6 clear) or lower half.
    private int Physical(ushort address)
    {
        if (!_model4) { return address - 0x4000; }
        if (!_banked || (_paging & 0x02) == 0) { return address; }
        bool lowerHalf = (_paging & 0x04) != 0;
        if (lowerHalf != (address < 0x8000)) { return address; }
        return 0x10000 + ((_paging & 0x01) << 15) + (address & 0x7FFF);
    }
}
