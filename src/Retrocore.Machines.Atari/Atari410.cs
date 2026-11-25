// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Devices;
using Retrocore.Media;
using Retrocore.Media.Atari;

namespace Retrocore.Machines.Atari;

/// <summary>
///  The 410 Program Recorder: a cassette deck on the serial bus whose motor the PIA's CA2 runs, which plays its
///  decoded data into POKEY's serial input and records what POKEY sends.
/// </summary>
/// <remarks>
///  <para>
///   The 410 turns the tape's two tones into a level on the bus's DATA IN line, mark (5,327 Hz) high and space
///   (3,995 Hz) low (Altirra Hardware Reference Manual, 9.17). The deck here works at that level: playing, it puts
///   each block's gap and bits on <c>Pokey.SerialInputLevel</c>, where the OS's <c>C:</c> handler times each
///   record's two <c>$55</c> bytes to find the baud rate and then reads the bytes in asynchronous mode. The motor runs while CA2 is low and PLAY or
///   RECORD is down.
///  </para>
///  <para>
///   Recording, it keeps the bytes the computer sends while the motor runs (the OS sends them in two-tone mode, the
///   FSK the tape takes) as records: a pause of more than four byte times (20 ms after a record's first byte) starts
///   a new one, whose gap is the time since the last ended. The rate is taken from the bytes' spacing. Recording
///   replaces the tape from where it is.
///  </para>
/// </remarks>
public sealed class Atari410 : ITapeDrive, IMediumSlot
{
    private const MediaOperations Operations =
        MediaOperations.Insert | MediaOperations.Eject | MediaOperations.Record | MediaOperations.WriteProtect | MediaOperations.Save;

    private readonly AtariBus _bus;
    private readonly double _hertz;
    private AtariTape? _tape;
    private TapeMode _mode;
    private int _block;
    private long _cycles;
    private bool _motor;

    // Recording: the bytes of the record under way, the cycles they ended on, and when the last record ended.
    private readonly List<byte> _bytes = [];
    private readonly List<long> _ends = [];
    private long _recordedTo;

    /// <summary>
    ///  Constructs the recorder.
    /// </summary>
    /// <param name="bus">The machine's bus.</param>
    internal Atari410(AtariBus bus)
    {
        _bus = bus;
        _hertz = AtariTiming.CpuHertz(bus.Standard);
        Info = new()
        {
            Name = "Program Recorder",
            Description = "410 cassette recorder",
            Controller = "Serial bus, motor on PIA CA2",
            Formats = ["cas"],
            SaveFormats = ["cas"],
            Operations = Operations
        };
    }

    /// <inheritdoc/>
    public string Id => "cassette";

    /// <inheritdoc/>
    public DeviceKind Kind => DeviceKind.TapeDrive;

    /// <inheritdoc/>
    public DeviceInfo Info { get; }

    /// <summary>
    ///  Gets the tape, or null.
    /// </summary>
    public AtariTape? Tape => _tape;

    /// <summary>
    ///  Gets which of PLAY and RECORD is down, if either.
    /// </summary>
    public TapeMode Mode => _mode;

    /// <summary>
    ///  Gets whether the motor is running: CA2 low with PLAY or RECORD down.
    /// </summary>
    public bool Motor => _motor;

    /// <summary>
    ///  Gets the block the tape is at.
    /// </summary>
    public int Block => _block;

    /// <summary>
    ///  Gets or sets what the host calls the tape's image.
    /// </summary>
    public string Label { get; set; } = "";

    /// <summary>
    ///  Gets or sets the image's format, <c>CAS</c>.
    /// </summary>
    public string Format { get; set; } = "CAS";

    /// <inheritdoc/>
    public MediaState? Media => _tape is { } tape ? new(Label, Format, tape.IsWriteProtected, tape.IsDirty) : null;

    /// <inheritdoc/>
    public DeviceActivity Activity => !_motor
        ? DeviceActivity.Idle
        : _mode == TapeMode.Recording ? DeviceActivity.Writing : DeviceActivity.Reading;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The position and length are in milliseconds.
    ///  </para>
    /// </remarks>
    public TapeTransport Transport => new(_motor, _mode, (long)(PositionSeconds * 1000), (long)((_tape?.Duration ?? 0) * 1000));

    /// <inheritdoc/>
    public IMedium? Medium => _tape;

    /// <inheritdoc/>
    public int MountGeneration { get; private set; } = MountGenerations.Next();

    private double PositionSeconds
    {
        get
        {
            if (_tape is null) { return 0; }
            double seconds = _cycles / _hertz;
            for (int i = 0; i < _block && i < _tape.Blocks.Count; i++) { seconds += _tape.Blocks[i].Duration; }
            return seconds;
        }
    }

    /// <summary>
    ///  Puts a tape in, at its start, with the buttons up.
    /// </summary>
    /// <param name="tape">The tape.</param>
    /// <param name="label">What the host calls its image.</param>
    /// <param name="format">The image's format.</param>
    public void Insert(AtariTape tape, string label = "", string format = "CAS")
    {
        ArgumentNullException.ThrowIfNull(tape);
        Stop();
        _tape = tape;
        _block = 0;
        _cycles = 0;
        Label = label;
        Format = format;
        MountGeneration = MountGenerations.Next();
    }

    /// <summary>
    ///  Takes the tape out.
    /// </summary>
    /// <returns>The tape, or null.</returns>
    public AtariTape? Eject()
    {
        Stop();
        AtariTape? tape = _tape;
        _tape = null;
        MountGeneration = MountGenerations.Next();
        return tape;
    }

    /// <inheritdoc/>
    public void Mount(IMedium medium, string label, string format)
    {
        Insert(medium as AtariTape ?? throw new ArgumentException($"{Info.Name} does not take a {medium?.GetType().Name}.", nameof(medium)), label, format);
        Play();
    }

    /// <inheritdoc/>
    public IMedium? Unmount() => Eject();

    /// <summary>
    ///  Presses PLAY.
    /// </summary>
    public void Play()
    {
        Stop();
        _mode = TapeMode.Playing;
    }

    /// <summary>
    ///  Presses RECORD (with PLAY, as the 410 needs).
    /// </summary>
    /// <exception cref="InvalidOperationException">There is no tape, or it's write-protected.</exception>
    public void Record()
    {
        if (_tape is null || _tape.IsWriteProtected)
        {
            throw new InvalidOperationException("There is no tape to record on, or it is write-protected.");
        }

        Stop();
        _mode = TapeMode.Recording;
    }

    /// <summary>
    ///  Presses STOP: the buttons come up, and anything being recorded is kept.
    /// </summary>
    public void Stop()
    {
        if (_motor && _mode == TapeMode.Recording) { EndRecording(); }
        _mode = TapeMode.Stopped;
        _motor = false;
        Level = true;
    }

    /// <summary>
    ///  Winds the tape back to its start.
    /// </summary>
    public void Rewind()
    {
        _block = 0;
        _cycles = 0;
    }

    /// <inheritdoc/>
    public void Saved(string label, string format, bool whole = true)
    {
        AtariTape tape = _tape ?? throw new InvalidOperationException("There is no tape.");
        if (whole)
        {
            tape.MarkSaved();
        }
        else
        {
            tape.MarkChanged();
        }

        Label = label;
        Format = format;
    }

    /// <summary>
    ///  Gets the level the recorder puts on the serial bus's data-in line: the tape's bits while it plays, and high
    ///  (idle) otherwise.
    /// </summary>
    internal bool Level { get; private set; } = true;

    /// <summary>
    ///  Advances a machine cycle: the motor follows CA2, and a playing tape drives POKEY's serial input.
    /// </summary>
    internal void Tick()
    {
        // CA2, an output when PACTL bits 5 and 4 are set, runs the motor while low.
        bool line = (_bus.Pia.ControlA & 0x30) == 0x30 && !_bus.Pia.CA2Output;
        bool motor = line && _tape is not null && _mode != TapeMode.Stopped;
        if (motor != _motor)
        {
            if (_mode == TapeMode.Recording)
            {
                if (motor)
                {
                    StartRecording();
                }
                else
                {
                    EndRecording();
                }
            }

            _motor = motor;
            if (!motor) { Level = true; }
        }

        if (!motor || _mode != TapeMode.Playing || _tape is not AtariTape tape) { return; }

        _cycles++;
        while (_block < tape.Blocks.Count && _cycles / _hertz >= tape.Blocks[_block].Duration)
        {
            _cycles -= (long)(tape.Blocks[_block].Duration * _hertz);
            _block++;
        }

        Level = _block >= tape.Blocks.Count || tape.Blocks[_block].LevelAt(_cycles / _hertz);
    }

    /// <summary>
    ///  Takes a byte the computer sent, which is recorded while the motor runs in RECORD.
    /// </summary>
    /// <param name="value">The byte.</param>
    internal void Sent(byte value)
    {
        if (!_motor || _mode != TapeMode.Recording) { return; }
        long now = _bus.Cycles;

        // A pause of more than four bytes at the record's rate starts a new record.
        if (_ends.Count >= 2)
        {
            long spacing = (_ends[^1] - _ends[0]) / (_ends.Count - 1);
            if (now - _ends[^1] > spacing * 4) { EndRecord(); }
        }
        else if (_ends.Count == 1 && now - _ends[0] > (long)(_hertz / 50))
        {
            EndRecord();
        }

        _bytes.Add(value);
        _ends.Add(now);
    }

    private void StartRecording()
    {
        if (_tape is not AtariTape tape) { return; }

        // Recording replaces the tape from the block it is at, unless the tape was protected after RECORD went down.
        if (!tape.IsWriteProtected) { tape.Record(Math.Min(_block, tape.Blocks.Count), []); }
        _block = tape.Blocks.Count;
        _cycles = 0;
        _recordedTo = _bus.Cycles;
        _bytes.Clear();
        _ends.Clear();
    }

    private void EndRecording()
    {
        EndRecord();
        _block = _tape?.Blocks.Count ?? 0;
        _cycles = 0;
    }

    // The record under way goes on the tape, after the gap since the last.
    private void EndRecord()
    {
        if (_bytes.Count == 0 || _tape is not AtariTape tape) { return; }
        if (tape.IsWriteProtected)
        {
            // A tape protected after RECORD went down takes nothing: the bytes sent meanwhile are dropped.
            _bytes.Clear();
            _ends.Clear();
            return;
        }

        int baud = AtariTape.StandardBaud;
        if (_ends.Count >= 2)
        {
            double cyclesPerByte = (double)(_ends[^1] - _ends[0]) / (_ends.Count - 1);
            baud = (int)Math.Round(_hertz * 10 / cyclesPerByte);
        }

        long byteCycles = (long)(_hertz * 10 / baud);
        long start = _ends[0] - byteCycles;
        int gap = (int)Math.Max(0, Math.Round((start - _recordedTo) * 1000 / _hertz));
        tape.Append(new(gap, baud, [.. _bytes], Durations: null));
        _recordedTo = _ends[^1];
        _bytes.Clear();
        _ends.Clear();
    }
}
