// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Devices;
using SDL3;
using Touki;

namespace Retrocore.Input;

/// <summary>
///  The game controllers SDL sees, in the order they connected, read as <see cref="ControllerState"/>. SDL must
///  be initialized with its gamepad subsystem, and every call made on the thread that pumps SDL's events.
/// </summary>
/// <remarks>
///  <para>
///   SDL recognizes Xbox, PlayStation, Switch Pro and many other controllers, and maps each to the same layout,
///   so <see cref="ControllerButtons.South"/> is A on an Xbox controller and Cross on a PlayStation one.
///  </para>
/// </remarks>
public sealed class Controllers : DisposableBase
{
    private readonly List<(uint Id, IntPtr Gamepad, string Name)> _open = [];

    /// <summary>
    ///  Opens the controllers already connected. Later ones arrive through <see cref="Handle(in SDL.Event)"/>.
    /// </summary>
    public Controllers()
    {
        foreach (uint id in SDL.GetGamepads(out _) ?? []) { Open(id); }
    }

    /// <summary>
    ///  Gets the names of the open controllers, in the order they connected.
    /// </summary>
    public IEnumerable<string> Names => _open.Select(controller => controller.Name);

    /// <summary>
    ///  Gets how many controllers are open.
    /// </summary>
    public int Count => _open.Count;

    /// <summary>
    ///  Opens or closes a controller as SDL reports it connected or disconnected.
    /// </summary>
    /// <param name="input">An event from SDL's queue; other events are ignored.</param>
    /// <returns>Whether the set of controllers changed.</returns>
    public bool Handle(in SDL.Event input)
    {
        switch ((SDL.EventType)input.Type)
        {
            case SDL.EventType.GamepadAdded:
                return Open(input.GDevice.Which);
            case SDL.EventType.GamepadRemoved:
                uint which = input.GDevice.Which;
                int index = _open.FindIndex(controller => controller.Id == which);
                if (index < 0) { return false; }
                SDL.CloseGamepad(_open[index].Gamepad);
                _open.RemoveAt(index);
                return true;
            default:
                return false;
        }
    }

    /// <summary>
    ///  Reads every open controller's left stick and buttons.
    /// </summary>
    /// <param name="states">Receives one state per controller, in the order they connected; cleared first.</param>
    public void Read(List<ControllerState> states)
    {
        states.Clear();
        foreach ((_, IntPtr gamepad, string name) in _open)
        {
            ControllerButtons buttons = ControllerButtons.None;
            foreach ((SDL.GamepadButton button, ControllerButtons mapped) in s_buttons)
            {
                if (SDL.GetGamepadButton(gamepad, button)) { buttons |= mapped; }
            }

            states.Add(new(
                name,
                SDL.GetGamepadAxis(gamepad, SDL.GamepadAxis.LeftX),
                SDL.GetGamepadAxis(gamepad, SDL.GamepadAxis.LeftY),
                buttons));
        }
    }

    /// <inheritdoc/>
    protected override void Dispose(bool disposing)
    {
        if (!disposing) { return; }
        foreach ((_, IntPtr gamepad, _) in _open) { SDL.CloseGamepad(gamepad); }
        _open.Clear();
    }

    private static readonly (SDL.GamepadButton Button, ControllerButtons Mapped)[] s_buttons =
    [
        (SDL.GamepadButton.South, ControllerButtons.South),
        (SDL.GamepadButton.East, ControllerButtons.East),
        (SDL.GamepadButton.West, ControllerButtons.West),
        (SDL.GamepadButton.North, ControllerButtons.North),
        (SDL.GamepadButton.DPadUp, ControllerButtons.Up),
        (SDL.GamepadButton.DPadDown, ControllerButtons.Down),
        (SDL.GamepadButton.DPadLeft, ControllerButtons.Left),
        (SDL.GamepadButton.DPadRight, ControllerButtons.Right)
    ];

    private bool Open(uint id)
    {
        if (_open.Exists(controller => controller.Id == id)) { return false; }
        IntPtr gamepad = SDL.OpenGamepad(id);
        if (gamepad == IntPtr.Zero) { return false; }
        _open.Add((id, gamepad, SDL.GetGamepadName(gamepad) ?? "Controller"));
        return true;
    }
}
