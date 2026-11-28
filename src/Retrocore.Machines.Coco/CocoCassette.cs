// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Devices;
using Retrocore.Media.Trs80;

namespace Retrocore.Machines.Coco;

/// <summary>
///  The Color Computer's cassette: the 1500 baud signal Color BASIC writes through the DAC and reads on PIA 1's PA0,
///  as <c>.cas</c> bytes.
/// </summary>
/// <remarks>
///  <para>
///   Each bit is one cycle of a square wave, least significant bit first: 1200 Hz for a 0 and 2400 Hz for a 1. A
///   <c>.cas</c> file holds the bytes, leaders and sync bytes included. The tape moves only while PIA 1's CA2 closes
///   the motor relay. Recording times the DAC's crossings of its midpoint, turns each cycle back into a bit, and
///   aligns the bits to bytes on each block's leader.
///  </para>
/// </remarks>
public sealed class CocoCassette
{
    // Time units (8 crystal periods) in a cycle of each tone.
    private const double ZeroCycleUnits = CocoTiming.CrystalHertz / 8 / 1200;
    private const double OneCycleUnits = CocoTiming.CrystalHertz / 8 / 2400;
    private const double ThresholdUnits = (ZeroCycleUnits + OneCycleUnits) / 2;

    // A .cas file leaves out the silence before each leader, where Color BASIC waits half a second for the motor
    // to come up to speed; playing puts it back so the leader is still running when BASIC starts reading. A $55 inside
    // a block is not a leader: silence there would cut the block's bits apart.
    private const double GapUnits = CocoTiming.CrystalHertz / 8 / 2;

    // The $55 bytes in a row, between blocks, that make a leader: Color BASIC writes 128 before the name block and
    // before the data. Between blocks that follow one another there are only the two that end and start them.
    private const int LeaderRun = 32;

    private CassetteImage? _tape;

    // Where the tape's leaders start, found by walking its blocks, and the length of tape they were found for.
    private HashSet<int>? _leaders;
    private int _leadersLength;
    private int _byteIndex;
    private int _bitIndex;
    private double _phase;
    private double _cycleLength;
    private bool _inGap;
    private double _sinceCrossing;
    private bool _wasHigh;
    private int _recordByte;
    private int _recordBits;
    private CocoTapeBlockState _recordState;
    private int _blockRemaining;


    /// <summary>
    ///  Gets whether the tape plays, records or is stopped.
    /// </summary>
    public TapeMode Mode { get; private set; }

    /// <summary>
    ///  Gets the level on PA0: the playing tape's signal, or high with none.
    /// </summary>
    public bool Input { get; private set; } = true;

    /// <summary>
    ///  Gets whether the playing tape has run out.
    /// </summary>
    public bool AtEnd => Mode == TapeMode.Playing && _tape is not null && _byteIndex >= _tape.Bytes.Count;

    /// <summary>
    ///  Gets the bytes recorded or played so far.
    /// </summary>
    public int Position => _byteIndex;

    /// <summary>
    ///  Starts playing a tape from its start.
    /// </summary>
    /// <param name="tape">The tape.</param>
    public void Play(CassetteImage tape)
    {
        ArgumentNullException.ThrowIfNull(tape);
        Load(tape, TapeMode.Playing);
    }

    /// <summary>
    ///  Starts recording onto a tape, appending to it.
    /// </summary>
    /// <param name="tape">The tape.</param>
    public void Record(CassetteImage tape)
    {
        ArgumentNullException.ThrowIfNull(tape);
        Load(tape, TapeMode.Recording);
    }

    /// <summary>
    ///  Stops and removes the tape.
    /// </summary>
    public void Stop()
    {
        _tape = null;
        Mode = TapeMode.Stopped;
        Input = true;
    }

    /// <summary>
    ///  Advances the tape while the motor runs.
    /// </summary>
    /// <param name="units">Time units.</param>
    /// <param name="motor">Whether the motor relay is closed.</param>
    /// <param name="dac">The DAC's value, 0-63, which recording reads.</param>
    internal void Tick(int units, bool motor, int dac)
    {
        if (!motor || _tape is not { } tape) { return; }
        if (Mode == TapeMode.Playing)
        {
            Play(tape, units);
        }
        else if (Mode == TapeMode.Recording)
        {
            Listen(tape, units, dac);
        }
    }

    private void Load(CassetteImage tape, TapeMode mode)
    {
        _tape = tape;
        _leaders = null;
        Mode = mode;
        _byteIndex = mode == TapeMode.Recording ? tape.Bytes.Count : 0;
        _bitIndex = 0;
        _phase = 0;
        _cycleLength = 0;
        _inGap = false;
        _sinceCrossing = 0;
        _wasHigh = false;
        _recordByte = 0;
        _recordBits = 0;
        _recordState = CocoTapeBlockState.Seeking;
        _blockRemaining = 0;
        Input = true;
    }

    // Where a tape's leaders start: walking it block by block, as Color BASIC reads it (the $55s before a block, its
    // $3C sync byte, its type and length, then its data and checksum, which are passed over), each run of at least
    // LeaderRun $55 bytes between blocks, and one at the tape's start. Where a run is not followed by a whole block's
    // sync byte, the run and the one byte after it are passed over, and the walk goes on from there. A $55 inside a
    // block is never one.
    private static HashSet<int> Leaders(IReadOnlyList<byte> bytes)
    {
        HashSet<int> leaders = [];
        int at = 0;
        while (at < bytes.Count)
        {
            int run = at;
            while (run < bytes.Count && bytes[run] == 0x55) { run++; }
            if (run - at >= LeaderRun || (at == 0 && run > 0)) { leaders.Add(at); }
            if (run >= bytes.Count) { break; }
            if (bytes[run] != 0x3C || run + 2 >= bytes.Count)
            {
                at = run + 1;
                continue;
            }

            // The sync byte, the type, the length, the data and the checksum.
            at = run + 3 + bytes[run + 2] + 1;
        }

        return leaders;
    }

    private void Play(CassetteImage tape, int units)
    {
        IReadOnlyList<byte> bytes = tape.Bytes;
        _phase += units;
        while (true)
        {
            if (_cycleLength == 0)
            {
                if (_byteIndex >= bytes.Count)
                {
                    Input = true;
                    return;
                }

                if (_leaders is null || _leadersLength != bytes.Count)
                {
                    _leaders = Leaders(bytes);
                    _leadersLength = bytes.Count;
                }

                bool leaderStarts = _bitIndex == 0 && _leaders.Contains(_byteIndex);

                if (leaderStarts && !_inGap)
                {
                    _inGap = true;
                    _cycleLength = GapUnits;
                }
                else
                {
                    _inGap = false;
                    bool one = (bytes[_byteIndex] & (1 << _bitIndex)) != 0;
                    _cycleLength = one ? OneCycleUnits : ZeroCycleUnits;
                }
            }

            if (_phase < _cycleLength) { break; }
            _phase -= _cycleLength;
            _cycleLength = 0;
            if (_inGap) { continue; }
            if (++_bitIndex == 8)
            {
                _bitIndex = 0;
                _byteIndex++;
            }
        }

        Input = _inGap || _phase < _cycleLength / 2;
    }

    // Between blocks the bits slide through a window until it reads $55; in the leader they slide until it reads
    // the $3C sync byte, which alone fixes the alignment, since $55 matches at every even offset. Each eight
    // leader bits record one $55.
    private void Bit(CassetteImage tape, bool one)
    {
        if (_recordState is CocoTapeBlockState.Seeking or CocoTapeBlockState.Leader)
        {
            // The newest bit is the most significant of a byte sent least significant bit first.
            _recordByte = (_recordByte >> 1) | (one ? 0x80 : 0);
            if (_recordState == CocoTapeBlockState.Seeking)
            {
                if (_recordByte == 0x55)
                {
                    Append(tape, 0x55);
                    _recordState = CocoTapeBlockState.Leader;
                    _recordBits = 0;
                }

                return;
            }

            if (_recordByte == 0x3C)
            {
                Append(tape, 0x3C);
                _recordState = CocoTapeBlockState.Type;
                _recordByte = 0;
                _recordBits = 0;
            }
            else if (++_recordBits == 8)
            {
                Append(tape, 0x55);
                _recordBits = 0;
            }

            return;
        }

        if (one) { _recordByte |= 1 << _recordBits; }
        if (++_recordBits < 8) { return; }
        byte value = (byte)_recordByte;
        _recordByte = 0;
        _recordBits = 0;
        switch (_recordState)
        {
            case CocoTapeBlockState.Type:
                Append(tape, value);
                _recordState = CocoTapeBlockState.Length;
                return;
            case CocoTapeBlockState.Length:
                Append(tape, value);
                _blockRemaining = value;
                _recordState = value == 0 ? CocoTapeBlockState.Checksum : CocoTapeBlockState.Data;
                return;
            case CocoTapeBlockState.Data:
                Append(tape, value);
                if (--_blockRemaining == 0) { _recordState = CocoTapeBlockState.Checksum; }
                return;
            case CocoTapeBlockState.Checksum:
                Append(tape, value);
                _recordState = CocoTapeBlockState.Trailer;
                return;
            default:
                // The trailer's last cycle runs into whatever BASIC writes next, so it is recorded as written.
                Append(tape, 0x55);
                _recordState = CocoTapeBlockState.Seeking;
                return;
        }
    }

    private void Append(CassetteImage tape, byte value)
    {
        tape.Append(value);
        _byteIndex++;
    }

    // A cycle runs from one rising crossing of the DAC's midpoint to the next; a long one is a 0.
    private void Listen(CassetteImage tape, int units, int dac)
    {
        _sinceCrossing += units;
        bool high = dac >= 32;
        if (high && !_wasHigh)
        {
            double length = _sinceCrossing;
            _sinceCrossing = 0;
            if (length < ZeroCycleUnits * 2)
            {
                Bit(tape, length < ThresholdUnits);
            }
        }

        _wasHigh = high;
    }
}
