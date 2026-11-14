// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json.Nodes;
using Retrocore.Machines.Devices;

namespace Retrocore.Debug;

/// <summary>
///  A machine the editor sets up while it is off: built as a launch builds it, with the cards and media saved for it,
///  and never run. The language server answers <c>retrocore/machine/describe</c> and <c>retrocore/machine/change</c>
///  with it, so the Machine and Drives views can show and change a machine with no debug session.
/// </summary>
/// <remarks>
///  <para>
///   Both requests take <c>{ "configuration": { launch arguments }, "machineState": { saved machine } }</c>, the
///   saved machine being what <see cref="MachineConfiguration"/> captures and a launch's <c>machineState</c>
///   restores. <c>change</c> also takes <c>"request": "hardware"</c> or <c>"device"</c> and <c>"arguments"</c>, as
///   <c>retro/hardware</c> and <c>retro/device</c> take them, such as <c>{ "id": "slot5", "action": "addDiskII",
///   "sectors": 16 }</c>. Both answer as <c>retro/devices</c> does (<c>devices</c>, <c>hardware</c>, and the new saved
///   machine as <c>configuration</c>), with <c>problems</c>: what of the saved machine could not be restored.
///  </para>
///  <para>
///   Nothing is kept between requests: each builds the machine afresh and disposes it, so the saved machine the
///   editor holds is the whole of an off machine's state. ROM dumps are used when the launch names them; without
///   them each machine's ROMs are assembled from the SDK's sources, as a launch does.
///  </para>
/// </remarks>
internal static class OffMachine
{
    // Requests run on their own threads; one machine is built at a time.
    private static readonly Lock s_gate = new();

    /// <summary>
    ///  Describes a machine with its saved cards and media.
    /// </summary>
    /// <param name="parameters">The launch configuration and the saved machine.</param>
    /// <returns>Its devices, hardware rows, saved machine and restore problems.</returns>
    /// <exception cref="ArgumentException">The configuration is missing or invalid.</exception>
    internal static JsonObject Describe(JsonObject parameters) => With(parameters, _ => { });

    /// <summary>
    ///  Changes a machine's hardware or a device's media, as <c>retro/hardware</c> or <c>retro/device</c> does.
    /// </summary>
    /// <param name="parameters">The launch configuration, the saved machine, the request and its arguments.</param>
    /// <returns>The changed machine's devices, hardware rows, saved machine and restore problems.</returns>
    /// <exception cref="ArgumentException">The configuration, request or arguments are missing or invalid.</exception>
    internal static JsonObject Change(JsonObject parameters)
    {
        JsonObject arguments = parameters["arguments"] as JsonObject ?? throw new ArgumentException("arguments is required.");
        string id = arguments.String("id") ?? throw new ArgumentException("id is required.");
        string action = arguments.String("action") ?? throw new ArgumentException("action is required.");
        string request = parameters.String("request") ?? throw new ArgumentException("request is required: hardware or device.");
        if (request is not ("hardware" or "device"))
        {
            throw new ArgumentException("request must be hardware or device.");
        }

        return With(parameters, target =>
        {
            if (request == "hardware")
            {
                target.HardwareAction(id, action, arguments);
                return;
            }

            IDevice device = target.Devices.FirstOrDefault(device => device.Id == id) ?? throw new ArgumentException($"There is no device '{id}'.");
            target.DeviceAction(device, action, arguments);
        });
    }

    // Builds the machine with its saved cards and media, acts on it, and describes it.
    private static JsonObject With(JsonObject parameters, Action<IDebugTarget> act)
    {
        JsonObject configuration = parameters["configuration"] as JsonObject ?? throw new ArgumentException("configuration is required: the machine's launch arguments.");

        lock (s_gate)
        {
            IDebugTarget target = Build(configuration);
            try
            {
                List<string> problems = parameters["machineState"] is JsonObject saved
                    ? MachineConfiguration.Restore(target, saved)
                    : [];

                act(target);
                JsonObject body = DeviceJson.Write(target.Devices);
                body["hardware"] = HardwareRow.Json(Off(target.Hardware(), configuration));
                body["configuration"] = MachineConfiguration.Capture(target);
                body["problems"] = problems.ToJsonArray();
                return body;
            }
            finally
            {
                (target as IDisposable)?.Dispose();
            }
        }
    }

    /// <summary>
    ///  Builds the machine a launch configuration describes, as a launch does, without booting or running it.
    /// </summary>
    /// <param name="configuration">The launch arguments.</param>
    /// <returns>The machine.</returns>
    /// <exception cref="ArgumentException">The configuration is invalid.</exception>
    internal static IDebugTarget Build(JsonObject configuration)
    {
        // Game controllers are read only while a machine runs; an off machine does not open them.
        JsonObject args = (JsonObject)configuration.DeepClone();
        args["controllers"] = false;
        // Each machine by name, as DebugSession's launch builds it, so a machine added there and not here fails rather
        // than being built as another.
        string machine = DebugMachines.Require(args.String("machine"));
        return machine switch
        {
            DebugMachines.Apple2 => Apple2DebugTarget.Launch(args),
            DebugMachines.Trs80Model1 => Trs80DebugTarget.Launch(args),
            DebugMachines.Trs80Model3 => Trs80Model3DebugTarget.Launch(args),
            DebugMachines.Trs80Model2 => Trs80Model2DebugTarget.Launch(args),
            DebugMachines.Apple3 => Apple3DebugTarget.Launch(args),
            DebugMachines.Apple1 => Apple1DebugTarget.Launch(args),
            DebugMachines.Coco => CocoDebugTarget.Launch(args),
            DebugMachines.Altair => AltairDebugTarget.Launch(args),
            _ => throw new ArgumentException($"A machine that is off cannot yet be a {machine}.")
        };
    }

    // The rows as the machine will have them when it runs: the game port reads controllers then, unless the launch
    // turns them off.
    private static IEnumerable<HardwareRow> Off(IEnumerable<HardwareRow> rows, JsonObject configuration) =>
        rows.Select(row => row.Id == "gamePort" && (configuration.Bool("controllers") ?? true)
            ? row with { Value = "Controllers, read while it runs" }
            : row);
}
