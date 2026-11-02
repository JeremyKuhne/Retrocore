// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Devices;
using SDL3;
using Touki;

namespace Retrocore.Input;

/// <summary>
///  Reads game controllers on a thread of its own, for a process with no window or event loop, such as the debug
///  host. It reports the controllers' state each time it changes, and reads them whatever window has focus.
/// </summary>
public sealed class ControllerMonitor : DisposableBase
{
    // How long the thread waits for an SDL event before reading the controllers again: about 4 ms is finer than
    // a 60 Hz frame and costs nothing when no controller is connected.
    private const int PollMilliseconds = 4;

    private readonly Action<IReadOnlyList<ControllerState>> _changed;
    private readonly Thread _thread;
    private readonly ManualResetEventSlim _started = new();
    private volatile bool _stopping;
    private string? _error;
    private string[] _names = [];

    /// <summary>
    ///  Starts reading controllers.
    /// </summary>
    /// <param name="changed">
    ///  Called on the monitor's thread with every controller's state, in the order they connected, whenever any
    ///  of them changes, including when one connects or disconnects.
    /// </param>
    public ControllerMonitor(Action<IReadOnlyList<ControllerState>> changed)
    {
        _changed = changed;
        _thread = new(Run) { IsBackground = true, Name = "Retrocore controllers" };
        _thread.Start();
        _started.Wait();
    }

    /// <summary>
    ///  Gets why controllers can't be read, such as SDL's native library missing, or null when they can.
    /// </summary>
    public string? Error => _error;

    /// <summary>
    ///  Gets the connected controllers' names, in the order they connected.
    /// </summary>
    public IReadOnlyList<string> Names => Volatile.Read(ref _names);

    /// <inheritdoc/>
    protected override void Dispose(bool disposing)
    {
        if (!disposing) { return; }
        _stopping = true;
        _thread.Join();
        _started.Dispose();
    }

    private void Run()
    {
        try
        {
            // The host has no window, so it never has focus; without this SDL would ignore every controller.
            SDL.SetHint(SDL.Hints.JoystickAllowBackgroundEvents, "1");
            if (!SDL.Init(SDL.InitFlags.Gamepad))
            {
                _error = SDL.GetError();
                return;
            }
        }
        catch (Exception exception) when (exception is DllNotFoundException or EntryPointNotFoundException)
        {
            _error = exception.Message;
            return;
        }
        finally
        {
            _started.Set();
        }

        try
        {
            using Controllers controllers = new();
            List<ControllerState> states = [];
            List<ControllerState> last = [];
            bool changed = true;
            while (!_stopping)
            {
                if (SDL.WaitEventTimeout(out SDL.Event input, PollMilliseconds))
                {
                    changed |= controllers.Handle(input);
                    while (SDL.PollEvent(out input)) { changed |= controllers.Handle(input); }
                }

                controllers.Read(states);
                if (changed || !states.SequenceEqual(last))
                {
                    Volatile.Write(ref _names, [.. controllers.Names]);
                    _changed(states);
                    (last, states) = (states, last);
                    changed = false;
                }
            }
        }
        finally
        {
            SDL.QuitSubSystem(SDL.InitFlags.Gamepad);
        }
    }
}
