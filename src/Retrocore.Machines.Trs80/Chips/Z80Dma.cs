// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Trs80.Chips;

/// <summary>
///  A Z80 DMA: moves bytes between two ports, A and B, each memory or I/O, incrementing, decrementing or fixed, when
///  its RDY input is active, as the Model II's disk controller's DRQ drives it.
/// </summary>
/// <remarks>
///  <para>
///   The program writes its registers through one port. WR0 (bit 7 clear, bits 0-1 not zero) sets the operation, the
///   direction (bit 2 set moves A to B) and, as its bits 3-6 say, port A's address and the block length; WR1 and WR2
///   (bits 0-2 <c>100</c> and <c>000</c>) port A's and B's kind (bit 3 I/O) and step (bits 4-5: 00 down, 01 up,
///   1x fixed); WR3 (bits 0-1 <c>00</c>, bit 7 set) the interrupt enable (bit 5) and DMA enable (bit 6); WR4 (bits 0-1
///   <c>01</c>) the mode (bits 5-6: byte, continuous, burst), port B's address and the interrupt control; WR5 (bits
///   0-2 <c>010</c>) RDY's polarity (bit 3 active high) and auto restart (bit 5); WR6 (bits 0-1 <c>11</c>) commands.
///   A block moves one byte more than its length, as Zilog's chip does.
///  </para>
/// </remarks>
public sealed class Z80Dma : IZ80DaisyDevice
{
    private readonly Func<ushort, byte> _readMemory;
    private readonly Action<ushort, byte> _writeMemory;
    private readonly Func<ushort, byte> _readPort;
    private readonly Action<ushort, byte> _writePort;
    private readonly Queue<Action<byte>> _follow = new();
    private readonly Queue<byte> _readBack = new();

    private bool _aToB;
    private ushort _portAStart;
    private ushort _portBStart;
    private ushort _length;
    private bool _portAIo;
    private bool _portBIo;
    private int _portAStep;
    private int _portBStep;
    private byte _wr3;
    private int _mode;
    private byte _interruptControl;
    private byte _vector;
    private bool _readyHigh;
    private bool _autoRestart;
    private byte _readMask = 0x7F;
    private bool _forceReady;
    private bool _interruptsEnabled;

    private ushort _addressA;
    private ushort _addressB;
    private int _counter;
    private byte _status = 0x38;
    private bool _pending;
    private bool _inService;
    private int _cooldown;

    /// <summary>
    ///  Creates the DMA.
    /// </summary>
    /// <param name="readMemory">Reads memory.</param>
    /// <param name="writeMemory">Writes memory.</param>
    /// <param name="readPort">Reads an I/O port.</param>
    /// <param name="writePort">Writes an I/O port.</param>
    internal Z80Dma(
        Func<ushort, byte> readMemory,
        Action<ushort, byte> writeMemory,
        Func<ushort, byte> readPort,
        Action<ushort, byte> writePort)
    {
        _readMemory = readMemory;
        _writeMemory = writeMemory;
        _readPort = readPort;
        _writePort = writePort;
    }

    /// <summary>
    ///  Gets whether the DMA is enabled to transfer.
    /// </summary>
    public bool Enabled { get; private set; }

    /// <summary>
    ///  Gets or sets the RDY input's level.
    /// </summary>
    public bool Ready { get; set; }

    /// <summary>
    ///  Gets port A's current address.
    /// </summary>
    public ushort AddressA => _addressA;

    /// <summary>
    ///  Gets port B's current address.
    /// </summary>
    public ushort AddressB => _addressB;

    /// <summary>
    ///  Gets the bytes moved in this block.
    /// </summary>
    public int Counter => _counter;

    /// <summary>
    ///  Reads the next byte of the read sequence, or the status byte.
    /// </summary>
    /// <returns>The byte.</returns>
    internal byte Read()
    {
        if (_readBack.Count == 0) { StartReadSequence(); }
        return _readBack.Count > 0 ? _readBack.Dequeue() : _status;
    }

    /// <summary>
    ///  Writes a register byte.
    /// </summary>
    /// <param name="value">The value.</param>
    internal void Write(byte value)
    {
        if (_follow.TryDequeue(out Action<byte>? next))
        {
            next(value);
            return;
        }

        if ((value & 0x80) == 0)
        {
            if ((value & 0x03) != 0) { WriteZero(value); }
            else if ((value & 0x07) == 0x04) { WritePortKind(value, portA: true); }
            else if ((value & 0x07) == 0x00) { WritePortKind(value, portA: false); }

            return;
        }

        switch (value & 0x03)
        {
            case 0x00:
                _wr3 = value;
                if ((value & 0x08) != 0) { _follow.Enqueue(_ => { }); }
                if ((value & 0x10) != 0) { _follow.Enqueue(_ => { }); }
                if ((value & 0x40) != 0) { Enabled = true; }
                break;
            case 0x01:
                _mode = (value >> 5) & 0x03;
                if ((value & 0x04) != 0) { _follow.Enqueue(b => _portBStart = Low(_portBStart, b)); }
                if ((value & 0x08) != 0) { _follow.Enqueue(b => _portBStart = High(_portBStart, b)); }
                if ((value & 0x10) != 0) { _follow.Enqueue(InterruptControl); }
                break;
            case 0x02 when (value & 0x07) == 0x02:
                _readyHigh = (value & 0x08) != 0;
                _autoRestart = (value & 0x20) != 0;
                break;
            case 0x03:
                Command(value);
                break;
        }
    }

    /// <summary>
    ///  Moves a byte when enabled and ready, at most one every four clocks.
    /// </summary>
    internal void Tick()
    {
        if (_cooldown > 0) { _cooldown--; }
        if (!Enabled || _cooldown > 0 || !(_forceReady || Ready == _readyHigh)) { return; }
        _cooldown = 4;
        byte value = _aToB
            ? (_portAIo ? _readPort(_addressA) : _readMemory(_addressA))
            : (_portBIo ? _readPort(_addressB) : _readMemory(_addressB));

        bool final = _counter == _length;
        if (_aToB)
        {
            if (_portBIo)
            {
                _writePort(_addressB, value);
            }
            else
            {
                _writeMemory(_addressB, value);
            }
        }
        else if (_portAIo)
        {
            _writePort(_addressA, value);
        }
        else
        {
            _writeMemory(_addressA, value);
        }

        _addressA = (ushort)(_addressA + _portAStep);
        _addressB = (ushort)(_addressB + _portBStep);
        _counter++;
        if (final) { EndOfBlock(); }
    }

    private void EndOfBlock()
    {
        Enabled = false;
        _status = (byte)(0x09 | 0x10 | (_forceReady || Ready == _readyHigh ? 0 : 0x02));
        if ((_interruptControl & 0x02) != 0) { Interrupt(); }
        if (_autoRestart)
        {
            Load();
            Enabled = true;
        }
    }

    private void Interrupt()
    {
        if (_inService || !_interruptsEnabled) { return; }
        _pending = true;
        _status &= unchecked((byte)~0x08);
    }

    private void WriteZero(byte value)
    {
        _aToB = (value & 0x04) != 0;
        if ((value & 0x08) != 0) { _follow.Enqueue(b => _portAStart = Low(_portAStart, b)); }
        if ((value & 0x10) != 0) { _follow.Enqueue(b => _portAStart = High(_portAStart, b)); }
        if ((value & 0x20) != 0) { _follow.Enqueue(b => _length = Low(_length, b)); }
        if ((value & 0x40) != 0) { _follow.Enqueue(b => _length = High(_length, b)); }
    }

    private static ushort Low(ushort word, byte value) => (ushort)((word & 0xFF00) | value);

    private static ushort High(ushort word, byte value) => (ushort)((word & 0x00FF) | (value << 8));

    private void WritePortKind(byte value, bool portA)
    {
        int step = ((value >> 4) & 0x03) switch
        {
            0 => -1,
            1 => 1,
            _ => 0
        };

        if (portA)
        {
            _portAIo = (value & 0x08) != 0;
            _portAStep = step;
        }
        else
        {
            _portBIo = (value & 0x08) != 0;
            _portBStep = step;
        }

        // A timing byte follows, and on port B the timing byte's bit 5 adds a prescaler.
        if ((value & 0x40) != 0)
        {
            _follow.Enqueue(timing =>
            {
                if (!portA && (timing & 0x20) != 0) { _follow.Enqueue(_ => { }); }
            });
        }
    }

    private void InterruptControl(byte value)
    {
        _interruptControl = value;
        if ((value & 0x08) != 0) { _follow.Enqueue(_ => { }); }
        if ((value & 0x10) != 0) { _follow.Enqueue(b => _vector = b); }
    }

    private void Command(byte value)
    {
        switch (value)
        {
            case 0xC3:
                Enabled = false;
                _forceReady = false;
                _autoRestart = false;
                _pending = false;
                _inService = false;
                _interruptsEnabled = false;
                _follow.Clear();
                _readMask = 0x7F;
                _status = 0x38;
                break;
            case 0xCF:
                Load();
                _status = 0x38;
                break;
            case 0xD3:
                _counter = 0;
                _status = 0x38;
                break;
            case 0xAF:
                _interruptsEnabled = false;
                break;
            case 0xAB:
                _interruptsEnabled = true;
                break;
            case 0xA3:
                _interruptsEnabled = false;
                _pending = false;
                _inService = false;
                break;
            case 0xB7:
                _interruptsEnabled = true;
                break;
            case 0xBF:
                _readBack.Clear();
                _readBack.Enqueue(_status);
                break;
            case 0x8B:
                _status = 0x38;
                break;
            case 0xA7:
                StartReadSequence();
                break;
            case 0xB3:
                _forceReady = true;
                break;
            case 0x87:
                Enabled = true;
                break;
            case 0x83:
                Enabled = false;
                break;
            case 0xBB:
                _follow.Enqueue(b => _readMask = b);
                break;
        }
    }

    private void Load()
    {
        _addressA = _portAStart;
        _addressB = _portBStart;
        _counter = 0;
    }

    private void StartReadSequence()
    {
        _readBack.Clear();
        ReadOnlySpan<byte> values =
        [
            _status, (byte)_counter, (byte)(_counter >> 8), (byte)_addressA, (byte)(_addressA >> 8),
            (byte)_addressB, (byte)(_addressB >> 8)
        ];

        for (int index = 0; index < values.Length; index++)
        {
            if ((_readMask & (1 << index)) != 0) { _readBack.Enqueue(values[index]); }
        }
    }

    /// <inheritdoc/>
    public byte? PendingVector => _pending && !_inService
        ? (byte)((_interruptControl & 0x20) != 0 ? (_vector & 0xF9) | 0x02 : _vector)
        : null;

    /// <inheritdoc/>
    public bool InService => _inService;

    /// <inheritdoc/>
    void IZ80DaisyDevice.Acknowledge()
    {
        _pending = false;
        _inService = true;
    }

    /// <inheritdoc/>
    void IZ80DaisyDevice.ReturnFromInterrupt() => _inService = false;
}
