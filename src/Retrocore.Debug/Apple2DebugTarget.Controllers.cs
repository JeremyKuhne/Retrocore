// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json.Nodes;
using Retrocore.Input;

namespace Retrocore.Debug;

// Game controllers on the game port: SDL reads them on a thread of its own, whatever window has focus, and each
// change sets the paddles and buttons.
internal sealed partial class Apple2DebugTarget
{
    private ControllerMonitor? _controllers;

    /// <summary>
    ///  Starts reading game controllers into the game port, unless the launch's <c>controllers</c> is false.
    /// </summary>
    /// <param name="args">The launch's arguments.</param>
    private void StartControllers(JsonObject args)
    {
        if (!(args.Bool("controllers") ?? true)) { return; }
        _controllers = new(states => _machine.Bus.GamePort.Apply(states));
    }

    // The Retro Devices view's game port row: the controllers driving it, or why none can.
    private HardwareRow GamePortRow()
    {
        string value = "Controllers off";
        if (_controllers?.Error is { } error)
        {
            value = "No controllers: " + error;
        }
        else if (_controllers is not null)
        {
            value = _controllers.Names.Count == 0 ? "No controller" : string.Join("; ", _controllers.Names);
        }

        return new(
            "gamePort",
            "Game port",
            value,
            "Game controllers drive the game port. The first is the joystick: its left stick or d-pad moves paddles 0 "
                + "and 1, and its A, B and X buttons (Cross, Circle and Square) press buttons 0, 1 and 2. A second "
                + "controller is paddles 2 and 3, its A button pressing button 2. The launch option controllers: false "
                + "turns this off.");
    }

    /// <inheritdoc/>
    protected override void Dispose(bool disposing)
    {
        if (!disposing) { return; }
        _controllers?.Dispose();
        _controllers = null;
        _machine.Bus.GamePort.Release();
    }
}
