// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Basic;
using Retrocore.Debug;
using Retrocore.Machines.Devices;
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

    // Pasted keys waiting their turn, and the cycle the next one goes in at.
    private readonly Queue<int> _typing = new();
    private ulong _typingDue;

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
    /// <param name="saved">
    ///  The saved machine it will be restored to, or null: slot 7's image comes from the launch, so one a Save As moved
    ///  builds the machine, while <see cref="Configuration"/> stays the launch's own, the base the saved changes are on.
    /// </param>
    internal MachineHost(JsonObject configuration, JsonObject? saved = null)
    {
        Configuration = configuration;
        _target = OffMachine.Build(LaunchMedia.WithSaved(configuration, saved));
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
    internal string KeyMapName => MachineCatalog.Kind(Configuration["machine"]?.GetValue<string>() ?? "apple2");

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
        Apple2DebugTarget or Apple3DebugTarget or Trs80Model2DebugTarget or KayproDebugTarget => "disk",
        Apple1DebugTarget
            or CocoDebugTarget
            or PetDebugTarget
            or Trs80DebugTarget
            or Trs80Model3DebugTarget
            or AltairDebugTarget
            or BbcDebugTarget
            or AtariDebugTarget => "tape",
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
                    KayproDebugTarget kaypro => kaypro.FastDisk,
                    Apple1DebugTarget apple1 => apple1.FastCassette,
                    CocoDebugTarget coco => coco.FastCassette,
                    PetDebugTarget pet => pet.FastCassette,
                    Trs80DebugTarget model1 => model1.FastCassette,
                    Trs80Model3DebugTarget model3 => model3.FastCassette,
                    AltairDebugTarget altair => altair.FastCassette,
                    BbcDebugTarget bbc => bbc.FastCassette,
                    AtariDebugTarget atari => atari.FastCassette,
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
                    case KayproDebugTarget kaypro:
                        kaypro.FastDisk = value;
                        break;
                    case Apple1DebugTarget apple1:
                        apple1.FastCassette = value;
                        break;
                    case CocoDebugTarget coco:
                        coco.FastCassette = value;
                        break;
                    case PetDebugTarget pet:
                        pet.FastCassette = value;
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
                    case BbcDebugTarget bbc:
                        bbc.FastCassette = value;
                        break;
                    case AtariDebugTarget atari:
                        atari.FastCassette = value;
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
    ///  Samples the cycle count and host timestamp together while the machine cannot advance.
    /// </summary>
    /// <returns>The machine cycles and matching stopwatch timestamp.</returns>
    internal (ulong Cycles, long Timestamp) Sample()
    {
        using (Gate()) { return (_target.CycleCount, Stopwatch.GetTimestamp()); }
    }

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
    internal void Start()
    {
        if (_thread.ThreadState.HasFlag(System.Threading.ThreadState.Unstarted)) { _thread.Start(); }
    }

    /// <summary>
    ///  Holds the machine still where it is, as it is while the person is asked about its changed disks before
    ///  something sets it up again, so it cannot change a disk after its question.
    /// </summary>
    internal void Pause() => HoldAt(CycleCount);

    /// <summary>
    ///  Lets the machine run on after <see cref="Pause"/>.
    /// </summary>
    internal void Resume() => HoldAt(ulong.MaxValue);

    /// <summary>
    ///  Gets whether the machine has been started; until then it is built and off, as the extension's off machine is.
    /// </summary>
    internal bool Running => !_thread.ThreadState.HasFlag(System.Threading.ThreadState.Unstarted);

    /// <summary>
    ///  Types a key on the machine's keyboard. A key pressed while a paste is still typing waits its turn behind it,
    ///  but a key that interrupts goes now and drops the rest of the paste, as the debug host has it: CONTROL-C, the
    ///  Model II's BREAK, and the BREAK of the Model I and Model III.
    /// </summary>
    /// <param name="code">The ASCII code, 0-127, or a Kaypro II arrow key's, $F1-$F4.</param>
    internal void Key(int code)
    {
        using (Gate())
        {
            if (code == 3 || (code == 1 && KeyMapName is "trs80-model1" or "trs80-model3"))
            {
                _typing.Clear();
            }
            else if (_typing.Count != 0)
            {
                _typing.Enqueue(code);
                return;
            }

            _target.Key(code);
        }
    }

    /// <summary>
    ///  Types text, as pasted, through the keyboard: line endings are RETURN, and characters with no key are left out.
    ///  The keys wait here and go as the machine reaches each one's time, as the debug host's paste does, so a key
    ///  that interrupts can drop the rest. A machine with no typing pace of its own, whose keyboard keeps its own
    ///  queue, takes them at a steady typist's pace.
    /// </summary>
    /// <param name="text">The text.</param>
    /// <returns>The keys typed and the characters left out.</returns>
    internal (int Typed, int Skipped) Type(string text)
    {
        List<int> codes = TypedText.Codes(text, out int skipped, _target is BbcDebugTarget ? DebugSession.BbcPound : null);
        using (Gate())
        {
            foreach (int code in codes) { _typing.Enqueue(code); }
        }

        return (codes.Count, skipped);
    }

    /// <summary>
    ///  Gets the model the machine's display names, such as <c>Apple II Plus</c>, or null.
    /// </summary>
    internal string? Model
    {
        get
        {
            using (Gate())
            {
                return _target.DisplayState(running: Running)["model"] is JsonValue model && model.TryGetValue(out string? text) ? text : null;
            }
        }
    }

    /// <summary>
    ///  Gets the slot of the Apple II's mouse card, or 0 without one.
    /// </summary>
    internal int MouseSlot
    {
        get
        {
            using (Gate())
            {
                return _target.DisplayState(running: Running)["mouse"] is JsonValue slot && slot.TryGetValue(out int number) ? number : 0;
            }
        }
    }

    /// <summary>
    ///  Gets whether the machine has the Apple keys or game-port buttons the display panel latches.
    /// </summary>
    internal bool HasButtons => ButtonRequest() is not null;

    /// <summary>
    ///  Holds or lets go of an Apple key or game-port button.
    /// </summary>
    /// <param name="button">0 for Open Apple or button 0, 1 for Closed (or Solid) Apple or button 1.</param>
    /// <param name="pressed">Whether it is down.</param>
    internal void Button(int button, bool pressed)
    {
        using (Gate())
        {
            if (ButtonRequest() is { } request)
            {
                _target.Requests[request](new JsonObject { ["button"] = button, ["pressed"] = pressed });
            }
        }
    }

    /// <summary>
    ///  Puts the mouse card's mouse at a place within the bounds the program set, and sets its button when given.
    /// </summary>
    /// <param name="across">
    ///  How far across the bounds, 0 to 1, or null with <paramref name="down"/> to leave it.
    /// </param>
    /// <param name="down">How far down them, 0 to 1, or null with <paramref name="across"/> to leave it.</param>
    /// <param name="pressed">The button, or null to leave it.</param>
    /// <returns>Whether the program has the mouse on.</returns>
    internal bool PlaceMouse(double? across, double? down, bool? pressed = null)
    {
        using (Gate())
        {
            if (!_target.Requests.TryGetValue("apple2/mouse", out Func<JsonObject, JsonObject>? mouse))
            {
                return false;
            }

            JsonObject args = [];
            if (across is { } x && down is { } y)
            {
                args["x"] = x;
                args["y"] = y;
            }

            if (pressed is { } button) { args["pressed"] = button; }
            return mouse(args)["on"] is JsonValue on && on.TryGetValue(out bool isOn) && isOn;
        }
    }

    /// <summary>
    ///  Gets whether the machine's terminal has a clear screen key, as the Apple-1's and the Altair's do.
    /// </summary>
    internal bool CanClearScreen => ClearRequest() is not null;

    /// <summary>
    ///  Clears the screen, as the Apple-1's CLEAR SCREEN or the Altair terminal's CLEAR does.
    /// </summary>
    internal void ClearScreen()
    {
        using (Gate())
        {
            if (ClearRequest() is { } request) { _target.Requests[request]([]); }
        }

        _frameWanted = true;
    }

    /// <summary>
    ///  Gets each device as the Drives section shows it.
    /// </summary>
    /// <returns>The devices, in the machine's order.</returns>
    internal IReadOnlyList<DeviceState> DeviceStates()
    {
        using (Gate()) { return [.. _target.Devices.Select(DeviceState.Of)]; }
    }

    /// <summary>
    ///  Changes a device's media, as <c>retro/device</c> does: inserts, records, ejects, protects or saves.
    /// </summary>
    /// <param name="id">The device's id.</param>
    /// <param name="action">The action, such as <c>insert</c>.</param>
    /// <param name="args">Its arguments, such as the image's <c>path</c>.</param>
    /// <returns>
    ///  Media's answer, as the debug adapter gives it, such as <c>changed</c> for a changed disk that would leave its
    ///  drive; null when the machine simply acted.
    /// </returns>
    /// <exception cref="ArgumentException">
    ///  There is no such device, or the action or its arguments are wrong.
    /// </exception>
    internal JsonObject? DeviceAction(string id, string action, JsonObject args)
    {
        using (Gate())
        {
            IDevice device = _target.Devices.FirstOrDefault(device => device.Id == id)
                ?? throw new ArgumentException($"There is no device '{id}'.");

            // The host saves disks and holds back a changed disk that would leave its drive, as the debug adapter does.
            JsonObject? answer = MediaActions.Device(device, action, args, (what, with) => _target.DeviceAction(device, what, with));
            if (answer is null) { _target.DeviceAction(device, action, args); }
            return answer;
        }
    }

    /// <summary>
    ///  Changes the installed hardware, as <c>retro/hardware</c> does: adds or removes a card, or sets a switch.
    /// </summary>
    /// <param name="id">The hardware row's id, such as <c>slot5</c>.</param>
    /// <param name="action">The action, such as <c>addDiskII</c>.</param>
    /// <param name="args">Its arguments.</param>
    /// <returns>
    ///  Media's answer, such as <c>changed</c> for a card with a changed disk; null when the machine acted.
    /// </returns>
    /// <exception cref="ArgumentException">The action or its arguments are wrong.</exception>
    internal JsonObject? HardwareAction(string id, string action, JsonObject args)
    {
        using (Gate())
        {
            string[]? ids = _target.Hardware().FirstOrDefault(row => row.Id == id)?.Devices;
            if (MediaActions.Hardware(ids, _target.Devices, action, args) is { } held) { return held; }
            _target.HardwareAction(id, action, args);
        }

        _frameWanted = true;
        return null;
    }

    /// <summary>
    ///  Gets what a drive called a disk the machine ejected from it, which the host keeps until it is saved or let go.
    /// </summary>
    /// <param name="id">The drive's id.</param>
    /// <param name="ejected">The ejected disk's id.</param>
    /// <returns>Its label, such as its image's path, or null when it is no longer kept.</returns>
    internal string? EjectedLabel(string id, string ejected)
    {
        using (Gate())
        {
            return _target.Devices.FirstOrDefault(device => device.Id == id) is { } device
                ? MediaActions.Ejected(device).FirstOrDefault(kept => kept.Id == ejected)?.Label
                : null;
        }
    }

    /// <summary>
    ///  Gets the changed disks the machine ejected from its drives, which the host keeps until they are saved or let go.
    /// </summary>
    /// <returns>Each one's drive, its id among the drive's ejected disks, and its label.</returns>
    internal IReadOnlyList<(DeviceState Drive, string Ejected, string Label)> UnsavedEjected()
    {
        using (Gate())
        {
            return [.. _target.Devices.SelectMany(device => MediaActions.Ejected(device)
                .Where(kept => kept.Medium.IsDirty)
                .Select(kept => (DeviceState.Of(device), kept.Id, kept.Label)))];
        }
    }

    /// <summary>
    ///  Captures the machine's cards and media, as a saved machine keeps them.
    /// </summary>
    /// <returns>The saved machine.</returns>
    internal JsonObject Capture()
    {
        using (Gate()) { return MachineConfiguration.Capture(_target); }
    }

    /// <summary>
    ///  Restores cards and media a saved machine kept.
    /// </summary>
    /// <param name="saved">The saved machine.</param>
    /// <returns>What could not be restored.</returns>
    internal List<string> Restore(JsonObject saved)
    {
        using (Gate()) { return MachineConfiguration.Restore(_target, saved); }
    }

    /// <summary>
    ///  Writes the machine's tape recordings, as a debug session does when it ends.
    /// </summary>
    /// <exception cref="IOException">A recording could not be written.</exception>
    /// <exception cref="UnauthorizedAccessException">A recording's path cannot be written.</exception>
    internal void SaveRecordings()
    {
        using (Gate()) { (_target as IRecordingTarget)?.SaveRecordings(); }
    }

    /// <summary>
    ///  Gets the BASIC program in the machine's memory, as the Machine section's BASIC program row summarises it.
    /// </summary>
    /// <returns>The dialect's name and the program's lines, or null for a machine with no BASIC.</returns>
    internal (string DisplayName, int Lines)? Basic()
    {
        using (Gate())
        {
            if (_target.Basic is not { } dialect) { return null; }
            try
            {
                string text = BasicProgram.Read(dialect, new TargetBasicMemory(_target)).ToText();
                return (dialect.DisplayName, text.Split('\n').Count(line => line.Trim().Length != 0));
            }
            catch (InvalidDataException)
            {
                return (dialect.DisplayName, 0);
            }
        }
    }

    /// <summary>
    ///  Presses the machine's reset.
    /// </summary>
    internal void Reset() => Reset(shift: false);

    /// <summary>
    ///  Presses the machine's reset, or the BBC Micro's SHIFT-BREAK.
    /// </summary>
    /// <param name="shift">Whether SHIFT is held, which on the BBC Micro boots its disk or tape.</param>
    internal void Reset(bool shift)
    {
        using (Gate())
        {
            // The BBC Micro's SHIFT-BREAK boots its disk or tape.
            if (shift && _target is BbcDebugTarget bbc) { bbc.ShiftReset(); }
            else { _target.Reset(); }
            _typing.Clear();
            _stopped = null;
            _paceAgain = true;
        }
    }

    /// <summary>
    ///  Gets why the machine's CPU stopped, such as on an opcode that jams it, or null while it runs. The machine
    ///  waits, with its picture as it was, until <see cref="Reset()"/>.
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
        // Under the gate, which the run thread holds while it reads the limit and sets the event, so a slice under
        // the old limit cannot set the event after this reset.
        using (Gate())
        {
            _held.Reset();
            _holdAt = cycle;
        }
    }

    /// <summary>
    ///  Waits for the run thread to reach the cycle <see cref="HoldAt"/> set.
    /// </summary>
    internal void WaitHeld() => _held.Wait();

    // The machine's own request that changes its sound, such as apple2/sound, or null.
    private string? SoundRequest() => _target.Requests.Keys.FirstOrDefault(key => key.EndsWith("/sound", StringComparison.Ordinal));

    // The machine's request for its Apple keys or game-port buttons, such as apple2/button, or null.
    private string? ButtonRequest() => _target.Requests.Keys.FirstOrDefault(key => key.EndsWith("/button", StringComparison.Ordinal));

    // The machine's request that clears its terminal's screen, such as apple1/clearScreen, or null.
    private string? ClearRequest() => _target.Requests.Keys.FirstOrDefault(key => key.EndsWith("/clearScreen", StringComparison.Ordinal));

    // Types the next pasted key once its time has come, and sets the time of the one after: longer after a RETURN.
    private void TypeNext()
    {
        if (_target.CycleCount < _typingDue) { return; }
        int next = _typing.Dequeue();
        _target.Key(next);

        // Without a pace of its own, 30 keys a second and a quarter second for each line, which any of their
        // keyboard queues keeps up with.
        ulong clock = (ulong)Math.Max(1, _target.ClockHertz);
        (ulong key, ulong line) = _target.TypingPace is { } pace ? (pace.Key, pace.Line) : (clock / 30, clock / 4);
        _typingDue = _target.CycleCount + (next == '\r' ? line : key);
    }

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
        int paceClock = 0;
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

                // A machine that changes its own clock, as the Model 4 does between 2 and 4 MHz, is paced from the
                // change at its new clock: the old clock's time is not counted again at the new one.
                int clock = _target.ClockHertz;
                if (clock != paceClock)
                {
                    paceTime = slice;
                    paceCycles = _target.CycleCount;
                    paceClock = clock;
                }

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
                    : paceCycles + (ulong)(Stopwatch.GetElapsedTime(paceTime).TotalSeconds * clock * speed);

                // Too far behind, as after the window was dragged, or too far ahead, as nothing else should leave it:
                // keep time from here rather than racing to catch up or waiting for the clock.
                ulong lag = (ulong)(clock * speed * MaximumLagSeconds);
                if (speed != 0 && !accelerated && (due > _target.CycleCount + lag || due + lag < _target.CycleCount))
                {
                    paceTime = slice;
                    paceCycles = _target.CycleCount;
                    due = paceCycles;
                }

                ulong holdAt = _holdAt;
                due = Math.Min(due, holdAt);

                // With no debugger attached, the machine runs without the debugger's tracking, in batches between
                // looks at the clock.
                try
                {
                    while (_stopped is null
                        && _target.CycleCount < due
                        && Stopwatch.GetElapsedTime(slice).TotalMilliseconds < SliceMilliseconds)
                    {
                        // Pasted keys go in as the machine reaches each one's time.
                        if (_typing.Count != 0) { TypeNext(); }
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