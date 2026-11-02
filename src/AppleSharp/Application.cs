// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Input;
using Retrocore.Machines.Apple2;
using Retrocore.Machines.Devices;
using SDL3;
using System.Collections.Concurrent;
using System.Diagnostics;
using System.Runtime.InteropServices;
using Touki;

namespace AppleSharp;

/// <summary>
///  A single-threaded SDL3 emulator host. Dialog callbacks only enqueue results for the UI thread.
/// </summary>
internal sealed class Application : DisposableBase
{
    private static readonly ConcurrentQueue<(Command Command, string? Path, string? Error)> s_dialogResults = new();

    // SDL calls back through this delegate after the dialog closes, so it lives as long as the process.
    private static readonly SDL.DialogFileCallback s_dialogCompleted = DialogCompleted;
    private static readonly string[] s_labels =
    [
        "F1 ROMs", "F2 Mount", "F3 Eject", "F4 Pause", "F5 Reset", "F6 Boot", "F7 Model",
        "F8 Writes", "F11 Full", "F9 P5", "F10 P6", "D2 Mount", "F12 Mute"
    ];
    private readonly AppOptions _options;
    private readonly byte[] _pixels = new byte[Apple2Video.Width * Apple2Video.Height * 4];
    private readonly List<ControllerState> _controllerStates = [];
    private AppSettings _settings;
    private FrameClock _clock = new(Stopwatch.Frequency, Stopwatch.GetTimestamp());
    private Apple2Machine? _machine;
    private FileBlockDevice? _disk;
    private FloppyMount? _floppy1;
    private FloppyMount? _floppy2;
    private SdlAudioSink? _audio;
    private Controllers? _controllers;
    private IntPtr _window;
    private IntPtr _renderer;
    private IntPtr _texture;
    private bool _initialized;
    private bool _running = true;
    private bool _paused;
    private bool _writeConfirmation;
    private bool _dialogOpen;
    private bool _pauseBeforeDialog;
    private string _message = "Choose your ROM folder with F1. Apple ROMs are not bundled.";
    private int _frames;
    private bool _smokeKeyAccepted;
    private ulong _smokePausedCycles;
    private IntPtr _smokeText;

    /// <summary>
    ///  Creates a host using saved settings and transient command-line overrides.
    /// </summary>
    /// <param name="options">The command-line options.</param>
    /// <param name="settings">The saved configuration.</param>
    internal Application(AppOptions options, AppSettings settings)
    {
        _options = options;
        _settings = settings with
        {
            RomDirectory = options.RomDirectory ?? settings.RomDirectory ?? Environment.GetEnvironmentVariable("RETROCORE_IIE_ROMS"),
            Model = options.Model ?? settings.Model,
            DiskPath = options.DiskPath ?? settings.DiskPath,
            Writable = options.Writable ?? settings.Writable,
            Floppy1Path = options.Floppy1Path ?? settings.Floppy1Path,
            Floppy2Path = options.Floppy2Path ?? settings.Floppy2Path,
            DiskBootRom = options.DiskBootRom ?? settings.DiskBootRom,
            DiskSequencerRom = options.DiskSequencerRom ?? settings.DiskSequencerRom,
            SequencerLayout = options.SequencerLayout ?? settings.SequencerLayout,
            Muted = options.Muted ?? settings.Muted
        };

        if (options.Floppy1Path is not null && options.DiskPath is null)
        {
            _settings = _settings with { DiskPath = null };
        }

        if (_settings.DiskPath is { } disk && !Path.GetExtension(disk).Equals(".po", StringComparison.OrdinalIgnoreCase))
        {
            _settings = _settings with { DiskPath = null, Floppy1Path = disk };
        }
    }

    /// <summary>
    ///  Owns the native event/render loop until the window closes or bounded acceptance completes.
    /// </summary>
    internal void Run()
    {
        Check(SDL.Init(SDL.InitFlags.Video | SDL.InitFlags.Audio | SDL.InitFlags.Gamepad));
        _initialized = true;
        _window = SDL.CreateWindow(
            "AppleSharp",
            960,
            800,
            SDL.WindowFlags.Resizable | SDL.WindowFlags.HighPixelDensity);

        if (_window == IntPtr.Zero) { throw new InvalidOperationException(SDL.GetError()); }
        Check(SDL.SetWindowMinimumSize(_window, 600, 400));
        _renderer = SDL.CreateRenderer(_window, name: null);
        if (_renderer == IntPtr.Zero) { throw new InvalidOperationException(SDL.GetError()); }
        Check(SDL.SetRenderVSync(_renderer, vsync: 1));

        // ABGR8888 is R, G, B, A in memory on a little-endian machine: the video's RGBA bytes.
        _texture = SDL.CreateTexture(
            _renderer,
            SDL.PixelFormat.ABGR8888,
            SDL.TextureAccess.Streaming,
            Apple2Video.Width,
            Apple2Video.Height);

        if (_texture == IntPtr.Zero) { throw new InvalidOperationException(SDL.GetError()); }
        Check(SDL.SetTextureScaleMode(_texture, SDL.ScaleMode.Nearest));
        Check(SDL.StartTextInput(_window));
        Check(SDL.SetWindowFullscreen(_window, _settings.Fullscreen));
        _controllers = new();
        if (!_settings.Muted) { _audio = new(sampleRate: 48000); }
        if (_options.SmokeTest || _options.RomDirectory is not null || _options.DiskPath is not null)
        {
            Configure(_settings, save: false);
            if (_machine is null) { throw new ArgumentException("A ROM directory is required for this launch."); }
        }
        else if (_settings.RomDirectory is not null)
        {
            UserAction(() => Configure(_settings, save: false));
        }

        _clock = new(Stopwatch.Frequency, Stopwatch.GetTimestamp());
        while (_running)
        {
            while (SDL.PollEvent(out SDL.Event input)) { Handle(input); }
            while (s_dialogResults.TryDequeue(out var result))
            {
                _dialogOpen = false;
                _paused = _pauseBeforeDialog;
                if (result.Error is { } error) { Failure(new IOException(error)); }
                else if (result.Path is { } path) { UserAction(() => SelectedMedia(result.Command, path)); }
            }

            // The controllers' sticks and buttons drive the game port, read once a frame.
            _controllers.Read(_controllerStates);
            _machine?.Bus.GamePort.Apply(_controllerStates);

            ulong cycles = _clock.Take(Stopwatch.GetTimestamp(), _machine is not null && !_paused);
            if (_machine is not null && cycles != 0) { UserAction(() => _machine.Run(cycles)); }
            if (_machine is not null)
            {
                if (!_machine.Bus.DiskII.State(drive: 1).Motor) { UserAction(() => _floppy1?.Save()); }
                if (!_machine.Bus.DiskII.State(drive: 2).Motor) { UserAction(() => _floppy2?.Save()); }
            }

            Draw();
            _frames++;
            if (_options.SmokeTest) { SmokeStep(); }
        }
    }

    private void Configure(AppSettings next, bool save)
    {
        Apple2Roms? roms = next.RomDirectory is null ? null : Apple2Roms.LoadFromDirectory(next.Model, next.RomDirectory);
        DiskIIFirmware? firmware = next.DiskBootRom is { } p5 && next.DiskSequencerRom is { } p6
            ? new(File.ReadAllBytes(p5), File.ReadAllBytes(p6), next.SequencerLayout) : null;

        if ((next.Floppy1Path is not null || next.Floppy2Path is not null) && firmware is null)
        {
            throw new InvalidOperationException(
                "Native floppy boot requires your Disk II P5 and P6 ROM files (F9 and F10, or --disk-ii-rom/--sequencer-rom).");
        }

        _machine?.Bus.Audio.Flush();
        _audio?.Clear();
        _floppy1?.Save();
        _floppy2?.Save();
        _machine = null;
        _disk?.Dispose();
        _disk = null;
        _floppy1?.Dispose();
        _floppy2?.Dispose();
        _floppy1 = _floppy2 = null;
        if (roms is not null)
        {
            if (next.DiskPath is { } path) { _disk = new(path, next.Writable); }
            _machine = new(next.Model, roms, _disk);

            // The emulator plays the Mockingboard, so it is always in slot 4.
            _machine.Bus.InstallMockingboard();
            if (firmware is not null) { _machine.Bus.DiskII.SetFirmware(firmware); }
            if (next.Floppy1Path is { } first)
            {
                _floppy1 = new(first, next.Writable);
                _machine.Bus.DiskII.Mount(drive: 1, _floppy1.Disk);
            }

            if (next.Floppy2Path is { } second)
            {
                _floppy2 = new(second, next.Writable);
                _machine.Bus.DiskII.Mount(drive: 2, _floppy2.Disk);
            }

            _machine.Bus.Audio.Sink = _audio;
        }

        _settings = next;
        _message = next.DiskPath is { } disk ? Path.GetFileName(disk)
            : next.Floppy1Path is { } floppy ? Path.GetFileName(floppy) : "F2 mounts .po block or .woz/.dsk floppy media.";

        _clock = new(Stopwatch.Frequency, Stopwatch.GetTimestamp());
        if (save) { next.Save(_options.SettingsPath); }
    }

    private void Handle(in SDL.Event input)
    {
        if (_controllers?.Handle(input) == true)
        {
            _message = _controllers.Count == 0 ? "No controller." : "Controllers: " + string.Join(", ", _controllers.Names);
        }

        switch ((SDL.EventType)input.Type)
        {
            case SDL.EventType.Quit: _running = false;
                break;
            case SDL.EventType.TextInput:
                string text = Marshal.PtrToStringUTF8(input.Text.Text)
                    ?? throw new InvalidOperationException("SDL returned a null text-input payload.");

                if (text.Any(character => character > 127))
                {
                    _message = "The emulated keyboard accepts seven-bit ASCII only.";
                    break;
                }

                if (_machine is not null)
                {
                    foreach (char character in text) { _machine.Bus.QueueKey((byte)character); }
                    if (_options.SmokeTest && text == "c")
                    {
                        _smokeKeyAccepted = _machine.Bus.Peek(0xC000) == ('c' | 128);
                    }
                }

                break;
            case SDL.EventType.KeyDown:
                HandleKey(input.Key);
                break;
            case SDL.EventType.MouseButtonDown when input.Button.Button == 1:
                Check(SDL.GetWindowSize(_window, out int width, out _));
                for (int index = 0; index < s_labels.Length; index++)
                {
                    SDL.FRect rect = Button(index, width);
                    if (input.Button.X >= rect.X
                        && input.Button.X < rect.X + rect.W
                        && input.Button.Y >= rect.Y
                        && input.Button.Y < rect.Y + rect.H)
                    {
                        UserAction(() => Invoke((Command)index));
                        break;
                    }
                }

                break;
        }
    }

    private void HandleKey(SDL.KeyboardEvent input)
    {
        Command? command = input.Key switch
        {
            SDL.Keycode.F1 => Command.Roms, SDL.Keycode.F2 => Command.Mount,
            SDL.Keycode.F3 => Command.Eject, SDL.Keycode.F4 => Command.Pause,
            SDL.Keycode.F5 => Command.Reset, SDL.Keycode.F6 => Command.Boot,
            SDL.Keycode.F7 => Command.Model, SDL.Keycode.F8 => Command.Writable,
            SDL.Keycode.F9 => Command.DiskBootRom, SDL.Keycode.F10 => Command.DiskSequencerRom,
            SDL.Keycode.F11 => Command.Fullscreen, SDL.Keycode.F12 => Command.Mute, _ => null
        };

        if (input.Key == SDL.Keycode.F2 && (input.Mod & SDL.Keymod.Shift) != 0)
        {
            command = Command.Floppy2;
        }

        if (command is { } action)
        {
            if (!input.Repeat) { UserAction(() => Invoke(action)); }
            return;
        }

        int code = input.Key switch
        {
            SDL.Keycode.Return => 13, SDL.Keycode.Backspace or SDL.Keycode.Left => 8,
            SDL.Keycode.Right => 21, SDL.Keycode.Up => 11, SDL.Keycode.Down => 10,
            SDL.Keycode.Escape => 27, SDL.Keycode.Tab => 9, _ => -1
        };

        uint key = (uint)input.Key;
        if ((input.Mod & SDL.Keymod.Ctrl) != 0 && key is >= 97 and <= 122) { code = (int)(key & 31); }
        if (code >= 0 && _machine is not null) { _machine.Bus.QueueKey((byte)code); }
    }

    private void Invoke(Command command)
    {
        if (_dialogOpen) { return; }
        if (command != Command.Writable) { _writeConfirmation = false; }
        switch (command)
        {
            case Command.Roms:
            case Command.Mount:
            case Command.Floppy2:
            case Command.DiskBootRom:
            case Command.DiskSequencerRom: OpenDialog(command);
            break;
            case Command.Eject:
                Configure(_settings with
                {
                    DiskPath = null, Floppy1Path = null, Floppy2Path = null
                }, save: true);

                break;
            case Command.Pause:
                _machine?.Bus.Audio.Flush();
                _audio?.Clear();
                _paused = !_paused;
                break;
            case Command.Reset:
                if (_machine is not null)
                {
                    _machine.Bus.Audio.Flush();
                    _audio?.Clear();
                    _machine.Bus.ResetDevices();
                    _machine.Bus.ResetSwitches();
                    _machine.Processor.Reset();
                }

                break;
            case Command.Boot: Configure(_settings, save: false);
                break;
            case Command.Model:
                Configure(_settings with
                {
                    Model = _settings.Model == Apple2Model.IIeEnhanced ? Apple2Model.IIe : Apple2Model.IIeEnhanced
                }, save: true);

                break;
            case Command.Writable:
                if (!_settings.Writable)
                {
                    _message = "Writable mounts change the .po file immediately. Click F8 again to confirm.";
                    if (_writeConfirmation)
                    {
                        Configure(_settings with { Writable = true }, save: true);
                        _writeConfirmation = false;
                    }
                    else
                    {
                        _writeConfirmation = true;
                    }
                }
                else
                {
                    Configure(_settings with { Writable = false }, save: true);
                }

                break;
            case Command.Fullscreen:
                Check(SDL.SetWindowFullscreen(_window, !_settings.Fullscreen));
                _settings = _settings with { Fullscreen = !_settings.Fullscreen };
                if (!_options.SmokeTest) { _settings.Save(_options.SettingsPath); }
                break;
            case Command.Mute:
                _machine?.Bus.Audio.Flush();
                _machine?.Bus.Audio.Sink = null;
                _audio?.Dispose();
                _audio = null;
                if (_settings.Muted) { _audio = new(sampleRate: 48000); }
                _machine?.Bus.Audio.Sink = _audio;
                _settings = _settings with { Muted = !_settings.Muted };
                if (!_options.SmokeTest) { _settings.Save(_options.SettingsPath); }
                break;
        }
    }

    private void SelectedMedia(Command command, string path)
    {
        AppSettings next = command switch
        {
            Command.Roms => _settings with { RomDirectory = path },
            Command.DiskBootRom => _settings with { DiskBootRom = path },
            Command.DiskSequencerRom => _settings with { DiskSequencerRom = path },
            Command.Floppy2 => _settings with { Floppy2Path = path },
            Command.Mount when Path.GetExtension(path).Equals(".po", StringComparison.OrdinalIgnoreCase) =>
                _settings with { DiskPath = path, Floppy1Path = null },
            Command.Mount => _settings with { DiskPath = null, Floppy1Path = path },
            _ => throw new ArgumentOutOfRangeException(nameof(command))
        };

        Configure(next, save: true);
    }

    private void OpenDialog(Command command)
    {
        bool folder = command == Command.Roms;
        bool firmware = command is Command.DiskBootRom or Command.DiskSequencerRom;
        DialogRequest request = (folder, firmware) switch
        {
            (true, _) => new(command, label: null, pattern: null),
            (_, true) => new(command, "Disk II ROM", "bin;rom"),
            _ => new(command, "Apple II disk image", "po;woz;dsk;do")
        };

        _dialogOpen = true;
        _pauseBeforeDialog = _paused;
        _paused = true;

        // The properties form, because SDL reads the filters until the dialog closes and SDL3-CS's
        // ShowOpenFileDialog releases them as soon as it returns. The request keeps them until the callback.
        uint properties = SDL.CreateProperties();
        try
        {
            SDL.SetPointerProperty(properties, SDL.Props.FileDialogWindowPointer, _window);
            SDL.SetPointerProperty(properties, SDL.Props.FileDialogFiltersPointer, request.Filters);
            SDL.SetNumberProperty(properties, SDL.Props.FileDialogNFiltersNumber, request.FilterCount);
            SDL.ShowFileDialogWithProperties(
                folder ? SDL.FileDialogType.OpenFolder : SDL.FileDialogType.OpenFile,
                s_dialogCompleted,
                GCHandle.ToIntPtr(GCHandle.Alloc(request)),
                properties);
        }
        finally
        {
            SDL.DestroyProperties(properties);
        }
    }

    // SDL may call back on another thread, so the result only goes onto the queue the UI thread drains.
    private static void DialogCompleted(IntPtr userdata, IntPtr files, int filter)
    {
        GCHandle handle = GCHandle.FromIntPtr(userdata);
        object target = handle.Target ?? throw new InvalidOperationException("The dialog's request is gone.");
        handle.Free();
        using DialogRequest request = (DialogRequest)target;
        IntPtr first = files == IntPtr.Zero ? IntPtr.Zero : Marshal.ReadIntPtr(files);
        string? path = first == IntPtr.Zero ? null : Marshal.PtrToStringUTF8(first);
        string? error = files == IntPtr.Zero ? SDL.GetError() : null;
        s_dialogResults.Enqueue((request.Command, path, error));
    }

    private void Draw()
    {
        Check(SDL.GetWindowSize(_window, out int width, out int height));
        Check(SDL.GetRenderOutputSize(_renderer, out int outputWidth, out int outputHeight));
        if (width <= 0 || height <= 0 || outputWidth <= 0 || outputHeight <= 0)
        {
            SDL.Delay(ms: 10);
            return;
        }

        Check(SDL.SetRenderScale(_renderer, (float)outputWidth / width, (float)outputHeight / height));
        Check(SDL.SetRenderDrawColor(_renderer, r: 18, g: 20, b: 24, a: 255));
        Check(SDL.RenderClear(_renderer));
        if (_machine is not null)
        {
            _machine.Bus.Video.RenderScannedBitmap(_pixels);
            Check(SDL.UpdateTexture(_texture, IntPtr.Zero, _pixels.AsSpan(), Apple2Video.Width * 4));
            int toolbarHeight = Math.Max(72, ((s_labels.Length + Math.Max(5, width / 106) - 1) / Math.Max(5, width / 106)) * 30 + 12);
            SDL.FRect screen = WindowLayout.Screen(width, height, toolbarHeight, statusHeight: 80);
            Check(SDL.RenderTexture(_renderer, _texture, IntPtr.Zero, in screen));
        }

        for (int index = 0; index < s_labels.Length; index++)
        {
            SDL.FRect rect = Button(index, width);
            Check(SDL.SetRenderDrawColor(_renderer, r: 45, g: 51, b: 60, a: 255));
            Check(SDL.RenderFillRect(_renderer, in rect));
            Check(SDL.SetRenderDrawColor(_renderer, r: 230, g: 235, b: 240, a: 255));
            Text(rect.X + 5, rect.Y + 9, index == 3 && _paused ? "F4 Run" : s_labels[index]);
        }

        if (_machine is null)
        {
            Text(x: 32, y: 128, "AppleSharp - standalone Apple IIe");
            Text(x: 32, y: 152, "F1: select your CD, EF and video ROM folder.");
            Text(x: 32, y: 176, "F2: .po block disk or .woz/.dsk floppy; Shift+F2: drive two.");
            Text(x: 32, y: 200, "F9/F10: caller-supplied Disk II P5/P6 ROMs.");
        }

        string state = _dialogOpen ? "choosing media" : _machine is null ? "setup" : _paused ? "paused"
            : _machine.Processor.Status == Retrocore.Cpu.ProcessorExecutionStatus.Running ? "running" : _machine.Processor.Status.ToString();

        Text(
            x: 12,
            height - 68,
            $"{_settings.Model} IIe | {state} | {(_settings.Writable ? "WRITABLE" : "read-only")} | {(_settings.Muted ? "muted" : "sound")} | 1.0205 MHz");

        Text(x: 12, height - 52, _message);
        if (_machine is not null)
        {
            for (int drive = 1; drive <= 2; drive++)
            {
                DiskDriveState disk = _machine.Bus.DiskII.State(drive);
                Text(
                    x: 12,
                    height - 36 + (drive - 1) * 16,
                    $"D{drive}: track {disk.QuarterTrack / 4.0:0.00} | bit {disk.BitPosition}/{disk.BitCount} | motor {(disk.Motor ? "on" : "off")} | {(disk.Dirty ? "changed" : "saved")}");
            }
        }

        Check(SDL.RenderPresent(_renderer));
    }

    private static SDL.FRect Button(int index, int width)
    {
        int columns = Math.Max(5, width / 106);
        return new()
        {
            X = 6 + index % columns * 106,
            Y = 6 + index / columns * 30,
            W = 100,
            H = 26
        };
    }

    // SDL's debug font draws ASCII; the text is cut at 500 characters as before.
    private void Text(float x, float y, string text) =>
        Check(SDL.RenderDebugText(_renderer, x, y, text.Length > 500 ? text[..500] : text));

    private void UserAction(Action action)
    {
        try
        {
            action();
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or ArgumentException or InvalidOperationException or NotSupportedException)
        {
            if (_options.SmokeTest) { throw; }
            Failure(exception);
        }
    }

    private void Failure(Exception exception)
    {
        _paused = true;
        _message = "Error: " + exception.Message;
        Console.Error.WriteLine(exception);
        if (!SDL.ShowSimpleMessageBox(SDL.MessageBoxFlags.Error, "AppleSharp", exception.Message, _window))
        {
            Console.Error.WriteLine("SDL error dialog failed: " + SDL.GetError());
        }
    }

    private void SmokeStep()
    {
        Apple2Machine machine = _machine ?? throw new InvalidOperationException("Native acceptance requires a running machine.");
        if (_frames == 120)
        {
            if (_disk is not null && machine.Bus.MainMemory[0xBF00] != 0x4C)
            {
                throw new InvalidOperationException("Native AppleSharp did not boot ProDOS within 120 presented frames.");
            }

            // SDL copies the event but not its text, which must stay valid until the event is read.
            _smokeText = Marshal.StringToCoTaskMemUTF8("c");
            SDL.Event input = new()
            {
                Text = new() { Type = SDL.EventType.TextInput, Text = _smokeText }
            };

            Check(SDL.PushEvent(ref input));
        }
        else if (_frames == 121)
        {
            Marshal.FreeCoTaskMem(_smokeText);
            _smokeText = IntPtr.Zero;
            if (!_smokeKeyAccepted)
            {
                throw new InvalidOperationException("Native SDL text input did not reach the IIe keyboard.");
            }

            _paused = true;
            _smokePausedCycles = machine.Bus.CycleCount;
        }
        else if (_frames == 122)
        {
            if (machine.Bus.CycleCount != _smokePausedCycles)
            {
                throw new InvalidOperationException("Paused machine clocks advanced.");
            }

            _paused = false;
            Invoke(Command.Fullscreen);
            if ((SDL.GetWindowFlags(_window) & SDL.WindowFlags.Fullscreen) == 0)
            {
                throw new InvalidOperationException("Fullscreen did not activate.");
            }
        }
        else if (_frames == 123)
        {
            Invoke(Command.Fullscreen);
        }
        else if (_frames == 124)
        {
            Invoke(Command.Reset);
        }
        else if (_frames == 128)
        {
            _running = false;
        }
    }

    private static void Check(bool success)
    {
        if (!success) { throw new InvalidOperationException("SDL3: " + SDL.GetError()); }
    }

    /// <inheritdoc/>
    protected override void Dispose(bool disposing)
    {
        if (!disposing) { return; }
        _machine?.Bus.Audio.Flush();
        _floppy1?.Dispose();
        _floppy2?.Dispose();
        _disk?.Dispose();
        _audio?.Dispose();
        _controllers?.Dispose();
        if (_smokeText != IntPtr.Zero) { Marshal.FreeCoTaskMem(_smokeText); }
        if (_texture != IntPtr.Zero) { SDL.DestroyTexture(_texture); }
        if (_renderer != IntPtr.Zero) { SDL.DestroyRenderer(_renderer); }
        if (_window != IntPtr.Zero) { SDL.DestroyWindow(_window); }
        if (_initialized) { SDL.Quit(); }
    }
}
