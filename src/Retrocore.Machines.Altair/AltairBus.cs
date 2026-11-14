// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Cpu;
using Retrocore.Machines.Chips;

namespace Retrocore.Machines.Altair;

/// <summary>
///  The Altair's S-100 bus: RAM from address 0, the 88-2SIO serial board's two MC6850 ACIAs, the 88-SIO serial
///  board when the terminal is on it, the 88-ACR cassette interface, and the front panel's sense switches.
/// </summary>
/// <remarks>
///  <para>
///   Addresses past the RAM, and ports no board answers, read $FF, as the bus's pull-ups leave it. The 88-2SIO's
///   first ACIA is at ports $10 (control and status) and $11 (data), with the terminal on its line unless it is on
///   the 88-SIO, at ports $00 and $01; the second ACIA, at $12 and $13, has nothing connected. The 88-ACR is an
///   88-SIO at ports $06 and $07, at 300 baud, with a cassette recorder. <c>IN $FF</c> reads the sense switches, the
///   front panel's high 8 switches.
///  </para>
/// </remarks>
public sealed class AltairBus : IProcessorBus, IIoBus
{
    /// <summary>
    ///  The 88-2SIO's first port, as its address jumpers come.
    /// </summary>
    public const byte SerialPort = 0x10;

    /// <summary>
    ///  The 88-SIO's status port, as its address jumpers come.
    /// </summary>
    public const byte SioPort = 0x00;

    /// <summary>
    ///  The 88-ACR's status port, as its address jumpers come.
    /// </summary>
    public const byte CassettePort = 0x06;

    /// <summary>
    ///  The 88-ACR's baud rate.
    /// </summary>
    public const int CassetteBaudRate = 300;

    /// <summary>
    ///  The port that reads the sense switches.
    /// </summary>
    public const byte SenseSwitchPort = 0xFF;

    private readonly byte[] _memory = new byte[0x10000];
    private readonly int _ramSize;

    /// <summary>
    ///  Builds the bus for a configuration.
    /// </summary>
    /// <param name="configuration">The boards and switches.</param>
    internal AltairBus(AltairConfiguration configuration)
    {
        _ramSize = configuration.RamKilobytes * 1024;
        int cycles = AltairTiming.CyclesPerCharacter(configuration.BaudRate);
        SerialA.CyclesPerCharacter = cycles;
        SerialB.CyclesPerCharacter = cycles;
        if (configuration.Console == AltairConsole.Sio)
        {
            Sio = new(SioPort, cycles);
            Terminal = new(Sio);
        }
        else
        {
            Terminal = new(SerialA);
        }

        Terminal.UpperCase = configuration.UpperCase;
        if (configuration.CassetteInterface)
        {
            Acr = new(CassettePort, AltairTiming.CyclesPerCharacter(CassetteBaudRate));
            Cassette = new(Acr);
        }

        FrontPanel = new(this) { Switches = configuration.Switches };
    }

    /// <summary>
    ///  Gets the 88-2SIO's first ACIA, which the terminal is on unless it is on the 88-SIO.
    /// </summary>
    public Acia6850 SerialA { get; } = new();

    /// <summary>
    ///  Gets the 88-2SIO's second ACIA, with nothing connected.
    /// </summary>
    public Acia6850 SerialB { get; } = new();

    /// <summary>
    ///  Gets the 88-SIO, which the terminal is on, or null when the terminal is on the 88-2SIO.
    /// </summary>
    public AltairSio? Sio { get; }

    /// <summary>
    ///  Gets the 88-ACR cassette interface's 88-SIO, or null without one.
    /// </summary>
    public AltairSio? Acr { get; }

    /// <summary>
    ///  Gets the 88-ACR's cassette recorder, or null without one.
    /// </summary>
    public AltairCassette? Cassette { get; }

    /// <summary>
    ///  Gets the terminal.
    /// </summary>
    public AltairTerminal Terminal { get; }

    /// <summary>
    ///  Gets the front panel.
    /// </summary>
    public AltairFrontPanel FrontPanel { get; }

    /// <summary>
    ///  Gets whether a serial board requests an interrupt on the bus's INT line.
    /// </summary>
    public bool Interrupt => SerialA.Interrupt || SerialB.Interrupt || Sio?.Interrupt == true || Acr?.Interrupt == true;

    /// <inheritdoc/>
    public byte Read(ushort address) => address < _ramSize ? _memory[address] : (byte)0xFF;

    /// <inheritdoc/>
    public void Write(ushort address, byte value)
    {
        if (address < _ramSize) { _memory[address] = value; }
    }

    /// <summary>
    ///  Reads memory without side effects.
    /// </summary>
    /// <param name="address">The address.</param>
    /// <returns>The value.</returns>
    public byte Peek(ushort address) => Read(address);

    /// <summary>
    ///  Gets what backs an address.
    /// </summary>
    /// <param name="address">The address.</param>
    /// <returns>The area.</returns>
    public AltairMemoryArea Area(ushort address) => address < _ramSize ? AltairMemoryArea.Ram : AltairMemoryArea.None;

    /// <inheritdoc/>
    public byte In(ushort port)
    {
        // The 8080 puts the port on both halves of the address bus; the boards decode the low half.
        byte number = (byte)port;
        if (Board(number) is { } board) { return board.Read(number & 1); }
        return number switch
        {
            SerialPort or SerialPort + 1 => SerialA.Read(number & 1),
            SerialPort + 2 or SerialPort + 3 => SerialB.Read(number & 1),
            SenseSwitchPort => FrontPanel.SenseSwitches,
            _ => 0xFF
        };
    }

    /// <inheritdoc/>
    public void Out(ushort port, byte value)
    {
        byte number = (byte)port;
        if (Board(number) is { } board)
        {
            board.Write(number & 1, value);
            return;
        }

        switch (number)
        {
            case SerialPort:
            case SerialPort + 1:
                SerialA.Write(number & 1, value);
                break;
            case SerialPort + 2:
            case SerialPort + 3:
                SerialB.Write(number & 1, value);
                break;
        }
    }

    /// <summary>
    ///  Reads a port without side effects, as the debugger shows it.
    /// </summary>
    /// <param name="port">The port.</param>
    /// <returns>The value an <c>IN</c> would read.</returns>
    public byte PeekPort(byte port)
    {
        if (Board(port) is { } board) { return board.Peek(port & 1); }
        return port switch
        {
            SerialPort or SerialPort + 1 => SerialA.Peek(port & 1),
            SerialPort + 2 or SerialPort + 3 => SerialB.Peek(port & 1),
            SenseSwitchPort => FrontPanel.SenseSwitches,
            _ => 0xFF
        };
    }

    /// <summary>
    ///  Advances the boards one CPU cycle.
    /// </summary>
    internal void Tick()
    {
        SerialA.Tick();
        SerialB.Tick();
        Sio?.Tick();
        Acr?.Tick();
        Terminal.Tick();
        Cassette?.Tick();
    }

    /// <summary>
    ///  Resets the boards, as the front panel's RESET switch does: the ACIAs master reset, and the 88-SIO's and
    ///  88-ACR's interrupts are disabled. A tape keeps moving.
    /// </summary>
    internal void Reset()
    {
        SerialA.Reset();
        SerialB.Reset();
        Sio?.Reset();
        Acr?.Reset();
        Terminal.Reset();
    }

    // The 88-SIO or 88-ACR that answers a port, if either does.
    private AltairSio? Board(byte port) => Sio?.Answers(port) == true ? Sio : Acr?.Answers(port) == true ? Acr : null;
}
