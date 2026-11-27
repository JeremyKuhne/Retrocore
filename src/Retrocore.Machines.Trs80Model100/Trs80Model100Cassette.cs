// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Devices;

namespace Retrocore.Machines.Trs80Model100;

/// <summary>
///  The Model 100's cassette port: SOD drives the tape's output, the tape's input comes back on SID, and port
///  <c>$E0</c> bit 3 runs the recorder's motor through its REM jack.
/// </summary>
/// <remarks>
///  <para>
///   The tape moves only while the motor runs: a tape that plays gives SID its changes then, and one that records
///   takes each change of SOD then, so time with the motor stopped is on neither. SID reads the input's level
///   inverted, as MAME's driver has it: low while the tape's level is high, and high with no tape playing.
///  </para>
/// </remarks>
public sealed class Trs80Model100Cassette
{
    private Trs80Model100Tape? _tape;
    private long _sinceChange;
    private long _untilChange;
    private int _position;
    private bool _output;
    private bool _level;

    /// <summary>
    ///  Gets what the deck is doing.
    /// </summary>
    public TapeMode Mode { get; private set; }

    /// <summary>
    ///  Gets whether the motor runs.
    /// </summary>
    public bool Motor { get; private set; }

    /// <summary>
    ///  Gets the SID input's level: low while the tape plays a high level, and high otherwise.
    /// </summary>
    public bool SerialInput => !(Mode == TapeMode.Playing && _level);

    /// <summary>
    ///  Gets the half cycles played or recorded.
    /// </summary>
    public int Position => Mode == TapeMode.Recording ? Length : _position;

    /// <summary>
    ///  Gets the half cycles on the tape.
    /// </summary>
    public int Length => _tape?.HalfCycles.Count ?? 0;

    /// <summary>
    ///  Gets whether the tape has played to its end.
    /// </summary>
    public bool AtEnd => Mode == TapeMode.Playing && _position >= Length;

    /// <summary>
    ///  Starts playing a tape from its beginning, once the motor runs.
    /// </summary>
    /// <param name="tape">The tape.</param>
    public void Play(Trs80Model100Tape tape)
    {
        ArgumentNullException.ThrowIfNull(tape);
        _tape = tape;
        Mode = TapeMode.Playing;
        _position = 0;
        _level = tape.StartsHigh;
        _untilChange = tape.HalfCycles.Count > 0 ? tape.HalfCycles[0] : long.MaxValue;
    }

    /// <summary>
    ///  Starts recording onto a tape, after what it holds, once the motor runs.
    /// </summary>
    /// <param name="tape">The tape.</param>
    public void Record(Trs80Model100Tape tape)
    {
        ArgumentNullException.ThrowIfNull(tape);
        _tape = tape;
        Mode = TapeMode.Recording;
        _sinceChange = 0;
        tape.Start(_output);
    }

    /// <summary>
    ///  Stops the deck and lets the tape go.
    /// </summary>
    public void Stop()
    {
        _tape = null;
        Mode = TapeMode.Stopped;
        _level = false;
    }

    /// <summary>
    ///  Advances one CPU cycle.
    /// </summary>
    /// <param name="motor">Whether port <c>$E0</c> runs the motor.</param>
    /// <param name="output">SOD's level.</param>
    internal void Tick(bool motor, bool output)
    {
        Motor = motor;
        bool changed = output != _output;
        _output = output;
        if (!motor || _tape is null) { return; }

        if (Mode == TapeMode.Recording)
        {
            _sinceChange++;
            if (changed)
            {
                _tape.Add(_sinceChange);
                _sinceChange = 0;
            }

            return;
        }

        if (--_untilChange > 0) { return; }
        _level = !_level;
        _position++;
        _untilChange = _position < Length ? _tape.HalfCycles[_position] : long.MaxValue;
    }
}
