// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Devices;
using Retrocore.Media.Trs80;

namespace Retrocore.Machines.Trs80;

/// <summary>
///  The cassette interface: port <c>$FF</c> drives the output, the motor relay and the input latch.
/// </summary>
/// <remarks>
///  <para>
///   Each bit is a cell starting with a clock pulse; a 1 adds a data pulse half a cell later. A cell is 2 ms at
///   Level II's 500 baud and 4 ms at Level I's 250. Playing sets the input latch at each pulse, which reading
///   port <c>$FF</c> bit 7 shows and writing the port clears. Recording times the pulses the program writes
///   (output going positive) and turns them back into bytes, aligned so the <c>$A5</c> sync byte after the
///   leader starts a byte.
///  </para>
/// </remarks>
public sealed class Trs80Cassette
{
    private const byte SyncByte = 0xA5;

    private readonly int _cellCycles;
    private CassetteImage? _tape;
    private bool _recording;
    private bool _latch;
    private int _outputLevel;
    private long _time;

    // Playback: the byte and bit under the head, and when the next pulse comes.
    private int _byte;
    private int _bit;
    private long _cellStart;
    private bool _dataPending;

    // Recording: the bits heard and the clock pulse that started the current cell.
    private readonly List<bool> _bits = [];
    private long _lastClock = -1;
    private bool _cellHasData;

    /// <summary>
    ///  Creates the interface.
    /// </summary>
    /// <param name="baud">500 for Level II, 250 for Level I.</param>
    /// <param name="clockHertz">The rate <see cref="Tick"/> is called at: the Model I's Z80 clock by default.</param>
    internal Trs80Cassette(int baud, int clockHertz = Trs80Timing.ClockHertz) => _cellCycles = clockHertz / baud;

    /// <summary>
    ///  Gets whether the input latch holds a pulse the program has not cleared.
    /// </summary>
    internal bool Latch => _latch;

    /// <summary>
    ///  Gets whether the motor relay is closed.
    /// </summary>
    public bool MotorOn { get; private set; }

    /// <summary>
    ///  Gets the T-states of one bit cell.
    /// </summary>
    public int CellCycles => _cellCycles;

    /// <summary>
    ///  Loads a tape to play from the start; the motor moves it.
    /// </summary>
    /// <param name="tape">The tape.</param>
    public void Play(CassetteImage tape)
    {
        ArgumentNullException.ThrowIfNull(tape);
        Stop();
        _tape = tape;
        _byte = 0;
        _bit = 0;
        _cellStart = -1;
    }

    /// <summary>
    ///  Loads a tape to record onto, appending what the program writes while the motor runs.
    /// </summary>
    /// <param name="tape">The tape.</param>
    public void Record(CassetteImage tape)
    {
        ArgumentNullException.ThrowIfNull(tape);
        Stop();
        _tape = tape;
        _recording = true;
    }

    /// <summary>
    ///  Stops the deck, finishing a recording, and ejects the tape.
    /// </summary>
    public void Stop()
    {
        if (_recording) { Flush(); }
        _tape = null;
        _recording = false;
    }

    /// <summary>
    ///  Gets the transport's mode.
    /// </summary>
    public TapeMode Mode => _tape is null ? TapeMode.Stopped : _recording ? TapeMode.Recording : TapeMode.Playing;

    /// <summary>
    ///  Gets the bytes played, or for a recording the whole bytes recorded so far.
    /// </summary>
    public long Position => _tape is null ? 0 : _recording ? Length : _byte;

    /// <summary>
    ///  Gets the tape's bytes: its length when playing, and when recording what is recorded, counting the bits
    ///  not yet saved.
    /// </summary>
    public long Length => _tape is not { } tape ? 0 : tape.Bytes.Count + (_recording ? _bits.Count / 8 : 0);

    /// <summary>
    ///  Gets whether a playing tape has run out.
    /// </summary>
    public bool AtEnd => _tape is { } tape && !_recording && _byte >= tape.Bytes.Count;

    /// <summary>
    ///  Reads port <c>$FF</c>: bit 7 is the input latch.
    /// </summary>
    /// <returns>The port's value.</returns>
    internal byte Read() => (byte)(_latch ? 0xFF : 0x7F);

    /// <summary>
    ///  Writes port <c>$FF</c>: bits 0-1 the output level, bit 2 the motor; any write clears the input latch.
    /// </summary>
    /// <param name="value">The value.</param>
    internal void Write(byte value)
    {
        SetMotor((value & 0x04) != 0);
        WriteLevel(value);
    }

    /// <summary>
    ///  Opens or closes the motor relay, which the Model III and 4 drive from port <c>$EC</c>.
    /// </summary>
    /// <param name="motor">Whether the motor runs.</param>
    internal void SetMotor(bool motor)
    {
        if (motor == MotorOn) { return; }
        MotorOn = motor;
        if (!motor && _recording) { Flush(); }
    }

    /// <summary>
    ///  Writes the output level from bits 0-1, clearing the input latch, as port <c>$FF</c> does.
    /// </summary>
    /// <param name="value">The value.</param>
    internal void WriteLevel(byte value)
    {
        _latch = false;
        int level = value & 0x03;
        if (level == 1 && _outputLevel != 1 && MotorOn && _recording) { Pulse(); }
        _outputLevel = level;
    }

    /// <summary>
    ///  Advances the tape one T-state.
    /// </summary>
    internal void Tick()
    {
        _time++;
        if (!MotorOn || _recording || _tape is not { } tape || _byte >= tape.Bytes.Count) { return; }

        // CAS drops the silent gaps where the writer paused, such as while CSAVE handled the file name. A pulse
        // due while the latch still holds an unread one waits, recreating the gap for a reader that is busy.
        bool due = _cellStart < 0
            || (_dataPending && _time - _cellStart == _cellCycles / 2)
            || _time - _cellStart >= _cellCycles;

        if (_latch && due)
        {
            if (_cellStart >= 0) { _cellStart++; }
            return;
        }

        // A cell's clock pulse at its start, then for a 1 its data pulse halfway.
        if (_cellStart < 0)
        {
            _cellStart = _time;
            _latch = true;
            _dataPending = ((tape.Bytes[_byte] >> (7 - _bit)) & 1) != 0;
            return;
        }

        long elapsed = _time - _cellStart;
        if (_dataPending && elapsed == _cellCycles / 2)
        {
            _latch = true;
            _dataPending = false;
        }

        if (elapsed < _cellCycles) { return; }
        if (++_bit == 8)
        {
            _bit = 0;
            _byte++;
        }

        _cellStart = -1;
    }

    // A pulse within the middle half of a cell is its data; any other starts the next cell.
    private void Pulse()
    {
        long since = _time - _lastClock;
        if (_lastClock >= 0 && !_cellHasData && since > _cellCycles / 4 && since < _cellCycles * 3 / 4)
        {
            _cellHasData = true;
            return;
        }

        if (_lastClock >= 0) { _bits.Add(_cellHasData); }
        _lastClock = _time;
        _cellHasData = false;
    }

    // Packs the recorded bits into bytes, aligning the first sync byte after the leader to a byte boundary.
    private void Flush()
    {
        if (_lastClock >= 0) { _bits.Add(_cellHasData); }
        _lastClock = -1;
        _cellHasData = false;
        if (_tape is not { } tape || _bits.Count == 0) { return; }
        int start = 0;
        for (int index = 0; index + 8 <= _bits.Count; index++)
        {
            int value = 0;
            for (int bit = 0; bit < 8; bit++) { value = (value << 1) | (_bits[index + bit] ? 1 : 0); }
            if (value == SyncByte)
            {
                start = index % 8;
                break;
            }
        }

        for (int index = start; index + 8 <= _bits.Count; index += 8)
        {
            int value = 0;
            for (int bit = 0; bit < 8; bit++) { value = (value << 1) | (_bits[index + bit] ? 1 : 0); }
            tape.Append((byte)value);
        }

        _bits.Clear();
    }
}
