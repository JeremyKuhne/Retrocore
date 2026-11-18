// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Cpu;
using Retrocore.Machines.Chips;

namespace Retrocore.Machines.Kaypro;

/// <summary>
///  The Kaypro II's memory and I/O: 64K of RAM, with the monitor ROM and video RAM banked over its first 16K, and
///  its ports.
/// </summary>
/// <remarks>
///  <para>
///   Ports, each repeated in its group of four: <c>$00</c> the serial port's baud rate generator, <c>$04</c>-<c>$07</c>
///   the SIO (channel A the serial port, B the keyboard; data then control), <c>$08</c>-<c>$0B</c> the
///   general-purpose PIO (port A the printer's data), <c>$0C</c> the keyboard's baud rate generator,
///   <c>$10</c>-<c>$13</c> the FD1793, and <c>$1C</c>-<c>$1F</c> the system PIO, whose port A is the system port.
///  </para>
///  <para>
///   Bit 7 set banks in the ROM at <c>$0000</c> and video RAM at <c>$3000</c>; bit 6 set turns the drive motors off;
///   bit 5 set selects single density; bit 4 is the printer's strobe; bit 3, an input, is set while the printer is
///   ready; and bits 1 and 0 select drive B and drive A.
///  </para>
///  <para>
///   The FD1793's interrupt and data requests reach the Z80's NMI only while the Z80 is halted.
///  </para>
/// </remarks>
public sealed class KayproBus : IProcessorBus, IIoBus
{
    /// <summary>
    ///  Where the ROM's bank ends: the ROM, then nothing, up to video RAM.
    /// </summary>
    public const int VideoStart = 0x3000;

    /// <summary>
    ///  Where the banked area ends.
    /// </summary>
    public const int BankEnd = 0x4000;

    private const byte RomBit = 0x80;
    private const byte MotorsOffBit = 0x40;
    private const byte SingleDensityBit = 0x20;
    private const byte StrobeBit = 0x10;
    private const byte PrinterReadyBit = 0x08;
    private const byte ResetSystem = RomBit;

    private readonly byte[] _rom;
    private readonly byte[] _ram = new byte[0x10000];
    private bool _romBanked = true;

    /// <summary>
    ///  Creates the bus with the ROM banked in.
    /// </summary>
    /// <param name="roms">The ROMs.</param>
    internal KayproBus(KayproRoms roms)
    {
        _rom = roms.Monitor.ToArray();
        Video = new(roms.CharacterGenerator);
        Disks = new(KayproTiming.ClockHertz, wd179x: true);
        Sio = new() { Transmit = Transmitted };
        Keyboard = new(Sio);
        SystemPio = new(SystemInput, () => 0xFF);
        GeneralPio = new(() => 0xFF, () => 0xFF);
        DaisyChain = [Sio, SystemPio, GeneralPio];
        System = ResetSystem;
        Apply(System);
    }

    /// <summary>
    ///  Gets the keyboard.
    /// </summary>
    public KayproKeyboard Keyboard { get; }

    /// <summary>
    ///  Gets the display.
    /// </summary>
    public KayproVideo Video { get; }

    /// <summary>
    ///  Gets the floppy disk controller.
    /// </summary>
    public WesternDigitalFloppyDiskController Disks { get; }

    /// <summary>
    ///  Gets the SIO: channel A the serial port, B the keyboard.
    /// </summary>
    public Z80Sio Sio { get; }

    /// <summary>
    ///  Gets the system PIO, whose port A is the system port.
    /// </summary>
    public Z80Pio SystemPio { get; }

    /// <summary>
    ///  Gets the general-purpose PIO, whose port A is the printer's data.
    /// </summary>
    public Z80Pio GeneralPio { get; }

    /// <summary>
    ///  Gets what the printer has printed.
    /// </summary>
    public List<byte> PrinterOutput { get; } = [];

    /// <summary>
    ///  Gets what the serial port has sent.
    /// </summary>
    public List<byte> SerialOutput { get; } = [];

    /// <summary>
    ///  Gets the system port's outputs.
    /// </summary>
    public byte System { get; private set; }

    /// <summary>
    ///  Gets whether the ROM and video RAM are banked in.
    /// </summary>
    public bool RomBanked => _romBanked;

    /// <summary>
    ///  Gets the serial port's and the keyboard's baud rate codes, 0 (50 baud) to 15 (19,200).
    /// </summary>
    public (int Serial, int Keyboard) BaudRates { get; private set; }

    /// <summary>
    ///  Gets the interrupting devices in priority order.
    /// </summary>
    internal IZ80DaisyDevice[] DaisyChain { get; }

    /// <summary>
    ///  Gets whether the floppy disk controller asks for the NMI: it does when it wants a byte or has finished a
    ///  command, but the Kaypro gates that with the Z80's HALT, which the machine adds.
    /// </summary>
    public bool DiskRequest => Disks.InterruptRequest || Disks.DataRequest;

    /// <inheritdoc/>
    public byte Read(ushort address) => Area(address) switch
    {
        KayproMemoryArea.Rom => address < _rom.Length ? _rom[address] : (byte)0,
        KayproMemoryArea.Video => Video.Read(address - VideoStart),
        _ => _ram[address]
    };

    /// <inheritdoc/>
    public void Write(ushort address, byte value)
    {
        switch (Area(address))
        {
            case KayproMemoryArea.Video:
                Video.Write(address - VideoStart, value);
                break;
            case KayproMemoryArea.Ram:
                _ram[address] = value;
                break;
        }
    }

    /// <summary>
    ///  Reads memory without side effects.
    /// </summary>
    /// <param name="address">The address.</param>
    /// <returns>The byte.</returns>
    public byte Peek(ushort address) => Read(address);

    /// <summary>
    ///  Reads RAM, under the ROM or not.
    /// </summary>
    /// <param name="address">The address.</param>
    /// <returns>The byte.</returns>
    public byte PeekRam(ushort address) => _ram[address];

    /// <summary>
    ///  Writes RAM, under the ROM or not.
    /// </summary>
    /// <param name="address">The address.</param>
    /// <param name="value">The byte.</param>
    public void PokeRam(ushort address, byte value) => _ram[address] = value;

    /// <summary>
    ///  Gets what an address reaches.
    /// </summary>
    /// <param name="address">The address.</param>
    /// <returns>The area.</returns>
    public KayproMemoryArea Area(ushort address) => !_romBanked || address >= BankEnd
        ? KayproMemoryArea.Ram
        : address >= VideoStart ? KayproMemoryArea.Video : KayproMemoryArea.Rom;

    /// <inheritdoc/>
    public byte In(ushort port)
    {
        byte low = (byte)port;
        return (low & 0x1C) switch
        {
            0x04 => Sio.Read(SioRegister(low)),
            0x08 => GeneralPio.Read(PioRegister(low)),
            0x10 => Disks.Read(low & 3),
            0x1C => SystemPio.Read(PioRegister(low)),
            _ => 0xFF
        };
    }

    /// <inheritdoc/>
    public void Out(ushort port, byte value)
    {
        byte low = (byte)port;
        switch (low & 0x1C)
        {
            case 0x00:
                BaudRates = BaudRates with { Serial = value & 0x0F };
                break;
            case 0x04:
                Sio.Write(SioRegister(low), value);
                break;
            case 0x08:
                GeneralPio.Write(PioRegister(low), value);
                break;
            case 0x0C:
                BaudRates = BaudRates with { Keyboard = value & 0x0F };
                break;
            case 0x10:
                Disks.Write(low & 3, value);
                break;
            case 0x1C:
                SystemPio.Write(PioRegister(low), value);
                if ((low & 3) is 0 or 1) { SystemChanged(); }
                break;
        }
    }

    /// <summary>
    ///  Banks the ROM in and turns the motors on, as the system port reads after a reset.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   The PIOs reset too, so the system port's pins float, pulled up, until the ROM sets the port up again. Its
    ///   latch keeps what CP/M last wrote, which only drives the pins once the ROM has written its own value there.
    ///  </para>
    /// </remarks>
    internal void Reset()
    {
        SystemPio.Reset();
        GeneralPio.Reset();
        System = ResetSystem;
        Apply(System);
    }

    /// <summary>
    ///  Banks the ROM out, as CP/M runs, for a program loaded under it; the drives and motors stay as they are.
    /// </summary>
    public void BankRomOut()
    {
        System = (byte)(System & ~RomBit);
        Apply(System);
    }

    /// <summary>
    ///  Runs the devices for a T-state.
    /// </summary>
    internal void Tick()
    {
        Video.Tick();
        Keyboard.Tick();
        Disks.Tick();
        SystemPio.Tick();
        GeneralPio.Tick();
    }

    // The SIO and PIOs take their registers with the channel in bit 0 and control in bit 1; our chips' are the other
    // way round.
    private static int SioRegister(byte port) => ((port >> 1) & 1) | ((port & 1) << 1);

    private static int PioRegister(byte port) => SioRegister(port);

    private void Transmitted(int channel, byte value)
    {
        if (channel == 1) { Keyboard.Receive(value); }
        else { SerialOutput.Add(value); }
    }

    // The system port's input pins: the printer ready, and the rest pulled up.
    private byte SystemInput() => 0xFF;

    // The system port's pins once its PIO port drives them: in bit control mode, the output bits.
    private void SystemChanged()
    {
        int mode = SystemPio.Mode(0);
        if (mode is not (0 or 3)) { return; }
        byte value = SystemPio.Peek(0);
        byte previous = System;
        System = value;
        Apply(value);

        // The printer takes a byte on the strobe's rising edge.
        if ((value & StrobeBit) != 0 && (previous & StrobeBit) == 0)
        {
            PrinterOutput.Add(GeneralPio.Peek(0));
        }
    }

    private void Apply(byte value)
    {
        _romBanked = (value & RomBit) != 0;
        int drive = (value & 0x01) != 0 ? 0 : (value & 0x02) != 0 ? 1 : -1;
        Disks.Control(drive, side: 0, motor: (value & MotorsOffBit) == 0, doubleDensity: (value & SingleDensityBit) == 0);
    }
}
