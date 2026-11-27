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
///   inverted, as MAME's driver has it: low while the tape's level is high, high with no tape, and while recording
///   the inverse of SOD, which MAME's recorder gives back as its input.
///  </para>
///  <para>
///   A change of SOD while the motor is stopped goes on the tape as it moves again. One made in the cycle the motor
///   stops leaves a half of one cycle, shorter than a WAV file's sample, which a saved file merges into the halves
///   beside it; <c>CSAVE</c> runs the motor before it writes and stops it after, so its tapes have none.
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
    private bool _recorded;

    /// <summary>
    ///  Gets what the deck is doing.
    /// </summary>
    public TapeMode Mode { get; private set; }

    /// <summary>
    ///  Gets whether the motor runs.
    /// </summary>
    public bool Motor { get; private set; }

    /// <summary>
    ///  Gets the SID input's level: low while the tape plays a high level, the inverse of SOD while it records, and
    ///  high with no tape.
    /// </summary>
    public bool SerialInput => Mode switch
    {
        TapeMode.Playing => !_level,
        TapeMode.Recording => !_output,
        _ => true
    };

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

        // The level the tape ends at: it alternates from its start.
        _recorded = tape.StartsHigh ^ ((tape.HalfCycles.Count & 1) != 0);
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
        _output = output;
        if (!motor || _tape is null) { return; }

        // A recording changes level where SOD differs from the level it last took, so SOD's changes with the motor
        // stopped leave its polarity right.
        if (Mode == TapeMode.Recording)
        {
            _sinceChange++;
            if (output != _recorded)
            {
                _tape.Add(_sinceChange);
                _sinceChange = 0;
                _recorded = output;
            }

            return;
        }

        if (--_untilChange > 0) { return; }
        _level = !_level;
        _position++;
        _untilChange = _position < Length ? _tape.HalfCycles[_position] : long.MaxValue;
    }
}
