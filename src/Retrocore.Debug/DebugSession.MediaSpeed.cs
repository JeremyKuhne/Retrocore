// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json.Nodes;
using Retrocore.Machines.Devices;

namespace Retrocore.Debug;

internal sealed partial class DebugSession
{
    private MediaSpeedPolicy? _mediaSpeed;
    private JsonObject? _bootMediaSpeed;
    private string? _tapeSpeedFallback;
    private string? _diskSpeedFallback;

    private MediaSpeedPolicy MediaSpeedSettings => _mediaSpeed ?? throw new InvalidOperationException("No machine has been launched.");

    private JsonObject MediaSpeedRequest(JsonObject args)
    {
        if (args["mode"] is { } mode)
        {
            bool tape = args.String("kind") switch
            {
                "tape" => true,
                "disk" => false,
                _ => throw new ArgumentException("Media speed kind must be tape or disk.")
            };

            MediaSpeedSettings.Set(tape, MediaSpeedPolicy.Parse(mode));
            _paceAgain = true;
            if (_run is not { IsCancellationRequested: false }) { NotifyFrame(running: false); }
        }

        return MediaSpeedSettings.ToJson();
    }

    private void ConfigureMediaSpeed((MediaSpeed? Tape, MediaSpeed? Disk) settings)
    {
        _mediaSpeed = new(Target);
        _mediaSpeed.Apply(settings);
        _bootMediaSpeed = null;
        _tapeSpeedFallback = _diskSpeedFallback = null;
    }

    private void NotifyMediaSpeed()
    {
        NotifyMediaSpeed(tape: true, MediaSpeedSettings.Tape, ref _tapeSpeedFallback);
        NotifyMediaSpeed(tape: false, MediaSpeedSettings.Disk, ref _diskSpeedFallback);
    }

    private JsonObject MediaSpeedFrame()
    {
        JsonObject state = MediaSpeedSettings.ToJson();
        state["boot"] = _bootMediaSpeed?.DeepClone();
        state["tapeFallback"] = MediaSpeedSettings.Tape == MediaSpeed.Skip && MediaSpeedSettings.Active(tape: true) is not null;
        state["diskFallback"] = MediaSpeedSettings.Disk == MediaSpeed.Skip && MediaSpeedSettings.Active(tape: false) is not null;
        return state;
    }

    private void NotifyMediaSpeed(bool tape, MediaSpeed requested, ref string? lastDevice)
    {
        IDevice? active = requested == MediaSpeed.Skip ? MediaSpeedSettings.Active(tape) : null;
        string? device = active?.Id;
        if (device == lastDevice) { return; }
        lastDevice = device;
        if (device is not null)
        {
            Notify("retro/mediaSpeed", WithIdentity(MediaSpeedPolicy.Outcome(tape, requested, MediaSpeed.Fast, device, "unsupportedOperation")));
        }
    }
}
