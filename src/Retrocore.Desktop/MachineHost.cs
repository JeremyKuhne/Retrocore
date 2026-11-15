// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug;
using System.Diagnostics;
using System.Text.Json.Nodes;
using Touki;

namespace Retrocore.Desktop;

/// <summary>
///  Runs one machine on its own thread at its clock's speed, and hands its latest frame and sound to the window.
/// </summary>
/// <remarks>
///  <para>
///   Everything that touches the machine holds <see cref="_gate"/>: the run thread, for a few milliseconds of the
///   machine's time at once, and the window, for a key or a setting. The window never waits on the machine for a
///   frame: the run thread renders one when the window asks, into a buffer the window copies from.
///  </para>
/// </remarks>
internal sealed class MachineHost : DisposableBase
{
    // The longest the run thread holds the gate in one slice, so a key or a setting waits no longer.
    private const double SliceMilliseconds = 4;

    // Further behind than this, the machine gives up catching up and keeps time from now, as after a pause.
    private const double MaximumLagSeconds = 0.1;

    // The cycles run between looks at the clock.
    private const int BatchCycles = 256;

    private readonly IDebugTarget _target;
    private readonly Lock _gate = new();
    private readonly Thread _thread;
    private readonly SdlAudio _audio = new();
    private volatile bool _stopping;

    // The window's calls waiting for the gate; the run thread steps aside for them between slices, since a lock
    // released and taken straight back can keep them waiting for many slices.
    private int _waiting;
    private volatile bool _frameWanted = true;
    private volatile bool _accelerated;

    // The cycle the run thread stops at and waits, for a measurement to start or end there; MaxValue for none.
    private ulong _holdAt = ulong.MaxValue;
    private readonly ManualResetEventSlim _held = new(initialState: false);

    // Why the CPU stopped, such as a 6502 jammed by an illegal opcode, or null while it runs; Reset clears it.
    private volatile string? _stopped;
    private double _speed = 1;
    private bool _paceAgain = true;

    // The newest frame, which the window takes; written only by the run thread, under _frameLock.
    private readonly Lock _frameLock = new();
    private byte[] _frame = [];
    private int _frameWidth;
    private int _frameHeight;
    private long _frameNumber;

    // Measured on the run thread over the last second.
    private long _measureStart = Stopwatch.GetTimestamp();
    private ulong _measureCycles;
    private ulong _publishedCycles;

    /// <summary>
    ///  Builds the machine a launch configuration describes, as the debug host's launch does.
    /// </summary>
    /// <param name="configuration">The launch arguments, such as <c>{ "machine": "apple2" }</c>.</param>
    internal MachineHost(JsonObject configuration)
    {
        Configuration = configuration;
        _target = OffMachine.Build(configuration);
        _measureCycles = _target.CycleCount;
        _thread = new(Run) { IsBackground = true, Name = "Machine" };
    }

    /// <summary>
    ///  Gets the launch configuration the machine was built from.
    /// </summary>
    internal JsonObject Configuration { get; }

    /// <summary>
    ///  Gets the machine's name, as its model row names it, such as <c>Apple IIe</c>.
    /// </summary>
    internal string Name
    {
        get
        {
            using (Gate())
            {
                HardwareRow? model = _target.Hardware().FirstOrDefault(row => row.Id == "model");
                return model?.Name ?? Configuration["machine"]?.GetValue<string>() ?? "Machine";
            }
        }
    }

    /// <summary>
    ///  Gets the catalog's key map name for the machine, as the display panel keys its maps.
    /// </summary>
    internal string KeyMapName => Configuration["machine"]?.GetValue<string>() ?? "apple2";

    /// <summary>
    ///  Gets the speed the machine keeps to: 1, 2, 4 or 8 times its clock, or 0 for as fast as it can.
    /// </summary>
    internal double Speed
    {
        get => Volatile.Read(ref _speed);
        set
        {
            using (Gate())
            {
                _speed = value;
                _paceAgain = true;
                _audio.Clear();
            }
        }
    }

    /// <summary>
    ///  Gets what the machine's fast drive setting speeds up, <c>disk</c> or <c>tape</c>, or null when it has none.
    /// </summary>
    internal string? FastDriveKind => _target switch
    {
        Apple2DebugTarget or Apple3DebugTarget or Trs80Model2DebugTarget => "disk",
        Apple1DebugTarget or CocoDebugTarget or Trs80DebugTarget or Trs80Model3DebugTarget or AltairDebugTarget => "tape",
        _ => null
    };

    /// <summary>
    ///  Gets or sets whether the machine runs as fast as it can while a disk drive's motor turns or a tape plays,
    ///  as the display panel's Fast disk does, then goes back to its speed.
    /// </summary>
    internal bool FastDrives
    {
        get
        {
            using (Gate())
            {
                return _target switch
                {
                    Apple2DebugTarget apple2 => apple2.FastDisk,
                    Apple3DebugTarget apple3 => apple3.FastDisk,
                    Trs80Model2DebugTarget model2 => model2.FastDisk,
                    Apple1DebugTarget apple1 => apple1.FastCassette,
                    CocoDebugTarget coco => coco.FastCassette,
                    Trs80DebugTarget model1 => model1.FastCassette,
                    Trs80Model3DebugTarget model3 => model3.FastCassette,
                    AltairDebugTarget altair => altair.FastCassette,
                    _ => false
                };
            }
        }
        set
        {
            using (Gate())
            {
                switch (_target)
                {
                    case Apple2DebugTarget apple2:
                        apple2.FastDisk = value;
                        break;
                    case Apple3DebugTarget apple3:
                        apple3.FastDisk = value;
                        break;
                    case Trs80Model2DebugTarget model2:
                        model2.FastDisk = value;
                        break;
                    case Apple1DebugTarget apple1:
                        apple1.FastCassette = value;
                        break;
                    case CocoDebugTarget coco:
                        coco.FastCassette = value;
                        break;
                    case Trs80DebugTarget model1:
                        model1.FastCassette = value;
                        break;
                    case Trs80Model3DebugTarget model3:
                        model3.FastCassette = value;
                        break;
                    case AltairDebugTarget altair:
                        altair.FastCassette = value;
                        break;
                }
            }
        }
    }

    /// <summary>
    ///  Gets whether the machine is running as fast as it can for a busy drive just now.
    /// </summary>
    internal bool Accelerated => _accelerated;

    /// <summary>
    ///  Gets the sound modes the machine offers: <c>off</c> and <c>speaker</c>, and <c>mockingboard</c> on an Apple II
    ///  with one in slot 4.
    /// </summary>
    internal IReadOnlyList<string> SoundModes
    {
        get
        {
            using (Gate())
            {
                return SoundRequest() is not null
                    && _target.DisplayState(running: true)["mockingboard"] is JsonValue board
                    && board.TryGetValue(out bool installed)
                    && installed
                        ? ["off", "speaker", "mockingboard"]
                        : ["off", "speaker"];
            }
        }
    }

    /// <summary>
    ///  Gets or sets the sound mode. A machine with a sound request of its own, as the Apple II, Apple III and CoCo
    ///  have, changes what it makes, so a machine launched with its sound off can be heard again; on the others the
    ///  host plays or drops the sound.
    /// </summary>
    internal string SoundMode
    {
        get
        {
            using (Gate())
            {
                return SoundRequest() is not null
                    && _target.DisplayState(running: true)["sound"] is JsonValue mode
                    && mode.TryGetValue(out string? text)
                        ? text
                        : SoundOn ? "speaker" : "off";
            }
        }
        set
        {
            using (Gate())
            {
                if (SoundRequest() is { } request) { _target.Requests[request](new JsonObject { ["mode"] = value }); }
                SoundOn = value != "off";
                _audio.Clear();
            }
        }
    }

    /// <summary>
    ///  Gets or sets whether the machine's sound plays.
    /// </summary>
    internal bool SoundOn { get; set; } = true;

    /// <summary>
    ///  Gets or sets the sound's volume, 0 to 1.
    /// </summary>
    internal float Volume
    {
        get
        {
            using (Gate()) { return _audio.Volume; }
        }
        set
        {
            // Under the gate, where the run thread opens and replaces the sound stream, so the gain never goes to a
            // stream that has just been destroyed.
            using (Gate()) { _audio.Volume = value; }
        }
    }

    /// <summary>
    ///  Gets the machine's cycles a second over the last second.
    /// </summary>
    internal double MeasuredHertz { get; private set; }

    /// <summary>
    ///  Gets the machine's cycles so far, read without the gate, so it may be a slice behind.
    /// </summary>
    internal ulong CycleCount => Volatile.Read(ref _publishedCycles);

    /// <summary>
    ///  Gets the machine's clock in cycles a second.
    /// </summary>
    internal int ClockHertz => _target.ClockHertz;

    /// <summary>
    ///  Gets the number of times the sound ran dry while the machine ran at its real speed.
    /// </summary>
    internal int AudioUnderruns => _audio.Underruns;

    /// <summary>
    ///  Gets whether the sound device opened.
    /// </summary>
    internal bool AudioOpen => _audio.IsOpen;

    /// <summary>
    ///  Gets the monitors the machine's video can be shown on.
    /// </summary>
    internal IReadOnlyList<string> Screens
    {
        get { using (Gate()) { return _target.Screens; } }
    }

    /// <summary>
    ///  Gets or sets the monitor the video is shown on.
    /// </summary>
    internal string Screen
    {
        get { using (Gate()) { return _target.Screen; } }
        set
        {
            using (Gate()) { _target.Screen = value; }
            _frameWanted = true;
        }
    }

    /// <summary>
    ///  Starts the machine running.
    /// </summary>
    internal void Start() => _thread.Start();

    /// <summary>
    ///  Types a key on the machine's keyboard.
    /// </summary>
    /// <param name="code">The ASCII code, 0-127.</param>
    internal void Key(int code)
    {
        using (Gate()) { _target.Key(code); }
    }

    /// <summary>
    ///  Presses the machine's reset.
    /// </summary>
    internal void Reset()
    {
        using (Gate())
        {
            _target.Reset();
            _stopped = null;
            _paceAgain = true;
        }
    }

    /// <summary>
    ///  Gets why the machine's CPU stopped, such as on an opcode that jams it, or null while it runs. The machine
    ///  waits, with its picture as it was, until <see cref="Reset"/>.
    /// </summary>
    internal string? Stopped => _stopped;

    /// <summary>
    ///  Gets the machine's installed hardware, in its documented order.
    /// </summary>
    /// <returns>The rows.</returns>
    internal IReadOnlyList<HardwareRow> Hardware()
    {
        using (Gate()) { return _target.Hardware(); }
    }

    /// <summary>
    ///  Gets each device with media and what it is doing.
    /// </summary>
    /// <returns>The devices' names, media, kind, lock and activity.</returns>
    internal List<DriveRow> Devices()
    {
        using (Gate())
        {
            return [.. _target.Devices.Select(device => new DriveRow(
                device.Info.Name,
                device.Kind,
                device.Media is { } media ? Path.GetFileName(media.Label) + (media.Changed ? " · changed" : "") : null,
                device.Media?.WriteProtected ?? false,
                device.Activity))];
        }
    }

    /// <summary>
    ///  Gets the text on the machine's screen, as the display panel's text rows give it.
    /// </summary>
    /// <returns>The rows, one a line.</returns>
    internal string ScreenText()
    {
        using (Gate())
        {
            return _target.DisplayState(running: true)["rows"] is JsonArray rows
                ? string.Join('\n', rows.Select(row => row?.GetValue<string>() ?? ""))
                : "";
        }
    }

    /// <summary>
    ///  Copies the newest frame when there is one the caller has not seen.
    /// </summary>
    /// <param name="seen">The number of the frame the caller has.</param>
    /// <param name="copy">Copies the pixels, given the RGBA bytes, width and height.</param>
    /// <returns>The number of the frame now copied, or <paramref name="seen"/> when there was none newer.</returns>
    internal long TakeFrame(long seen, Action<ReadOnlySpan<byte>, int, int> copy)
    {
        _frameWanted = true;
        lock (_frameLock)
        {
            if (_frameNumber == seen || _frame.Length == 0) { return seen; }
            copy(_frame, _frameWidth, _frameHeight);
            return _frameNumber;
        }
    }

    /// <summary>
    ///  Has the run thread stop at a cycle, exactly, and wait there until held elsewhere, so a measurement starts and
    ///  ends at whole cycles of the machine's own rather than at the run thread's slices.
    /// </summary>
    /// <param name="cycle">The cycle to stop at, or <see cref="ulong.MaxValue"/> to run on.</param>
    internal void HoldAt(ulong cycle)
    {
        _held.Reset();
        Volatile.Write(ref _holdAt, cycle);
    }

    /// <summary>
    ///  Waits for the run thread to reach the cycle <see cref="HoldAt"/> set.
    /// </summary>
    internal void WaitHeld() => _held.Wait();

    // The machine's own request that changes its sound, such as apple2/sound, or null.
    private string? SoundRequest() => _target.Requests.Keys.FirstOrDefault(key => key.EndsWith("/sound", StringComparison.Ordinal));

    // Takes the gate for the window, telling the run thread to let it in.
    private Lock.Scope Gate()
    {
        Interlocked.Increment(ref _waiting);
        Lock.Scope scope = _gate.EnterScope();
        Interlocked.Decrement(ref _waiting);
        return scope;
    }

    private void Run()
    {
        long paceTime = 0;
        ulong paceCycles = 0;
        while (!_stopping)
        {
            bool ahead;
            lock (_gate)
            {
                if (_paceAgain)
                {
                    paceTime = Stopwatch.GetTimestamp();
                    paceCycles = _target.CycleCount;
                    _paceAgain = false;
                }

                long slice = Stopwatch.GetTimestamp();
                double speed = _speed;

                // While a drive is busy with fast drives on, the machine runs as fast as it can, and its pacing
                // starts over from wherever it is once the drive is done, rather than waiting for the clock.
                bool accelerated = speed != 0 && _target.Accelerated;
                if (accelerated)
                {
                    paceTime = slice;
                    paceCycles = _target.CycleCount;
                }
                else if (_accelerated)
                {
                    // Pacing starts from here: the last fast slice ran the machine well ahead of its start.
                    paceTime = slice;
                    paceCycles = _target.CycleCount;
                    _audio.Clear();
                }

                _accelerated = accelerated;
                // As fast as it can, the machine runs whole slices and never sleeps: a sleep of a millisecond lasts
                // as long as 15.6 at Windows' default timer resolution, which held it to a fraction of its speed.
                ulong due = speed == 0 || accelerated
                    ? ulong.MaxValue
                    : paceCycles + (ulong)(Stopwatch.GetElapsedTime(paceTime).TotalSeconds * _target.ClockHertz * speed);

                // Too far behind, as after the window was dragged: keep time from here rather than racing to catch up.
                if (speed != 0 && !accelerated && due > _target.CycleCount + (ulong)(_target.ClockHertz * speed * MaximumLagSeconds))
                {
                    paceTime = slice;
                    paceCycles = _target.CycleCount;
                    due = paceCycles;
                }

                ulong holdAt = Volatile.Read(ref _holdAt);
                due = Math.Min(due, holdAt);

                // With no debugger attached, the machine runs without the debugger's tracking, in batches between
                // looks at the clock.
                try
                {
                    while (_stopped is null
                        && _target.CycleCount < due
                        && Stopwatch.GetElapsedTime(slice).TotalMilliseconds < SliceMilliseconds)
                    {
                        _target.RunCycles((int)Math.Min(BatchCycles, due - _target.CycleCount));
                    }
                }
                catch (InvalidOperationException exception)
                {
                    // The CPU stopped, as a jammed 6502 does: the machine waits for a reset rather than ending the app.
                    _stopped = exception.Message;
                }

                ahead = _stopped is not null || _target.CycleCount >= due;
                if (_frameWanted)
                {
                    _frameWanted = false;
                    Publish();
                }

                // Queued under the gate, so that a change of speed, which clears the sound under it, never finds a
                // batch from the old speed queued after its clear.
                JsonObject? audio = _target.TakeAudio();
                if (audio is not null && SoundOn && speed == 1 && !accelerated && _stopped is null)
                {
                    _audio.Queue(audio);
                }

                Volatile.Write(ref _publishedCycles, _target.CycleCount);

                // Held once the count it stops at is published, so the waiter reads it.
                if (_target.CycleCount >= holdAt) { _held.Set(); }
                Measure();
            }

            while (Volatile.Read(ref _waiting) != 0) { Thread.Yield(); }
            if (ahead) { Thread.Sleep(1); }
        }
    }

    // Renders the video into the frame the window takes.
    private void Publish()
    {
        ReadOnlySpan<byte> pixels = _target.RenderVideo();
        JsonObject state = _target.DisplayState(running: true);
        int width = state["video"]?["width"]?.GetValue<int>() ?? 0;
        int height = state["video"]?["height"]?.GetValue<int>() ?? 0;
        if (width <= 0 || height <= 0 || pixels.Length < width * height * 4) { return; }

        lock (_frameLock)
        {
            if (_frame.Length != width * height * 4) { _frame = new byte[width * height * 4]; }
            pixels[..(width * height * 4)].CopyTo(_frame);
            _frameWidth = width;
            _frameHeight = height;
            _frameNumber++;
        }
    }

    private void Measure()
    {
        TimeSpan elapsed = Stopwatch.GetElapsedTime(_measureStart);
        if (elapsed.TotalSeconds < 1) { return; }
        MeasuredHertz = (_target.CycleCount - _measureCycles) / elapsed.TotalSeconds;
        _measureStart = Stopwatch.GetTimestamp();
        _measureCycles = _target.CycleCount;
    }

    /// <inheritdoc/>
    protected override void Dispose(bool disposing)
    {
        if (!disposing) { return; }
        _stopping = true;
        if (_thread.IsAlive) { _thread.Join(); }
        _audio.Dispose();
        _held.Dispose();
        (_target as IDisposable)?.Dispose();
    }
}