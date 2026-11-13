// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Cpu;
using Retrocore.Machines.Trs80.Chips;

namespace Retrocore.Machines.Trs80;

/// <summary>
///  The Model II family's memory and ports.
/// </summary>
/// <remarks>
///  <para>
///   The boot ROM reads at <c>$0000</c>-<c>$07FF</c> until port <c>$F9</c> bit 0 is cleared; RAM is under it, and the
///   first 32K of RAM is always at <c>$0000</c>-<c>$7FFF</c>. Port <c>$FF</c> bits 0-3 select the 32K bank at
///   <c>$8000</c> (bank 0 is none), bit 7 maps the 2K of video RAM over <c>$F800</c>-<c>$FFFF</c>, bit 6 blanks
///   the display, bit 5 enables the real-time clock's interrupt and bit 4 selects 40 columns. Reading it returns bit
///   7 the keyboard interrupt, 6 the display enable, 5 and 4 as written.
///  </para>
///  <para>
///   The other ports are the PIO (<c>$E0</c>-<c>$E3</c>: port A reads the disk controller's INTRQ, a two-sided
///   disk and disk change), the FD1791 (<c>$E4</c>-<c>$E7</c>, whose inverted data bus the board inverts back), drive select
///   (<c>$EF</c>: bits 0-3 drives, active low, bit 6 clear side 1, bit 7 double density), the CTC
///   (<c>$F0</c>-<c>$F3</c>, channel 3 counting keyboard interrupts), the SIO (<c>$F4</c>-<c>$F7</c>), the DMA
///   (<c>$F8</c>, ready on the disk controller's DRQ), the ROM switch (<c>$F9</c>), the keyboard and 6845 address
///   (<c>$FC</c>), the 6845's registers (<c>$FD</c>) and the clock acknowledge (<c>$FE</c>). Interrupts chain from
///   the CTC through the SIO and DMA to the PIO, in mode 2; the clock interrupts as an NMI.
///  </para>
/// </remarks>
public sealed class Trs80Model2Bus : IProcessorBus, IIoBus
{
    private readonly byte[] _rom;
    private readonly byte[] _ram;
    private bool _bootRom = true;
    private int _bank;
    private bool _videoMapped;
    private bool _clockEnabled;
    private bool _clockPhase;
    private bool _clockInterrupt;
    private byte _control;

    /// <summary>
    ///  Creates the bus.
    /// </summary>
    /// <param name="configuration">The machine's options.</param>
    /// <param name="roms">The boot ROM and the character generator.</param>
    internal Trs80Model2Bus(Trs80Model2Configuration configuration, Trs80Model2Roms roms)
    {
        _rom = roms.Boot.ToArray();
        _ram = new byte[configuration.RamKilobytes * 1024];
        Video = new(roms.CharacterGenerator);
        Disks = new(Trs80Doubler.None, Trs80Model2Timing.ClockHertz, wd179x: true, eightInch: true);
        Ctc = new();
        Sio = new();
        Pio = new(PortA, () => 0xFF, PrinterOutput.Add);
        Dma = new(Read, Write, port => In(port), (port, value) => Out(port, value));
        DaisyChain = [Ctc, Sio, Dma, Pio];
    }

    /// <summary>
    ///  Gets the keyboard.
    /// </summary>
    public Trs80Model2Keyboard Keyboard { get; } = new();

    /// <summary>
    ///  Gets the video.
    /// </summary>
    public Trs80Model2Video Video { get; }

    /// <summary>
    ///  Gets the FD1791 and its 8-inch drives.
    /// </summary>
    public Trs80DiskController Disks { get; }

    /// <summary>
    ///  Gets the counter/timer.
    /// </summary>
    public Z80Ctc Ctc { get; }

    /// <summary>
    ///  Gets the serial ports.
    /// </summary>
    public Z80Sio Sio { get; }

    /// <summary>
    ///  Gets the parallel ports.
    /// </summary>
    public Z80Pio Pio { get; }

    /// <summary>
    ///  Gets the DMA controller.
    /// </summary>
    public Z80Dma Dma { get; }

    /// <summary>
    ///  Gets the bytes sent to the printer, through the PIO's port B.
    /// </summary>
    public List<byte> PrinterOutput { get; } = [];

    /// <summary>
    ///  Gets the interrupt daisy chain, highest priority first.
    /// </summary>
    internal IZ80DaisyDevice[] DaisyChain { get; }

    /// <summary>
    ///  Gets whether the boot ROM is switched in.
    /// </summary>
    public bool BootRomEnabled => _bootRom;

    /// <summary>
    ///  Gets the 32K bank at <c>$8000</c>, or 0 for none.
    /// </summary>
    public int Bank => _bank;

    /// <summary>
    ///  Gets whether the real-time clock requests a non-maskable interrupt.
    /// </summary>
    public bool NmiRequested => _clockInterrupt;

    /// <inheritdoc/>
    public byte Read(ushort address) => Area(address) switch
    {
        Trs80Model2MemoryArea.Rom => _rom[address],
        Trs80Model2MemoryArea.Video => Video.Read(address),
        Trs80Model2MemoryArea.Ram => _ram[Physical(address)],
        _ => 0xFF
    };

    /// <inheritdoc/>
    public void Write(ushort address, byte value)
    {
        if (address < 0x8000)
        {
            _ram[address] = value;
            return;
        }

        switch (Area(address))
        {
            case Trs80Model2MemoryArea.Video:
                Video.Write(address, value);
                break;
            case Trs80Model2MemoryArea.Ram:
                _ram[Physical(address)] = value;
                break;
        }
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
    public Trs80Model2MemoryArea Area(ushort address)
    {
        if (address < 0x8000)
        {
            return _bootRom && address < Trs80Model2Roms.BootSize ? Trs80Model2MemoryArea.Rom : Trs80Model2MemoryArea.Ram;
        }

        if (_videoMapped && address >= 0xF800) { return Trs80Model2MemoryArea.Video; }
        return _bank != 0 && Physical(address) < _ram.Length ? Trs80Model2MemoryArea.Ram : Trs80Model2MemoryArea.Unmapped;
    }

    /// <inheritdoc/>
    public byte In(ushort port)
    {
        byte low = (byte)port;
        switch (low)
        {
            case >= 0xE0 and <= 0xE3:
                return Pio.Read(low - 0xE0);
            case >= 0xE4 and <= 0xE7:
                return Disks.Read(low - 0xE4);
            case >= 0xF0 and <= 0xF3:
                return Ctc.Read(low - 0xF0);
            case >= 0xF4 and <= 0xF7:
                return Sio.Read(low - 0xF4);
            case 0xF8:
                return Dma.Read();
            case 0xFC:
                return Keyboard.Read();
            case 0xFD:
                return Video.CrtcRead();
            case 0xFE:
                _clockInterrupt = false;
                return 0xFF;
            case 0xFF:
                return Status();
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
            case >= 0xE0 and <= 0xE3:
                Pio.Write(low - 0xE0, value);
                break;
            case >= 0xE4 and <= 0xE7:
                Disks.Write(low - 0xE4, value);
                break;
            case 0xEF:
                DriveSelect(value);
                break;
            case >= 0xF0 and <= 0xF3:
                Ctc.Write(low - 0xF0, value);
                break;
            case >= 0xF4 and <= 0xF7:
                Sio.Write(low - 0xF4, value);
                break;
            case 0xF8:
                Dma.Write(value);
                break;
            case 0xF9:
                _bootRom = (value & 1) != 0;
                break;
            case 0xFC or 0xFD:
                Video.CrtcWrite(low == 0xFD, value);
                break;
            case 0xFF:
                Control(value);
                break;
        }
    }

    /// <summary>
    ///  Resets the board, as the reset switch does: the boot ROM is switched in and video RAM out.
    /// </summary>
    internal void Reset()
    {
        _bootRom = true;
        _videoMapped = false;
        _clockInterrupt = false;
    }

    /// <summary>
    ///  Advances the devices one T-state.
    /// </summary>
    internal void Tick()
    {
        if (Video.Tick())
        {
            // Each vertical sync toggles the clock, which interrupts on every other one.
            _clockPhase = !_clockPhase;
            if (_clockPhase && _clockEnabled) { _clockInterrupt = true; }
        }

        Keyboard.Tick();
        Ctc.Trigger(3, !Keyboard.Ready);
        Ctc.Tick();
        Disks.Tick();
        Dma.Ready = Disks.DataRequest;
        Dma.Tick();
        Pio.Tick();
    }

    private byte Status()
    {
        int status = _control & 0x30;
        if (Keyboard.Ready) { status |= 0x80; }
        if (Video.DisplayEnabled) { status |= 0x40; }
        return (byte)status;
    }

    private void Control(byte value)
    {
        _control = value;
        _bank = value & 0x0F;
        Video.WideCharacters = (value & 0x10) != 0;
        _clockEnabled = (value & 0x20) != 0;
        if (_clockEnabled && _clockPhase) { _clockInterrupt = true; }
        Video.Blanked = (value & 0x40) != 0;
        _videoMapped = (value & 0x80) != 0;
    }

    private void DriveSelect(byte value)
    {
        int drive = (~value & 0x0F) switch
        {
            0x01 => 0,
            0x02 => 1,
            0x04 => 2,
            0x08 => 3,
            _ => -1
        };

        // 8-inch drives turn all the time; selecting one loads its head.
        Disks.Control(drive, (value & 0x40) == 0 ? 1 : 0, motor: true, doubleDensity: (value & 0x80) != 0);
    }

    // PIO port A: bit 0 the controller's INTRQ, bit 1 a two-sided disk, bit 2 disk change.
    private byte PortA()
    {
        int value = Disks.InterruptRequest ? 0x01 : 0;
        if (Disks.SelectedDrive >= 0 && Disks.Disk(Disks.SelectedDrive) is { Sides: 2 }) { value |= 0x02; }
        return (byte)value;
    }

    private int Physical(ushort address) => address < 0x8000 ? address : (_bank << 15) | (address & 0x7FFF);
}
