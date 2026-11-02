// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Cpu;

namespace Retrocore.Machines.Trs80;

/// <summary>
///  The Model I's memory map and port <c>$FF</c>.
/// </summary>
/// <remarks>
///  <para>
///   <c>$0000</c>-<c>$2FFF</c> is BASIC (Level I fills only <c>$0FFF</c>). With the Expansion Interface,
///   <c>$37E0</c> reads the interrupt latch (bit 7 the 40 Hz clock, which the read clears, and bit 6 the disk
///   controller) and writes select drives, <c>$37E8</c> is the printer and <c>$37EC</c>-<c>$37EF</c> the
///   disk controller. <c>$3800</c> is the keyboard, <c>$3C00</c> video RAM and <c>$4000</c> RAM.
///  </para>
/// </remarks>
public sealed class Trs80Bus : IProcessorBus, IIoBus
{
    private const ushort Latches = 0x37E0;
    private const ushort Printer = 0x37E8;
    private const ushort Controller = 0x37EC;
    private const ushort KeyboardStart = 0x3800;
    private const ushort VideoStart = 0x3C00;
    private const ushort RamStart = 0x4000;
    private const byte PrinterIdle = 0x30;

    private readonly byte[] _rom;
    private readonly byte[] _ram;
    private readonly int _romEnd;
    private readonly bool _expansion;
    private readonly bool _controller;
    private int _tick;
    private bool _clock;

    /// <summary>
    ///  Creates the bus.
    /// </summary>
    /// <param name="configuration">The machine's options.</param>
    /// <param name="roms">BASIC and the character generator.</param>
    internal Trs80Bus(Trs80Configuration configuration, Trs80Roms roms)
    {
        _rom = roms.System.ToArray();
        _romEnd = _rom.Length;
        _ram = new byte[configuration.RamKilobytes * 1024];
        _expansion = configuration.ExpansionInterface;
        _controller = _expansion && configuration.DiskController;
        Video = new(roms.CharacterGenerator, configuration.LowercaseModification) { Snow = configuration.VideoSnow };
        Cassette = new(configuration.Rom == Trs80Rom.Level1 ? 250 : 500);
        Disks = new(configuration.Doubler);
    }

    /// <summary>
    ///  Gets whether the Expansion Interface has its disk controller.
    /// </summary>
    public bool HasDiskController => _controller;

    /// <summary>
    ///  Gets the keyboard.
    /// </summary>
    public Trs80Keyboard Keyboard { get; } = new();

    /// <summary>
    ///  Gets the video.
    /// </summary>
    public Trs80Video Video { get; }

    /// <summary>
    ///  Gets the cassette interface.
    /// </summary>
    public Trs80Cassette Cassette { get; }

    /// <summary>
    ///  Gets the disk controller and drives.
    /// </summary>
    public Trs80DiskController Disks { get; }

    /// <summary>
    ///  Gets the bytes sent to the printer.
    /// </summary>
    public List<byte> PrinterOutput { get; } = [];

    /// <summary>
    ///  Gets whether the Expansion Interface requests an interrupt: its clock or the disk controller.
    /// </summary>
    public bool InterruptRequested => _expansion && (_clock || (_controller && Disks.InterruptRequest));

    /// <inheritdoc/>
    public byte Read(ushort address)
    {
        if (address >= RamStart) { return address - RamStart < _ram.Length ? _ram[address - RamStart] : (byte)0xFF; }
        if (address >= VideoStart) { return Video.CpuRead(address - VideoStart); }
        if (address >= KeyboardStart) { return Keyboard.Read(address); }
        if (address < _romEnd) { return _rom[address]; }
        if (address < Latches || !_expansion) { return 0xFF; }
        if (address < Latches + 4)
        {
            // Reading the latch acknowledges the clock interrupt.
            byte latch = Latch();
            _clock = false;
            return latch;
        }

        if (address is >= Printer and < Controller) { return PrinterIdle; }
        return _controller && address < Controller + 4 ? Disks.Read(address - Controller) : (byte)0xFF;
    }

    /// <inheritdoc/>
    public void Write(ushort address, byte value)
    {
        if (address >= RamStart)
        {
            if (address - RamStart < _ram.Length) { _ram[address - RamStart] = value; }
            return;
        }

        if (address >= VideoStart)
        {
            Video.CpuWrite(address - VideoStart, value);
            return;
        }

        if (!_expansion || address is < Latches or >= KeyboardStart) { return; }
        if (address < Latches + 4)
        {
            Disks.Select(value);
        }
        else if (address is >= Printer and < Controller)
        {
            PrinterOutput.Add(value);
        }
        else if (_controller && address < Controller + 4)
        {
            Disks.Write(address - Controller, value);
        }
    }

    /// <inheritdoc/>
    public byte In(ushort port) => (byte)port == 0xFF ? Cassette.Read() : (byte)0xFF;

    /// <inheritdoc/>
    public void Out(ushort port, byte value)
    {
        if ((byte)port != 0xFF) { return; }
        Cassette.Write(value);
        Video.WideCharacters = (value & 0x08) != 0;
    }

    /// <summary>
    ///  Reads without side effects, for the debugger.
    /// </summary>
    /// <param name="address">The address.</param>
    /// <returns>The byte a read would return.</returns>
    public byte Peek(ushort address)
    {
        if (Area(address) == Trs80MemoryArea.Video) { return Video.Read(address - VideoStart); }
        if (Area(address) != Trs80MemoryArea.ExpansionInterface) { return Read(address); }
        if (address < Latches + 4) { return Latch(); }
        return _controller && address is >= Controller and < Controller + 4 ? Disks.Peek(address - Controller) : Read(address);
    }

    /// <summary>
    ///  Gets the region an address is in.
    /// </summary>
    /// <param name="address">The address.</param>
    /// <returns>The region.</returns>
    public Trs80MemoryArea Area(ushort address) => address switch
    {
        >= RamStart => address - RamStart < _ram.Length ? Trs80MemoryArea.Ram : Trs80MemoryArea.Unmapped,
        >= VideoStart => Trs80MemoryArea.Video,
        >= KeyboardStart => Trs80MemoryArea.Keyboard,
        _ when address < _romEnd => Trs80MemoryArea.Rom,
        >= Latches when _expansion => Trs80MemoryArea.ExpansionInterface,
        _ => Trs80MemoryArea.Unmapped
    };

    /// <summary>
    ///  Advances the devices one T-state.
    /// </summary>
    internal void Tick()
    {
        Video.Tick();
        Keyboard.Tick();
        Cassette.Tick();
        if (!_expansion) { return; }
        if (++_tick == Trs80Timing.CyclesPerTick)
        {
            _tick = 0;
            _clock = true;
        }

        if (_controller) { Disks.Tick(); }
    }

    private byte Latch() => (byte)((_clock ? 0x80 : 0) | (_controller && Disks.InterruptRequest ? 0x40 : 0));
}
