// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Devices;
using Retrocore.Media;
using Retrocore.Media.Acorn;

namespace Retrocore.Machines.Acorn;

/// <summary>
///  The cassette recorder on the BBC Micro's cassette port, whose motor the serial ULA's relay switches.
/// </summary>
/// <remarks>
///  <para>
///   The tape moves while a key is down and the relay is closed, one 2 MHz cycle at a time. Playing, it gives the
///   serial ULA each half-cycle as it ends; recording, it takes the half-cycles the ULA makes, replacing what was
///   on the tape from the head on. Silence recorded after silence lengthens it.
///  </para>
/// </remarks>
public sealed class BbcCassette : ITapeDrive, IMediumSlot
{
    // A unit of the tape, 1/4,800 second, is 416⅔ CPU cycles: time is kept in thirds of a cycle.
    private const int ThirdsPerUnit = 1250;

    private AcornTape? _tape;
    private string _label = "";
    private string _format = "";
    private TapeMode _mode;
    private int _index;
    private long _elapsed;
    private bool _silenceRecorded;

    /// <summary>
    ///  Builds the recorder.
    /// </summary>
    internal BbcCassette()
    {
        Info = new()
        {
            Name = "Cassette",
            Description = "Cassette recorder, 1200 or 300 baud",
            Controller = "Serial ULA: tones to and from the 6850 ACIA, and the motor relay",
            Formats = ["uef"],
            SaveFormats = ["uef"],
            Operations = MediaOperations.Insert | MediaOperations.Eject | MediaOperations.Record | MediaOperations.Save | MediaOperations.Keys
        };
    }

    /// <inheritdoc/>
    public string Id => "cassette";

    /// <inheritdoc/>
    public DeviceKind Kind => DeviceKind.TapeDrive;

    /// <inheritdoc/>
    public DeviceInfo Info { get; }

    /// <summary>
    ///  Gets the tape in the recorder, or null.
    /// </summary>
    public AcornTape? Tape => _tape;

    /// <summary>
    ///  Gets which keys are down.
    /// </summary>
    public TapeMode Mode => _mode;

    /// <summary>
    ///  Gets whether the motor relay is closed.
    /// </summary>
    public bool Motor { get; internal set; }

    /// <summary>
    ///  Gets the half-cycle the head is on.
    /// </summary>
    public int Position => _index;

    /// <inheritdoc/>
    public MediaState? Media => _tape is null
        ? null
        : new(_label, _format, _tape.IsWriteProtected, _tape.IsDirty);

    /// <inheritdoc/>
    public DeviceActivity Activity => !Motor || _tape is null || _mode == TapeMode.Stopped
        ? DeviceActivity.Idle
        : _mode == TapeMode.Recording ? DeviceActivity.Writing : DeviceActivity.Reading;

    /// <inheritdoc/>
    public TapeTransport Transport => new(Motor, _mode, _index, _tape?.HalfCycles.Count ?? 0);

    /// <inheritdoc/>
    IMedium? IMediumSlot.Medium => _tape;

    /// <inheritdoc/>
    public int MountGeneration { get; private set; } = MountGenerations.Next();

    /// <summary>
    ///  Puts a tape in, rewound, with no key down.
    /// </summary>
    /// <param name="tape">The tape.</param>
    /// <param name="label">Its name, for display.</param>
    /// <param name="format">Its image format, such as <c>UEF</c>.</param>
    /// <param name="changed">Whether it differs from its image, as a blank tape does.</param>
    public void Insert(AcornTape tape, string label, string format = "UEF", bool changed = false)
    {
        ArgumentNullException.ThrowIfNull(tape);
        _tape = tape;
        _label = label;
        _format = format;
        if (changed) { tape.MarkChanged(); }
        _mode = TapeMode.Stopped;
        MountGeneration = MountGenerations.Next();
        Rewind();
    }

    /// <summary>
    ///  Takes the tape out, releasing the keys.
    /// </summary>
    /// <returns>The tape, or null.</returns>
    public AcornTape? Eject()
    {
        AcornTape? tape = _tape;
        _tape = null;
        _label = "";
        _format = "";
        _mode = TapeMode.Stopped;
        MountGeneration = MountGenerations.Next();
        Rewind();
        return tape;
    }

    /// <summary>
    ///  Presses PLAY.
    /// </summary>
    /// <exception cref="InvalidOperationException">There is no tape.</exception>
    public void Play()
    {
        if (_tape is null) { throw new InvalidOperationException("There is no tape in the recorder."); }
        _mode = TapeMode.Playing;
    }

    /// <summary>
    ///  Presses RECORD and PLAY together.
    /// </summary>
    /// <exception cref="InvalidOperationException">There is no tape, or its record tab is gone.</exception>
    public void Record()
    {
        if (_tape is null) { throw new InvalidOperationException("There is no tape in the recorder."); }
        if (_tape.IsWriteProtected)
        {
            throw new InvalidOperationException("The tape is write protected: RECORD will not go down.");
        }

        _mode = TapeMode.Recording;
        _silenceRecorded = false;
    }

    /// <summary>
    ///  Presses STOP.
    /// </summary>
    public void Stop() => _mode = TapeMode.Stopped;

    /// <summary>
    ///  Rewinds the tape to its start.
    /// </summary>
    public void Rewind() => Wind(0);

    /// <summary>
    ///  Moves the head to a half-cycle, as fast forward and rewind do.
    /// </summary>
    /// <param name="halfCycle">The half-cycle, at most the tape's count.</param>
    public void Wind(int halfCycle)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(halfCycle);
        ArgumentOutOfRangeException.ThrowIfGreaterThan(halfCycle, _tape?.HalfCycles.Count ?? 0);
        _index = halfCycle;
        _elapsed = 0;
        _silenceRecorded = false;
    }

    /// <inheritdoc/>
    public void Saved(string label, string format, bool whole)
    {
        if (_tape is null) { throw new InvalidOperationException("There is no tape in the recorder."); }
        _label = label;
        _format = format;
        if (whole) { _tape.MarkSaved(); }
        else { _tape.MarkChanged(); }
    }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The tape goes in with PLAY down, as a tape the debugger inserts does, since the BBC Micro's motor relay, not
    ///   a key, starts it.
    ///  </para>
    /// </remarks>
    public void Mount(IMedium medium, string label, string format)
    {
        Insert(medium as AcornTape ?? throw new ArgumentException($"{Info.Name} does not take a {medium?.GetType().Name}.", nameof(medium)), label, format);
        Play();
    }

    /// <inheritdoc/>
    public IMedium? Unmount() => Eject();

    /// <summary>
    ///  Gets whether the tape moves and records.
    /// </summary>
    internal bool Recording => Motor && _mode == TapeMode.Recording && _tape is not null;

    /// <summary>
    ///  Advances the tape one 2 MHz cycle, playing.
    /// </summary>
    /// <returns>The length of a half-cycle that ended, in units; 0 when none did.</returns>
    internal int Tick()
    {
        if (!Motor || _mode != TapeMode.Playing || _tape is null || _index >= _tape.HalfCycles.Count) { return 0; }
        _elapsed += 3;
        int length = _tape.HalfCycles[_index];
        if (_elapsed < (long)length * ThirdsPerUnit) { return 0; }
        _elapsed -= (long)length * ThirdsPerUnit;
        _index++;
        return length;
    }

    /// <summary>
    ///  Records a half-cycle at the head, or silence.
    /// </summary>
    /// <param name="units">Its length in units of 1/4,800 second.</param>
    /// <param name="silence">Whether it is silence, which lengthens silence just recorded.</param>
    internal void Write(int units, bool silence)
    {
        if (!Recording || _tape is null) { return; }
        if (silence && _silenceRecorded && _index > 0)
        {
            _tape.Record(_index - 1, _tape.HalfCycles[_index - 1] + units);
            return;
        }

        _tape.Record(_index++, silence ? Math.Max(units, 3) : units);
        _silenceRecorded = silence;
    }
}
