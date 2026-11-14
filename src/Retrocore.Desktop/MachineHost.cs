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

    private readonly IDebugTarget _target;
    private readonly Lock _gate = new();
    private readonly Thread _thread;
    private readonly SdlAudio _audio = new();
    private volatile bool _stopping;
    private volatile bool _frameWanted = true;
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
            lock (_gate)
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
            lock (_gate)
            {
                _speed = value;
                _paceAgain = true;
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
        get => _audio.Volume;
        set => _audio.Volume = value;
    }

    /// <summary>
    ///  Gets the machine's cycles a second over the last second.
    /// </summary>
    internal double MeasuredHertz { get; private set; }

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
        get { lock (_gate) { return _target.Screens; } }
    }

    /// <summary>
    ///  Gets or sets the monitor the video is shown on.
    /// </summary>
    internal string Screen
    {
        get { lock (_gate) { return _target.Screen; } }
        set
        {
            lock (_gate) { _target.Screen = value; }
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
        lock (_gate) { _target.Key(code); }
    }

    /// <summary>
    ///  Presses the machine's reset.
    /// </summary>
    internal void Reset()
    {
        lock (_gate) { _target.Reset(); }
    }

    /// <summary>
    ///  Gets the machine's installed hardware, in its documented order.
    /// </summary>
    /// <returns>The rows.</returns>
    internal IReadOnlyList<HardwareRow> Hardware()
    {
        lock (_gate) { return _target.Hardware(); }
    }

    /// <summary>
    ///  Gets each device with media and what it is doing.
    /// </summary>
    /// <returns>The devices' names, media, kind, lock and activity.</returns>
    internal List<DriveRow> Devices()
    {
        lock (_gate)
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
        lock (_gate)
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

    private void Run()
    {
        long paceTime = 0;
        ulong paceCycles = 0;
        while (!_stopping)
        {
            bool ahead;
            System.Text.Json.Nodes.JsonObject? audio;
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
                ulong due = speed == 0
                    ? _target.CycleCount + (ulong)(_target.ClockHertz / 250)
                    : paceCycles + (ulong)(Stopwatch.GetElapsedTime(paceTime).TotalSeconds * _target.ClockHertz * speed);

                // Too far behind, as after the window was dragged: keep time from here rather than racing to catch up.
                if (speed != 0 && due > _target.CycleCount + (ulong)(_target.ClockHertz * speed * MaximumLagSeconds))
                {
                    paceTime = slice;
                    paceCycles = _target.CycleCount;
                    due = paceCycles;
                }

                for (int count = 0; _target.CycleCount < due; count++)
                {
                    if ((count & 255) == 0 && Stopwatch.GetElapsedTime(slice).TotalMilliseconds >= SliceMilliseconds)
                    {
                        break;
                    }

                    _target.StepCycle();
                }

                ahead = _target.CycleCount >= due;
                if (_frameWanted)
                {
                    _frameWanted = false;
                    Publish();
                }

                audio = _target.TakeAudio();
                Measure();
            }

            if (audio is not null && SoundOn && _speed == 1) { _audio.Queue(audio); }
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
        (_target as IDisposable)?.Dispose();
    }
}