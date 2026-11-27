// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Devices;
using Retrocore.Media;
using Retrocore.Media.Commodore;

namespace Retrocore.Machines.Commodore;

/// <summary>
///  A Commodore C2N or 1530 Datasette on a cassette port: PLAY, RECORD, STOP and the tape's position, the motor the
///  computer runs, and the read and write lines.
/// </summary>
/// <remarks>
///  <para>
///   The sense line is low while PLAY is down, alone or with RECORD; the motor runs while the computer holds its line
///   low. Playing, the read line falls at each pulse's start and rises halfway through. Recording, each rise of the
///   write line ends a pulse and starts the next, as the read line then falls there, the Datasette inverting what it
///   records. A recording replaces the tape from the head on.
///  </para>
///  <para>
///   The tape's pulses are microseconds; the Datasette counts them in the computer's cycles, a microsecond on the PET
///   and 0.98 or 0.90 of one on the VIC-20.
///  </para>
/// </remarks>
public sealed class CommodoreDatasette : ITapeDrive, IMediumSlot
{
    private readonly double _cyclesPerMicrosecond;
    private CommodoreTape? _tape;
    private string _label = "";
    private string _format = "";
    private TapeMode _mode;
    private int _index;
    private int _elapsed;
    private int _length;
    private bool _write;
    private bool _recordingStarted;

    /// <summary>
    ///  Builds a Datasette for a port.
    /// </summary>
    /// <param name="id">The device's id, such as <c>cassette1</c>.</param>
    /// <param name="name">Its name, such as <c>Cassette #1</c>.</param>
    /// <param name="controller">The lines it is wired to.</param>
    /// <param name="cpuHertz">The computer's clock, which counts the pulses.</param>
    /// <param name="tapMachine">The machine byte of the TAP images it saves.</param>
    /// <param name="tapVideo">Their video byte.</param>
    internal CommodoreDatasette(
        string id,
        string name,
        string controller,
        double cpuHertz,
        byte tapMachine = TapFormat.PetMachine,
        byte tapVideo = TapFormat.Pal)
    {
        Id = id;
        _cyclesPerMicrosecond = cpuHertz / 1_000_000;
        TapMachine = tapMachine;
        TapVideo = tapVideo;
        Info = new()
        {
            Name = name,
            Description = "Commodore C2N or 1530 Datasette",
            Controller = controller,
            Formats = ["tap", "wav", "t64"],
            SaveFormats = ["tap", "wav"],
            Operations = MediaOperations.Insert | MediaOperations.Eject | MediaOperations.Record | MediaOperations.Save
        };
    }

    /// <summary>
    ///  Gets the machine byte of the TAP images the Datasette saves, whose clock they count.
    /// </summary>
    public byte TapMachine { get; }

    /// <summary>
    ///  Gets the video byte of the TAP images it saves.
    /// </summary>
    public byte TapVideo { get; }

    /// <inheritdoc/>
    public string Id { get; }

    /// <inheritdoc/>
    public DeviceKind Kind => DeviceKind.TapeDrive;

    /// <inheritdoc/>
    public DeviceInfo Info { get; }

    /// <summary>
    ///  Gets the tape in the Datasette, or null.
    /// </summary>
    public CommodoreTape? Tape => _tape;

    /// <summary>
    ///  Gets which keys are down.
    /// </summary>
    public TapeMode Mode => _mode;

    /// <summary>
    ///  Gets whether the computer runs the motor.
    /// </summary>
    public bool Motor { get; private set; }

    /// <summary>
    ///  Gets the read line's level.
    /// </summary>
    public bool Read { get; private set; } = true;

    /// <summary>
    ///  Gets whether a key is down, which pulls the sense line low.
    /// </summary>
    public bool KeyDown => _mode != TapeMode.Stopped;

    /// <summary>
    ///  Gets the pulse the head is on.
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
    public TapeTransport Transport => new(Motor, _mode, _index, _tape?.Pulses.Count ?? 0);

    /// <inheritdoc/>
    IMedium? IMediumSlot.Medium => _tape;

    /// <inheritdoc/>
    public int MountGeneration { get; private set; } = MountGenerations.Next();

    /// <summary>
    ///  Puts a tape in, rewound, with no key down.
    /// </summary>
    /// <param name="tape">The tape.</param>
    /// <param name="label">Its name, for display.</param>
    /// <param name="format">Its image format, such as <c>TAP</c>.</param>
    /// <param name="changed">Whether it differs from its image, as a blank tape does.</param>
    public void Insert(CommodoreTape tape, string label, string format, bool changed = false)
    {
        ArgumentNullException.ThrowIfNull(tape);
        if (changed) { tape.MarkChanged(); } else { tape.MarkSaved(); }
        Load(tape, label, format);
    }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The tape keeps its changes, as a tape put back for Undo has them, and goes in rewound with no key down.
    ///  </para>
    /// </remarks>
    public void Mount(IMedium medium, string label, string format) => Load(
        medium as CommodoreTape ?? throw new ArgumentException($"The Datasette does not take a {medium?.GetType().Name}.", nameof(medium)),
        label,
        format);

    /// <inheritdoc/>
    public IMedium? Unmount() => Eject();

    /// <summary>
    ///  Takes the tape out, releasing the keys.
    /// </summary>
    /// <returns>The tape, or null.</returns>
    public CommodoreTape? Eject()
    {
        CommodoreTape? tape = _tape;
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
        if (_tape is null) { throw new InvalidOperationException("There is no tape in the Datasette."); }
        _mode = TapeMode.Playing;
        _recordingStarted = false;
    }

    /// <summary>
    ///  Presses RECORD and PLAY together.
    /// </summary>
    /// <exception cref="InvalidOperationException">There is no tape, or its record tab is gone.</exception>
    public void Record()
    {
        if (_tape is null) { throw new InvalidOperationException("There is no tape in the Datasette."); }
        if (_tape.IsWriteProtected)
        {
            throw new InvalidOperationException("The tape is write protected: RECORD will not go down.");
        }

        _mode = TapeMode.Recording;
        _recordingStarted = false;
    }

    /// <summary>
    ///  Presses STOP, which releases PLAY and RECORD.
    /// </summary>
    public void Stop()
    {
        _mode = TapeMode.Stopped;
        _recordingStarted = false;
    }

    /// <summary>
    ///  Rewinds the tape to its start.
    /// </summary>
    public void Rewind()
    {
        _index = 0;
        _elapsed = 0;
        _length = 0;
        _recordingStarted = false;
        Read = true;
    }

    /// <summary>
    ///  Moves the head to a pulse, as fast forward and rewind do.
    /// </summary>
    /// <param name="pulse">The pulse, at most the tape's count.</param>
    public void Wind(int pulse)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(pulse);
        ArgumentOutOfRangeException.ThrowIfGreaterThan(pulse, _tape?.Pulses.Count ?? 0);
        _index = pulse;
        _elapsed = 0;
        _length = 0;
        _recordingStarted = false;
    }

    /// <inheritdoc/>
    public void Saved(string label, string format, bool whole)
    {
        if (_tape is null) { throw new InvalidOperationException("There is no tape in the Datasette."); }
        _label = label;
        _format = format;
        if (whole) { _tape.MarkSaved(); } else { _tape.MarkChanged(); }
    }

    private void Load(CommodoreTape tape, string label, string format)
    {
        _tape = tape;
        _label = label;
        _format = format;
        _mode = TapeMode.Stopped;
        MountGeneration = MountGenerations.Next();
        Rewind();
    }

    /// <summary>
    ///  Advances the tape one CPU cycle.
    /// </summary>
    /// <param name="motor">Whether the motor runs.</param>
    /// <param name="write">The write line's level.</param>
    internal void Tick(bool motor, bool write)
    {
        if (motor != Motor)
        {
            Motor = motor;
            _recordingStarted = false;
        }

        bool rose = write && !_write;
        _write = write;
        if (!motor || _tape is null) { return; }

        if (_mode == TapeMode.Playing)
        {
            if (_index >= _tape.Pulses.Count)
            {
                Read = true;
                return;
            }

            // A pulse's length in cycles, worked out as the head reaches it.
            if (_length == 0) { _length = Math.Max(1, (int)Math.Round(_tape.Pulses[_index] * _cyclesPerMicrosecond)); }
            if (++_elapsed >= _length)
            {
                _index++;
                _elapsed = 0;
                _length = 0;
                Read = _index >= _tape.Pulses.Count;
                return;
            }

            Read = _elapsed >= _length / 2;
        }
        else if (_mode == TapeMode.Recording)
        {
            _elapsed++;
            if (!rose) { return; }

            // The first rise after the motor starts begins the first pulse.
            if (_tape.IsWriteProtected)
            {
                // The record tab broken off while RECORD was down lets the key up, as RECORD cannot stay down.
                Stop();
                return;
            }

            if (_recordingStarted && _elapsed > 0)
            {
                _tape.Record(_index, Math.Max(1, (int)Math.Round(_elapsed / _cyclesPerMicrosecond)));
                _index++;
            }

            _recordingStarted = true;
            _elapsed = 0;
            _length = 0;
        }
    }
}
