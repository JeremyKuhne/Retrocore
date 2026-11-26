// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Cpu;
using Retrocore.Machines.Chips;

namespace Retrocore.Machines.Trs80Model100;

/// <summary>
///  The Model 100's memory and I/O: the main ROM or the option ROM at $0000-$7FFF, RAM down from $FFFF, and the
///  ports of the 81C55, the UART, the keyboard, the clock and the LCD.
/// </summary>
/// <remarks>
///  <para>
///   Each device answers a block of 16 ports, decoded from the high four bits (Covington's <i>System Map</i>, which
///   gives the port bits used here, with MAME's <c>kyocera.cpp</c>):
///  </para>
///  <list type="bullet">
///   <item>
///    <description>
///     <c>$A0</c>: the modem's controls (written): bit 0 the phone relay, bit 1 the modem's enable.
///    </description>
///   </item>
///   <item>
///    <description>
///     <c>$B0</c>: the 81C55, by the low three bits. Port A strobes keyboard columns 0-7, selects LCD drivers 0-7, and
///     drives the clock's C0-C2 (bits 0-2), CLK (bit 3) and DATA IN (bit 4). Port B: bit 0 strobes column 8 and selects
///     driver 8, bit 1 selects driver 9, bit 2 picks the beeper's source, bit 3 puts the UART on the modem, bit 4 turns
///     the power off, bit 5 is the beeper's level, and bits 6 and 7 are RS-232 DTR and RTS, active low. Port C reads
///     the clock's DATA OUT (bit 0), the printer's BUSY low and high (bits 1 and 2), the bar-code wand (bit 3), and
///     RS-232 CTS and DSR, active low (bits 4 and 5).
///    </description>
///   </item>
///   <item>
///    <description>
///     <c>$C0</c>: the IM6402 UART's data.
///    </description>
///   </item>
///   <item>
///    <description>
///     <c>$D0</c>: the UART's word format (written) and status (read): bit 0 carrier, bits 1-3 overrun, framing and
///     parity errors, bit 4 transmit buffer empty, bit 5 ring, bit 7 power good (the low-power signal, active low).
///    </description>
///   </item>
///   <item>
///    <description>
///     <c>$E0</c>: the keyboard's rows (read); written, bit 0 selects the option ROM, bit 1 is the printer's STROBE
///     (low), bit 2 the clock's STB, bit 3 the cassette's motor.
///    </description>
///   </item>
///   <item>
///    <description>
///     <c>$F0</c>: the LCD drivers selected by ports A and B: even ports instructions and status, odd ports display
///     data.
///    </description>
///   </item>
///  </list>
///  <para>
///   Other ports read $FF. Neither the UART nor the modem is connected yet: the UART reads no data, its transmitter is
///   always empty, and there is never a carrier. No printer is connected, so BUSY reads not busy.
///  </para>
/// </remarks>
public sealed class Trs80Model100Bus : IProcessorBus, IIoBus
{
    private readonly byte[] _rom;
    private readonly byte[]? _option;
    private readonly byte[] _ram = new byte[0x8000];
    private readonly int _ramStart;
    private int _select;
    private byte _control;

    /// <summary>
    ///  Builds the bus.
    /// </summary>
    /// <param name="configuration">The RAM fitted and the clock's start.</param>
    /// <param name="roms">The ROMs.</param>
    internal Trs80Model100Bus(Trs80Model100Configuration configuration, Trs80Model100Roms roms)
    {
        _rom = roms.Main;
        _option = roms.Option;
        _ramStart = 0x10000 - configuration.RamKilobytes * 1024;
        Clock = new(Trs80Model100Timing.ClockHertz);
        Clock.SetTime(configuration.StartTime ?? DateTime.Now);
        Pio.PortAWritten = PortAWritten;
        Pio.PortBWritten = PortBWritten;
    }

    /// <summary>
    ///  Gets the 81C55.
    /// </summary>
    public Pio8155 Pio { get; } = new();

    /// <summary>
    ///  Gets the uPD1990AC clock.
    /// </summary>
    public Rtc1990 Clock { get; }

    /// <summary>
    ///  Gets the LCD.
    /// </summary>
    public Trs80Model100Lcd Lcd { get; } = new();

    /// <summary>
    ///  Gets the keyboard.
    /// </summary>
    public Trs80Model100Keyboard Keyboard { get; } = new();

    /// <summary>
    ///  Gets whether port $E0 bit 0 has the option ROM in place of the main ROM.
    /// </summary>
    public bool OptionRomSelected => (_control & 1) != 0;

    /// <summary>
    ///  Gets whether the cassette's motor is on, from port $E0 bit 3.
    /// </summary>
    public bool CassetteMotor => (_control & 8) != 0;

    /// <summary>
    ///  Gets the last value written to the modem's port, $A0.
    /// </summary>
    public byte ModemControl { get; private set; }

    /// <summary>
    ///  Gets the last value written to the UART's word format, port $D0.
    /// </summary>
    public byte UartFormat { get; private set; }

    /// <summary>
    ///  Gets or sets what is told when software turns the power off with port B bit 4.
    /// </summary>
    internal Action? PowerOff { get; set; }

    /// <summary>
    ///  Gets the address the RAM starts at.
    /// </summary>
    public int RamStart => _ramStart;

    /// <summary>
    ///  Gets the RAM, $8000-$FFFF, of which the part from <see cref="RamStart"/> is fitted.
    /// </summary>
    public Span<byte> Ram => _ram;

    /// <inheritdoc/>
    public byte Read(ushort address)
    {
        if (address < 0x8000)
        {
            if (!OptionRomSelected) { return _rom[address]; }
            return _option is not null && address < _option.Length ? _option[address] : (byte)0xFF;
        }

        return address >= _ramStart ? _ram[address - 0x8000] : (byte)0xFF;
    }

    /// <inheritdoc/>
    public void Write(ushort address, byte value)
    {
        if (address >= _ramStart) { _ram[address - 0x8000] = value; }
    }

    /// <summary>
    ///  Reads memory without side effects.
    /// </summary>
    /// <param name="address">The address.</param>
    /// <returns>The value.</returns>
    public byte Peek(ushort address) => Read(address);

    /// <summary>
    ///  Gets what backs an address now.
    /// </summary>
    /// <param name="address">The address.</param>
    /// <returns>The area.</returns>
    public Trs80Model100MemoryArea Area(ushort address)
    {
        if (address >= 0x8000)
        {
            return address >= _ramStart ? Trs80Model100MemoryArea.Ram : Trs80Model100MemoryArea.None;
        }

        if (!OptionRomSelected) { return Trs80Model100MemoryArea.Rom; }
        return _option is not null && address < _option.Length ? Trs80Model100MemoryArea.OptionRom : Trs80Model100MemoryArea.None;
    }

    /// <inheritdoc/>
    public byte In(ushort port) => Input((byte)port, peek: false);

    /// <inheritdoc/>
    public void Out(ushort port, byte value)
    {
        byte number = (byte)port;
        switch (number >> 4)
        {
            case 0xA:
                ModemControl = value;
                break;
            case 0xB:
                Pio.Write(number & 7, value);
                break;
            case 0xD:
                UartFormat = value;
                break;
            case 0xE:
                _control = value;
                Clock.SetStrobe((value & 4) != 0);
                break;
            case 0xF:
                Lcd.Write(_select, (number & 1) != 0, value);
                break;
        }
    }

    /// <summary>
    ///  Reads a port without side effects, as the debugger shows it.
    /// </summary>
    /// <param name="port">The port.</param>
    /// <returns>The value an <c>IN</c> would read.</returns>
    public byte PeekPort(byte port) => Input(port, peek: true);

    /// <summary>
    ///  Advances the devices one CPU cycle.
    /// </summary>
    internal void Tick()
    {
        Pio.Tick();
        Clock.Tick();
        Keyboard.Tick();
    }

    /// <summary>
    ///  Resets the devices, as power-on does: the 81C55's command clears, the option ROM is deselected, and the LCD
    ///  drivers turn their displays off. RAM and the clock keep running.
    /// </summary>
    internal void Reset()
    {
        Pio.Reset();
        Lcd.Reset();
        _control = 0;
        Clock.SetStrobe(strobe: false);
    }

    private byte Input(byte port, bool peek)
    {
        switch (port >> 4)
        {
            case 0xB:
                if ((port & 7) == 3) { Pio.PortCInput = PortC; }
                return peek ? Pio.Peek(port & 7) : Pio.Read(port & 7);
            case 0xC:
                return 0;
            case 0xD:
                // Transmit buffer empty, power good.
                return 0x90;
            case 0xE:
                return Keyboard.Read(_select);
            case 0xF:
                return Lcd.Read(_select, (port & 1) != 0, peek);
            default:
                return 0xFF;
        }
    }

    // Port C's inputs: the clock's DATA OUT, the printer not busy, no wand, and RS-232 CTS and DSR not asserted.
    private byte PortC => (byte)((Clock.DataOut ? 1 : 0) | 0x02 | 0x30);

    private void PortAWritten(byte value)
    {
        _select = (_select & 0x300) | value;
        Clock.SetInputs(value & 7, (value & 8) != 0, (value & 0x10) != 0);
    }

    private void PortBWritten(byte value)
    {
        _select = (_select & 0xFF) | ((value & 3) << 8);
        if ((value & 0x10) != 0) { PowerOff?.Invoke(); }
    }
}
