// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Chips;

/// <summary>
///  An Intel 8155, or OKI's CMOS 81C55: 256 bytes of RAM, two 8-bit ports, a 6-bit port and a 14-bit timer.
/// </summary>
/// <remarks>
///  <para>
///   Its I/O registers, by the low three address bits: 0 the command register (written) and status (read), 1 port
///   A, 2 port B, 3 port C, 4 the timer count's low byte, 5 its high six bits with the timer mode in bits 6-7. 6 and 7
///   are not decoded and read $FF. The RAM, selected by the chip's IO/M line, is reached through
///   <see cref="ReadRam"/> and <see cref="WriteRam"/>.
///  </para>
///  <para>
///   The command register: bits 0 and 1 make port A and B outputs, bits 2 and 3 port C's mode (00 all inputs, 11 all
///   outputs, 01 and 10 the handshake modes; only inputs are modelled, so port C always reads its pins and ignores
///   writes, as the Model 100 has it), bits 4 and 5 enable the ports' handshake interrupts (stored only), and bits 6
///   and 7 command the timer: 00 nothing, 01 stop at once, 10 stop after the next terminal count, 11 start, loading
///   the count and mode written, or, if it is running, loading them at its next terminal count. Status: bit 6 is the
///   timer's terminal-count latch, which a status read clears; the handshake bits read 0.
///  </para>
///  <para>
///   The timer counts the TIMER IN clock, which <see cref="Tick"/> advances, and its mode is the count's top two
///   bits: 00 one square wave, 01 a continuous square wave, 10 one pulse at terminal count, 11 a pulse each terminal
///   count. A square wave of count n is high for the first n/2 counts, rounded up, and low for the rest; a pulse mode
///   holds TIMER OUT high but for the one count at terminal count. Counts below 2 are taken as 2. TIMER OUT is high
///   while the timer is stopped, but for a single pulse's last count. This is the timer as Intel's <i>MCS-80/85 Family User's Manual</i> describes it, but
///   for one thing: the chip counts down by twos, twice a cycle, so its count registers read an encoded value while
///   it runs; here they read the counts left.
///  </para>
/// </remarks>
public sealed class Pio8155
{
    private readonly byte[] _ram = new byte[256];
    private byte _command;
    private byte _portA;
    private byte _portB;
    private byte _countLow;
    private byte _countHigh;

    // The count and mode the timer runs with, and how far it has counted down.
    private int _runCount;
    private int _runMode;
    private int _remaining;
    private bool _running;
    private bool _reload;
    private bool _stopAfterTerminal;
    private bool _terminalCount;
    private bool _pulse;
    private bool _output = true;

    /// <summary>
    ///  Creates a reset chip.
    /// </summary>
    public Pio8155() => Reset();

    /// <summary>
    ///  Gets or sets the levels on port C's pins, which a read of port C returns.
    /// </summary>
    public byte PortCInput { get; set; } = 0x3F;

    /// <summary>
    ///  Gets or sets the levels on port A's pins while it is an input.
    /// </summary>
    public byte PortAInput { get; set; } = 0xFF;

    /// <summary>
    ///  Gets or sets the levels on port B's pins while it is an input.
    /// </summary>
    public byte PortBInput { get; set; } = 0xFF;

    /// <summary>
    ///  Gets port A's output latch, which the pins carry while it is an output.
    /// </summary>
    public byte PortA => _portA;

    /// <summary>
    ///  Gets port B's output latch.
    /// </summary>
    public byte PortB => _portB;

    /// <summary>
    ///  Gets the command register last written.
    /// </summary>
    public byte Command => _command;

    /// <summary>
    ///  Gets TIMER OUT.
    /// </summary>
    public bool TimerOutput => _output;

    /// <summary>
    ///  Gets whether the timer is counting.
    /// </summary>
    public bool TimerRunning => _running;

    /// <summary>
    ///  Gets or sets what is told of each write to port A, with the value written.
    /// </summary>
    public Action<byte>? PortAWritten { get; set; }

    /// <summary>
    ///  Gets or sets what is told of each write to port B, with the value written.
    /// </summary>
    public Action<byte>? PortBWritten { get; set; }

    /// <summary>
    ///  Gets or sets what is told when TIMER OUT changes, with its new level.
    /// </summary>
    public Action<bool>? TimerOutputChanged { get; set; }

    /// <summary>
    ///  Resets the chip, as its RESET line does: the command register clears, so the ports are inputs, and the timer
    ///  stops. The output latches, the count and the RAM keep their values.
    /// </summary>
    public void Reset()
    {
        _command = 0;
        _running = false;
        _reload = false;
        _stopAfterTerminal = false;
        _terminalCount = false;
        _pulse = false;
        SetOutput(level: true);
    }

    /// <summary>
    ///  Reads an I/O register.
    /// </summary>
    /// <param name="register">The register, by the low three address bits.</param>
    /// <returns>The value.</returns>
    public byte Read(int register)
    {
        byte value = Peek(register);
        if ((register & 7) == 0) { _terminalCount = false; }
        return value;
    }

    /// <summary>
    ///  Reads an I/O register without side effects.
    /// </summary>
    /// <param name="register">The register, by the low three address bits.</param>
    /// <returns>The value a read would return.</returns>
    public byte Peek(int register) => (register & 7) switch
    {
        0 => (byte)(_terminalCount ? 0x40 : 0),
        1 => (_command & 1) != 0 ? _portA : PortAInput,
        2 => (_command & 2) != 0 ? _portB : PortBInput,
        3 => (byte)(PortCInput | 0xC0),
        4 => (byte)CurrentCount,
        5 => (byte)((CurrentCount >> 8) & 0x3F | ((_running ? _runMode : _countHigh >> 6) << 6)),
        _ => 0xFF
    };

    /// <summary>
    ///  Writes an I/O register.
    /// </summary>
    /// <param name="register">The register, by the low three address bits.</param>
    /// <param name="value">The value.</param>
    public void Write(int register, byte value)
    {
        switch (register & 7)
        {
            case 0:
                _command = value;
                TimerCommand((value >> 6) & 3);
                break;
            case 1:
                _portA = value;
                PortAWritten?.Invoke(value);
                break;
            case 2:
                _portB = value;
                PortBWritten?.Invoke(value);
                break;
            case 4:
                _countLow = value;
                break;
            case 5:
                _countHigh = value;
                break;
        }
    }

    /// <summary>
    ///  Reads the chip's RAM.
    /// </summary>
    /// <param name="address">The address; the low eight bits are used.</param>
    /// <returns>The byte.</returns>
    public byte ReadRam(int address) => _ram[address & 0xFF];

    /// <summary>
    ///  Writes the chip's RAM.
    /// </summary>
    /// <param name="address">The address; the low eight bits are used.</param>
    /// <param name="value">The byte.</param>
    public void WriteRam(int address, byte value) => _ram[address & 0xFF] = value;

    /// <summary>
    ///  Advances the timer one TIMER IN clock.
    /// </summary>
    public void Tick()
    {
        // A terminal-count pulse lasts one count.
        if (_pulse)
        {
            _pulse = false;
            SetOutput(level: true);
        }

        if (!_running) { return; }
        _remaining--;
        if (_remaining > 0)
        {
            // n - k counts left after k: high while more than n/2 remain, which is the first n/2 rounded up.
            if (_runMode is 0 or 1) { SetOutput(_remaining > _runCount / 2); }
            return;
        }

        _terminalCount = true;
        if (_runMode is 2 or 3)
        {
            SetOutput(level: false);
            _pulse = true;
        }

        // A start while running takes effect at terminal count, whatever the mode, and over a stop after it.
        if (_reload)
        {
            Load();
            _stopAfterTerminal = false;
        }
        else if (_stopAfterTerminal || _runMode is 0 or 2)
        {
            _running = false;
            _stopAfterTerminal = false;
            if (!_pulse) { SetOutput(level: true); }
            return;
        }

        _remaining = _runCount;
        if (_runMode is 0 or 1) { SetOutput(level: true); }
    }

    // Running, the counts left; stopped, the count as written.
    private int CurrentCount => _running ? _remaining : ((_countHigh & 0x3F) << 8) | _countLow;

    private static int Count(byte low, byte high) => Math.Max(2, ((high & 0x3F) << 8) | low);

    private void TimerCommand(int timer)
    {
        switch (timer)
        {
            case 1:
                _running = false;
                _reload = false;
                _stopAfterTerminal = false;
                SetOutput(level: true);
                break;
            case 2:
                if (_running) { _stopAfterTerminal = true; }
                break;
            case 3:
                if (_running)
                {
                    _reload = true;
                }
                else
                {
                    Load();
                    _remaining = _runCount;
                    _running = true;
                    _stopAfterTerminal = false;
                    SetOutput(level: true);
                }

                break;
        }
    }

    private void Load()
    {
        _runCount = Count(_countLow, _countHigh);
        _runMode = _countHigh >> 6;
        _reload = false;
    }

    private void SetOutput(bool level)
    {
        if (_output == level) { return; }
        _output = level;
        TimerOutputChanged?.Invoke(level);
    }
}
