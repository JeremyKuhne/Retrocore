// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Chips;

namespace Retrocore.Machines.Atari;

/// <summary>
///  The serial (SIO) bus: POKEY's serial output and input, the PIA's command line (CB2) and the devices that answer
///  command frames.
/// </summary>
/// <remarks>
///  <para>
///   The protocol and its timing follow the Altirra Hardware Reference Manual, 9.1. The computer lowers the command
///   line and sends a five-byte command frame (device, command, AUX1, AUX2, carry-wrapped checksum), then raises it.
///   The addressed device answers about 0.6 ms later with an ACK (<c>$41</c>) or a NAK (<c>$4E</c>). A write's data
///   frame then comes from the computer, and the device ACKs it about 1 ms after its last byte. After the command
///   runs, and at least 250 µs after the ACK, the device sends Complete (<c>$43</c>) or Error (<c>$45</c>), and a
///   read's data frame straight after it.
///  </para>
///  <para>
///   The device's bytes reach POKEY whole, one each 932 cycles (19,200 baud with a start and a stop bit), as
///   <see cref="Pokey.ReceiveByte"/> takes them.
///  </para>
/// </remarks>
public sealed class AtariSioBus
{
    // One byte at 19,200 baud: ten bits.
    private const int ByteCycles = 932;
    private const int AckCycles = 1_100;
    private const int DataAckCycles = 1_800;
    private const int CompleteCycles = 500;

    private readonly Pokey _pokey;
    private readonly AtariBus _bus;
    private readonly List<IAtariSioDevice> _devices = [];
    private readonly Queue<(long Due, byte Value)> _replies = new();
    private readonly byte[] _frame = new byte[5];
    private readonly List<byte> _dataIn = [];

    private bool _command;
    private int _frameLength;
    private IAtariSioDevice? _device;
    private byte _commandByte;
    private ushort _aux;
    private int _dataLength;
    private long _nextFree;

    /// <summary>
    ///  Constructs the bus.
    /// </summary>
    /// <param name="bus">The machine's bus, for the clock and the PIA.</param>
    internal AtariSioBus(AtariBus bus)
    {
        _bus = bus;
        _pokey = bus.Pokey;
        _pokey.SerialByteSent = Sent;
    }

    /// <summary>
    ///  Gets the devices on the bus.
    /// </summary>
    internal IReadOnlyList<IAtariSioDevice> Devices => _devices;

    /// <summary>
    ///  Gets whether the command line is asserted (CB2 low).
    /// </summary>
    public bool CommandLine => _command;

    /// <summary>
    ///  Puts a device on the bus.
    /// </summary>
    /// <param name="device">The device.</param>
    internal void Attach(IAtariSioDevice device)
    {
        ArgumentNullException.ThrowIfNull(device);
        _devices.Add(device);
    }

    /// <summary>
    ///  Gets the carry-wrapped checksum of a frame, as the SIO protocol adds it.
    /// </summary>
    /// <param name="data">The frame's bytes.</param>
    /// <returns>The checksum.</returns>
    public static byte Checksum(ReadOnlySpan<byte> data)
    {
        int sum = 0;
        foreach (byte value in data)
        {
            sum += value;
            if (sum > 0xFF) { sum = (sum & 0xFF) + 1; }
        }

        return (byte)sum;
    }

    /// <summary>
    ///  Advances a machine cycle: the command line is sampled and a due reply byte reaches POKEY.
    /// </summary>
    internal void Tick()
    {
        // CB2 is the command line, active low; it is high unless the PIA drives it as an output low.
        bool command = (_bus.Pia.ControlB & 0x30) == 0x30 && !_bus.Pia.CB2Output;
        if (command != _command)
        {
            _command = command;
            if (command)
            {
                // A new command frame starts; whatever was under way is abandoned.
                _frameLength = 0;
                _device = null;
                _dataLength = 0;
                _replies.Clear();
            }
            else
            {
                EndCommandFrame();
            }
        }

        if (_replies.Count != 0 && _bus.Cycles >= _replies.Peek().Due)
        {
            _pokey.ReceiveByte(_replies.Dequeue().Value);
        }
    }

    // A byte the computer has shifted out.
    private void Sent(byte value)
    {
        _bus.Cassette.Sent(value);
        if (_command)
        {
            if (_frameLength < _frame.Length) { _frame[_frameLength++] = value; }
            return;
        }

        if (_device is null || _dataLength == 0) { return; }
        _dataIn.Add(value);
        if (_dataIn.Count == _dataLength + 1) { EndDataFrame(); }
    }

    private void EndCommandFrame()
    {
        if (_frameLength != 5 || Checksum(_frame.AsSpan(0, 4)) != _frame[4]) { return; }
        IAtariSioDevice? device = _devices.Find(d => d.DeviceId == _frame[0]);
        if (device is null) { return; }

        _commandByte = _frame[1];
        _aux = (ushort)(_frame[2] | (_frame[3] << 8));
        int? accepted = device.Accept(_commandByte, _aux);
        long now = _bus.Cycles;
        if (accepted is not int length)
        {
            Reply(now + AckCycles, 0x4E);
            return;
        }

        Reply(now + AckCycles, 0x41);
        _device = device;
        _dataIn.Clear();
        _dataLength = length;
        if (length == 0) { Run([]); }
    }

    private void EndDataFrame()
    {
        int length = _dataLength;
        _dataLength = 0;
        byte[] data = [.. _dataIn];
        if (Checksum(data.AsSpan(0, length)) != data[length])
        {
            Reply(_bus.Cycles + DataAckCycles, 0x4E);
            _device = null;
            return;
        }

        Reply(_bus.Cycles + DataAckCycles, 0x41);
        Run(data.AsSpan(0, length));
    }

    // Runs the command once its frames are in, and queues Complete or Error and any data frame.
    private void Run(ReadOnlySpan<byte> data)
    {
        if (_device is not IAtariSioDevice device) { return; }
        (bool success, byte[] result, int cycles) = device.Execute(_commandByte, _aux, data, _bus.Cycles);
        Reply(_nextFree + CompleteCycles + cycles, success ? (byte)0x43 : (byte)0x45);
        if (result.Length != 0)
        {
            foreach (byte value in result) { Reply(0, value); }
            Reply(0, Checksum(result));
        }

        _device = null;
    }

    // Queues a byte to arrive no sooner than a cycle and a byte after the last.
    private void Reply(long earliest, byte value)
    {
        long due = Math.Max(earliest, _nextFree) + ByteCycles;
        if (_replies.Count == 0 && due < _bus.Cycles + ByteCycles) { due = _bus.Cycles + ByteCycles; }
        _replies.Enqueue((due, value));
        _nextFree = due;
    }
}
