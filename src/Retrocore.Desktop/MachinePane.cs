// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Primitives;
using Avalonia.Platform.Storage;
using Retrocore.Debug;
using Retrocore.Machines.Devices;
using System.Runtime.CompilerServices;
using System.Text.Json.Nodes;

namespace Retrocore.Desktop;

/// <summary>
///  The machine's side pane, as the extension's Retrocore views are: the Machine section with the machine, its
///  settings and its hardware slot by slot; the Drives section with each controller's drives and their media; and
///  Display and Sound with the display panel's options. Each action is the extension's, from Switch Machine and Add
///  Card to Insert Media and Save Disk As.
/// </summary>
internal sealed class MachinePane : ScrollViewer
{
    // The icons of the Machine section's rows, by hardware id, when the row is not a slot.
    private static readonly Dictionary<string, string> s_hardwareIcons = new()
    {
        ["cpu"] = "chip",
        ["rom"] = "file-binary",
        ["memory"] = "server",
        ["video"] = "device-desktop",
        ["builtIn"] = "plug",
        ["gamePort"] = "game",
        ["cassette"] = "record-keys",
        ["auxiliary"] = "extensions",
    };

    private readonly MainWindow _window;
    private readonly MachineSession _session;
    private readonly DesktopSettings _settings;
    private readonly ViewTree _machineTree = new();
    private readonly ViewTree _driveTree = new();
    private readonly ViewSection _machine;
    private readonly ViewSection _drives;
    private readonly StackPanel _display = new() { Margin = new Thickness(0, 2, 0, 8) };
    // The machine the Display and Sound section was built for, with the sound modes and screens it offered then.
    private string? _displayFor;

    /// <summary>
    ///  Creates the pane.
    /// </summary>
    /// <param name="window">The window, for its dialogs and file pickers.</param>
    /// <param name="session">The machine.</param>
    /// <param name="settings">The settings Fast disk is kept in.</param>
    internal MachinePane(MainWindow window, MachineSession session, DesktopSettings settings)
    {
        _window = window;
        _session = session;
        _settings = settings;
        _machine = new ViewSection("Machine", _machineTree, first: true);
        _drives = new ViewSection("Drives", _driveTree);
        HorizontalScrollBarVisibility = ScrollBarVisibility.Auto;
        Content = new StackPanel { Children = { _machine, _drives, new ViewSection("Display and Sound", _display) } };
        session.Changed += (_, _) => Refresh();
        Refresh();
    }

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The theme's scroll viewer template, which a type of its own would not otherwise get: without it the pane
    ///   has no scroll bar and clips what does not fit.
    ///  </para>
    /// </remarks>
    protected override Type StyleKeyOverride => typeof(ScrollViewer);

    /// <summary>
    ///  Gets the Machine section's tree, for the smoke run's checks.
    /// </summary>
    internal ViewTree MachineTree => _machineTree;

    /// <summary>
    ///  Gets the Drives section's tree, for the smoke run's checks.
    /// </summary>
    internal ViewTree DriveTree => _driveTree;

    /// <summary>
    ///  Draws the sections from the machine as it is now. Unchanged rows are left as they are.
    /// </summary>
    internal void Refresh()
    {
        MachineHost host = _session.Host;
        IReadOnlyList<HardwareRow> hardware = host.Hardware();
        IReadOnlyList<DeviceState> devices = host.DeviceStates();
        List<(HardwareRow Row, List<DeviceState> Devices)> rows = Group(hardware, devices, out List<DeviceState> loose);

        _machineTree.Show(MachineRows(host, hardware, rows));
        _driveTree.Show(DriveRows(rows, loose));
        _machine.SetActions(
            _session.Running ? [] : [new("arrow-swap", "Switch Machine...", () => _ = SwitchMachine())],
            [[new(Icon: null, "Start Machine...", () => _ = StartMachine()), new(Icon: null, "Reset Saved Machine...", () => _ = ResetSaved())]]);

        _machine.SetMessage(_session.Problems.Count == 0 ? null : $"{_session.Name} could not be fully set up: {string.Join(" ", _session.Problems)}");

        // The badge counts the disks changed in the machine and not yet saved to their images.
        int changed = devices.Count(device => device.Media?.Changed == true && device.Can(MediaOperations.Save));
        _drives.SetBadge(changed, $"{changed} disk{(changed == 1 ? "" : "s")} changed and not saved to {(changed == 1 ? "its image" : "their images")}");

        // Built again for another machine, or when a card changes what this one offers, as adding a Mockingboard does.
        string displayFor = $"{RuntimeHelpers.GetHashCode(host)}|{string.Join(',', host.SoundModes)}|{string.Join(',', host.Screens)}";
        if (_displayFor != displayFor)
        {
            _displayFor = displayFor;
            BuildDisplay(host);
        }
    }

    // The hardware rows, each with the devices on it, and the devices no row claims.
    private static List<(HardwareRow Row, List<DeviceState> Devices)> Group(
        IReadOnlyList<HardwareRow> hardware,
        IReadOnlyList<DeviceState> devices,
        out List<DeviceState> loose)
    {
        Dictionary<string, DeviceState> byId = devices.ToDictionary(device => device.Id);
        HashSet<string> claimed = [];
        List<(HardwareRow, List<DeviceState>)> rows = [];
        foreach (HardwareRow row in hardware)
        {
            List<DeviceState> on = [];
            foreach (string id in row.Devices ?? [])
            {
                if (byId.TryGetValue(id, out DeviceState? device) && claimed.Add(id)) { on.Add(device); }
            }

            rows.Add((row, on));
        }

        loose = [.. devices.Where(device => !claimed.Contains(device.Id))];
        return rows;
    }

    private static bool IsEmpty(HardwareRow row) => row.Value is "empty" or "none";

    private static string HardwareTooltip(HardwareRow row) => $"**{Tip.Escape(row.Name)}**: {Tip.Escape(row.Value)}\n\n{Tip.Escape(row.Description)}";

    // The Machine section: the machine, with its settings and hardware under it, then its BASIC program, and while it
    // is off a row to switch to another.
    private List<TreeNode> MachineRows(MachineHost host, IReadOnlyList<HardwareRow> hardware, List<(HardwareRow Row, List<DeviceState> Devices)> rows)
    {
        bool running = _session.Running;
        HardwareRow? model = hardware.FirstOrDefault(row => row.Id == "model");
        string status = !running ? "off" : host.Stopped is not null ? "stopped" : "running";
        string machine = host.KeyMapName;

        List<TreeNode> children = [];
        if (_session.CatalogMachine is { Choices.Count: > 0 } catalog)
        {
            children.Add(new TreeNode
            {
                Id = "settings",
                Label = "Settings",
                Icon = "settings-gear",
                Description = running ? "fixed while it runs" : null,
                Tooltip = running
                    ? "What the machine was built with. Stop it to change them."
                    : "What the machine is built with. A change keeps the cards and media you added, where they still fit.",
                State = running ? TreeState.Collapsed : TreeState.Expanded,
                Children = [.. catalog.Choices.Select(choice => SettingRow(choice, running))],
            });
        }

        foreach ((HardwareRow row, List<DeviceState> devices) in rows.Where(entry => entry.Row.Id != "model"))
        {
            children.Add(HardwareRowNode(row, devices));
        }

        string name = _session.Name;
        string tooltip = (model is null ? "" : $"**{Tip.Escape(model.Name)}**: {Tip.Escape(model.Value)}\n\n{Tip.Escape(model.Description)}\n\n")
            + (!running
                ? $"*{Tip.Escape(name)}*, off. Cards and media changed now are there when it starts."
                : host.Stopped is { } why
                    ? $"Started as *{Tip.Escape(name)}*, stopped: {Tip.Escape(why)} Press Reset to go on."
                    : $"Started as *{Tip.Escape(name)}*, running.");

        List<TreeNode> roots =
        [
            new TreeNode
            {
                Id = "machine",
                Label = model?.Name ?? name,
                Description = string.Join(" · ", new[] { model?.Value, status }.Where(part => part is not null)),
                IconControl = () => MachineIcon.Create(machine, lit: running && host.Stopped is null),
                Tooltip = tooltip,
                State = TreeState.Expanded,
                Children = children,
                Inline = running
                    ? [new("debug-restart", "Restart", () => _ = Release("Restart", _session.Restart)), new("debug-stop", "Stop", () => _ = Release("Stop", _session.Stop))]
                    : [new("arrow-swap", "Switch Machine...", () => _ = SwitchMachine()), new("play", "Start This Machine", () => Try(_session.Start))],
            },
        ];

        if (running && host.Basic() is { } basic)
        {
            roots.Add(new TreeNode
            {
                Id = "basic",
                Label = "BASIC program",
                Description = $"{basic.DisplayName} · {(basic.Lines == 0 ? "no program" : basic.Lines == 1 ? "1 line" : $"{basic.Lines} lines")}",
                Icon = "file-code",
                Tooltip = $"**BASIC program**: the {Tip.Escape(basic.DisplayName)} program in the machine's memory.",
            });
        }

        if (!running)
        {
            roots.Add(new TreeNode
            {
                Id = "switch",
                Label = "Switch to Another Machine…",
                Icon = "arrow-swap",
                Tooltip = "Pick a machine to set up, off, and start from here.",
                Command = () => _ = SwitchMachine(),
            });
        }

        return roots;
    }

    // One setting: its value, and while off a click to pick another.
    private TreeNode SettingRow(MachineChoice choice, bool running)
    {
        object value = MachineCatalog.Value(choice, _session.Configuration);
        ChoiceValue? chosen = choice.Values.FirstOrDefault(candidate => Equals(candidate.Value, value));
        string standard = choice.Values.FirstOrDefault(candidate => Equals(candidate.Value, choice.Default))?.Label ?? choice.Default.ToString() ?? "";
        string tooltip = $"**{Tip.Escape(choice.Label)}**: {Tip.Escape(chosen?.Label ?? value.ToString() ?? "")}";
        if (chosen?.Detail is { } detail) { tooltip += $"\n\n{Tip.Escape(detail)}"; }
        tooltip += $"\n\nThe launch option `{choice.Option}`; {Tip.Escape(standard)} by default.";
        if (running) { tooltip += " Stop the machine to change it."; }

        return new TreeNode
        {
            Id = $"setting/{choice.Option}",
            Label = choice.Label,
            Description = chosen?.Label ?? value.ToString(),
            Tooltip = tooltip,
            Command = running ? null : () => _ = ChangeSetting(choice),
        };
    }

    // A piece of the installed hardware, with its switches under it.
    private TreeNode HardwareRowNode(HardwareRow row, List<DeviceState> devices)
    {
        bool empty = IsEmpty(row);
        int drives = devices.Count;
        List<TreeAction> inline = [];
        if (row.Actions?.Contains("addCard") == true) { inline.Add(new("add", "Add Card...", () => _ = AddCard(row))); }
        if (row.Actions?.Contains("removeCard") == true)
        {
            inline.Add(new("trash", "Remove Card", () => _ = RemoveCard(row, devices)));
        }

        return new TreeNode
        {
            Id = $"hardware/{row.Id}",
            Label = row.Name,
            Description = drives == 0 || empty ? row.Value : $"{row.Value} · {drives} drive{(drives == 1 ? "" : "s")}",
            Tooltip = HardwareTooltip(row),
            Icon = empty ? "circle-outline" : s_hardwareIcons.GetValueOrDefault(row.Id, "circuit-board"),
            IconColour = empty ? Palette.Disabled : Palette.Icon,
            State = (row.Settings?.Length ?? 0) > 0 ? TreeState.Collapsed : TreeState.None,
            Inline = inline,
            Children = [.. (row.Settings ?? []).Select(setting => new TreeNode
            {
                Id = $"hardware/{row.Id}/{setting.Id}",
                Label = setting.Label,
                Description = setting.Value ? "on" : "off",
                Tooltip = $"**{Tip.Escape(setting.Label)}**: {Tip.Escape(setting.Description)}",
                Checked = setting.Value,
                Check = ticked => Try(() => _session.Hardware(row.Id, new JsonObject
                {
                    ["action"] = "setSetting",
                    ["setting"] = setting.Id,
                    ["value"] = ticked,
                })),
            })],
        };
    }

    // The Drives section: each controller with drives on it, its drives under it, and each drive's details under that.
    private List<TreeNode> DriveRows(List<(HardwareRow Row, List<DeviceState> Devices)> rows, List<DeviceState> loose)
    {
        List<TreeNode> roots = [];
        foreach ((HardwareRow row, List<DeviceState> devices) in rows.Where(entry => entry.Devices.Count > 0))
        {
            roots.Add(new TreeNode
            {
                Id = $"controller/{row.Id}",
                Label = row.Name,
                Description = row.Value,
                Tooltip = HardwareTooltip(row),
                Icon = s_hardwareIcons.GetValueOrDefault(row.Id, "circuit-board"),
                State = TreeState.Expanded,
                Children = [.. devices.Select(DriveRow)],
            });
        }

        roots.AddRange(loose.Select(DriveRow));
        return roots;
    }

    private TreeNode DriveRow(DeviceState device)
    {
        bool running = _session.Running;
        string tooltip = $"**{Tip.Escape(device.Info.Name)}**: {Tip.Escape(device.Info.Description)}\n\n"
            + string.Join("\n", device.Details.Select(row => $"- {row.Detail}: {Tip.Escape(row.Value)}"));

        // While the machine is off, a tape cannot record and nothing has changed a disk to save.
        List<TreeAction> inline = [];
        if (device.Can(MediaOperations.Insert)) { inline.Add(new("add", "Insert Media...", () => _ = Insert(device))); }
        if (running && device.Can(MediaOperations.Record))
        {
            inline.Add(new("record", "Record to...", () => _ = Record(device)));
        }

        if (device.Media is not null && device.Can(MediaOperations.Eject))
        {
            inline.Add(new("eject", "Eject", () => Act(device, "eject")));
        }

        if (device.Media is { } media && device.Can(MediaOperations.WriteProtect))
        {
            inline.Add(media.WriteProtected
                ? new("unlock", "Allow Writes", () => Act(device, "writeProtect", new JsonObject
                {
                    ["writeProtected"] = false
                }))
                : new("lock", "Write Protect", () => Act(device, "writeProtect", new JsonObject
                {
                    ["writeProtected"] = true
                })));
        }

        if (running && device.Media?.Changed == true && device.Can(MediaOperations.Save))
        {
            inline.Add(new("save", "Save to Its Image", () => _ = Save(device)));
        }

        List<IReadOnlyList<TreeAction>> menu = [];
        if (running && device.Media is not null && device.Can(MediaOperations.Save))
        {
            menu.Add([new(Icon: null, "Save Disk As...", () => _ = SaveAs(device))]);
        }

        return new TreeNode
        {
            Id = device.Id,
            Label = device.Info.Name,
            Description = device.Summary,
            Icon = device.Kind switch
            {
                DeviceKind.TapeDrive => "record-keys",
                DeviceKind.BlockStorage => "database",
                _ => "save"
            },
            IconColour = device.Activity switch
            {
                DeviceActivity.Writing => Palette.Writing,
                DeviceActivity.Reading => Palette.Reading,
                DeviceActivity.Seeking => Palette.Seeking,
                _ => device.Media is null ? Palette.Disabled : Palette.Icon,
            },
            Tooltip = tooltip,
            State = TreeState.Collapsed,
            Inline = inline,
            Menu = menu,
            Children = [.. device.Details.Select(row => new TreeNode
            {
                Id = $"{device.Id}/{row.Detail}",
                Label = row.Detail,
                Description = row.Value,
                Tooltip = Tip.Escape(row.Value),
            })],
        };
    }

    // An action that may fail, as a file the machine cannot read: the error shows as a notification.
    private void Try(Action action)
    {
        try
        {
            action();
        }
        catch (Exception exception) when (exception is ArgumentException
            or InvalidOperationException
            or IOException
            or UnauthorizedAccessException
            or NotSupportedException
            or InvalidDataException)
        {
            _window.Notify($"Retrocore: {exception.Message}");
        }

        Refresh();
    }

    private void Act(DeviceState device, string action, JsonObject? args = null) =>
        _ = Send(answer => _session.Device(device.Id, action, answer), args ?? []);

    /// <summary>
    ///  Gets the devices with disks whose changes are not saved to their images.
    /// </summary>
    internal IReadOnlyList<DeviceState> Unsaved => [.. _session.Host.DeviceStates().Where(device => device.Media?.Changed == true && device.Can(MediaOperations.Save))];

    /// <summary>
    ///  Asks about each disk whose changes are not saved before something that sets the machine up again would lose
    ///  them: save it, or let the changes go.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   The machine holds still from the first question, so it cannot change a disk after its question or one it was
    ///   not asked about; it stays held for what follows, which builds it again, and runs on if the person cancels.
    ///   Each disk is asked about until it is saved or let go: one whose save could not keep all of it, as a lossy
    ///   format's, is asked about again, and goes only if it is let go.
    ///  </para>
    /// </remarks>
    /// <param name="what">What would lose them, such as <c>Stop</c>, for the question.</param>
    /// <returns>
    ///  True when every disk was saved or let go, with the machine held; false when the person cancelled or a save
    ///  failed, with the machine running on.
    /// </returns>
    internal async Task<bool> ReleaseMedia(string what)
    {
        // One at a time: Stop, Restart, switching, starting, resetting and closing each hold the machine for their
        // questions, so one asking while another is would let go of the other's hold.
        if (Busy)
        {
            _window.Notify("Retrocore: answer the open question about the disks first.", "info");
            return false;
        }

        Busy = true;
        MachineHost held = _session.Host;
        held.Pause();
        bool released = false;
        try
        {
            released = await AskAboutUnsaved(what);
            return released;
        }
        finally
        {
            Busy = false;
            if (!released) { held.Resume(); }
        }
    }

    /// <summary>
    ///  Gets whether something that sets the machine up again is asking about its changed disks, holding it still.
    /// </summary>
    internal bool Busy { get; private set; }

    /// <summary>
    ///  Holds the machine still, as before something that sets it up again: the window closing holds it, and asks
    ///  only when a disk has changes not saved.
    /// </summary>
    internal void Hold() => _session.Host.Pause();

    // Asks about each changed disk until it is saved or let go; says whether all were, or false when one was not.
    private async Task<bool> AskAboutUnsaved(string what)
    {
        HashSet<(string Id, int? Generation)> discarded = [];
        HashSet<(string Id, int? Generation)> saved = [];
        while (Unsaved.FirstOrDefault(device => !discarded.Contains((device.Id, device.Generation))) is { } device)
        {
            (string Id, int? Generation) mount = (device.Id, device.Generation);
            string file = Path.GetFileName(device.Media?.Label) ?? "its image";
            string? answer = saved.Contains(mount)
                ? await _window.Ask(
                    $"{file} cannot hold all of the disk in {device.Info.Name}, so it still has changes. Let them go before {what}?",
                    ["Discard"])
                : await _window.Ask($"The disk in {device.Info.Name} has changes not saved to {file}. Save them before {what}?", ["Save", "Discard"]);

            if (answer == "Discard")
            {
                discarded.Add(mount);
                continue;
            }

            saved.Add(mount);
            JsonObject save = new() { ["generation"] = device.Generation };
            if (answer is null || !await Send(args => _session.Device(device.Id, "save", args), save)) { return false; }
        }

        return true;
    }

    // Lets changed disks go, then acts, as Stop, Restart, switching, starting another machine and resetting do. The
    // machine held for the questions runs on if the action left it in place, as when Stop could not write a recording
    // or the new machine could not be built.
    private async Task Release(string what, Action action)
    {
        MachineHost held = _session.Host;
        if (!await ReleaseMedia(what)) { return; }
        Try(action);
        if (ReferenceEquals(_session.Host, held)) { held.Resume(); }
    }

    // Sends a media action and answers what comes back, as the extension does: a changed disk that would leave its
    // drive is saved or let go, a changed image is replaced or the disk saved as a new one, a lossy save is accepted
    // or saved as a new image, and a read-only image is saved as a new one. Says whether the action went through.
    // Each answer goes back for the disk it was about (its mount's generation, or the mount in discards), so a disk
    // that went in while a question was open is never saved or let go by it.
    private async Task<bool> Send(Func<JsonObject, JsonObject?> send, JsonObject args)
    {
        args["supportsRetrocoreMedia"] = 1;
        while (true)
        {
            JsonObject? answer = null;
            bool failed = false;
            Try(() =>
            {
                failed = true;
                answer = send((JsonObject)args.DeepClone());
                failed = false;
            });

            if (failed) { return false; }
            string device = answer?["device"]?.GetValue<string>() ?? "";
            JsonNode? generation = answer?["generation"]?.DeepClone();
            string name = _session.Host.DeviceStates().FirstOrDefault(state => state.Id == device)?.Info.Name ?? device;
            string file = Path.GetFileName(answer?["label"]?.GetValue<string>() ?? "");
            string label = file.Length != 0 ? file : "its image";
            switch (answer?["outcome"]?.GetValue<string>())
            {
                case null:
                    return true;
                case "saved":
                    Said(answer, name);
                    return true;
                case "changed":
                    string? choice = await _window.Ask($"The disk in {name} has changes not saved to {label}.", ["Save", "Discard"]);
                    if (choice is null) { return false; }
                    if (choice == "Discard")
                    {
                        JsonArray discards = args["discards"] as JsonArray ?? [];
                        discards.Add((JsonNode)new JsonObject { ["device"] = device, ["generation"] = generation });
                        args["discards"] = discards;
                    }
                    else if (!await Send(saveArgs => _session.Device(device, "save", saveArgs), SaveOf(generation)))
                    {
                        return false;
                    }

                    continue;
                case "conflict":
                    string image = Path.GetFileName(answer["path"]?.GetValue<string>()) ?? "The image";
                    string? replace = await _window.Ask(
                        answer["current"] is null
                            ? $"{image} was deleted since the disk in {name} was read from it. Save the disk there again?"
                            : answer["baseline"] is null
                                ? $"{image} changed since you chose it. Replace it with the disk in {name}?"
                                : $"{image} changed since the disk in {name} was read from it. Replace it with the disk?",
                        ["Replace", "Save As..."]);

                    if (replace == "Replace")
                    {
                        args["overwrite"] = new JsonObject { ["sha256"] = answer["current"]?["sha256"]?.DeepClone() };
                        args["generation"] = generation;
                        continue;
                    }

                    return replace == "Save As..." && await SaveAsNew(device, generation);
                case "losses":
                    string losses = string.Join(" ", (answer["losses"]?.AsArray() ?? []).Select(loss => loss?.GetValue<string>()));
                    string? accept = await _window.Ask(
                        $"{answer["format"]?.GetValue<string>()} cannot hold all of the disk in {name}: {losses}",
                        ["Save Anyway", "Save As..."]);

                    if (accept == "Save Anyway")
                    {
                        args["acceptLosses"] = true;
                        args["generation"] = generation;
                        continue;
                    }

                    return accept == "Save As..." && await SaveAsNew(device, generation);
                case "readOnly":
                    string why = answer["reason"]?.GetValue<string>() switch
                    {
                        "noImage" => $"The disk in {name} has no image of its own.",
                        "format" => $"The disk in {name} came from an image that can only be read.",
                        "file" => $"The image of the disk in {name} is read-only.",
                        _ => $"The image of the disk in {name} cannot be written.",
                    };

                    return await _window.Ask($"{why} Save the disk as a new image?", ["Save As..."]) is not null && await SaveAsNew(device, generation);
                default:
                    return true;
            }
        }
    }

    // What a save says beside saving: a WOZ1 image now WOZ2, a sector that read from a second copy, what was lost.
    private void Said(JsonObject answer, string name)
    {
        IEnumerable<string?> said = (answer["notes"]?.AsArray() ?? []).Concat(answer["losses"]?.AsArray() ?? [])
            .Select(node => node?.GetValue<string>());

        string text = string.Join(" ", said.Where(line => line is not null));
        if (text.Length != 0) { _window.Notify($"Saved the disk in {name}. {text}", "info"); }
    }

    // A save's arguments for the mount an answer was about.
    private static JsonObject SaveOf(JsonNode? generation) => new() { ["generation"] = generation?.DeepClone() };

    // Save As for a device by its id, as the answers offer it.
    // It carries the mount the answer was about, so a disk that went in since is not the one saved.
    private async Task<bool> SaveAsNew(string id, JsonNode? generation) =>
        _session.Host.DeviceStates().FirstOrDefault(state => state.Id == id) is { } device
            && await SaveAs(device, generation?.GetValue<int>());

    private async Task SwitchMachine()
    {
        // The machine shown has a check, as the extension's $(check) marks it.
        CatalogMachine? current = _session.CatalogMachine;
        List<QuickPickItem<CatalogMachine>> items = [new() { Label = "Machines", Separator = true }];
        items.AddRange(MachineCatalog.Machines.Select(machine => new QuickPickItem<CatalogMachine>
        {
            Label = machine.Label,
            Detail = machine.Detail,
            DescriptionIcon = machine == current ? "check" : null,
            Picked = machine == current,
            Value = machine,
        }));

        QuickPickItem<CatalogMachine>? picked = await _window.Pick(items, "Switch Machine", "Which machine to set up?");
        if (picked?.Value is not { } chosen) { return; }
        await Release("switching machines", () => _session.Switch(MachineCatalog.Configuration(chosen), saved: null));
    }

    private async Task StartMachine()
    {
        QuickPickItem<CatalogMachine>? picked = await _window.Pick(
            [.. MachineCatalog.Machines.Select(machine => new QuickPickItem<CatalogMachine>
            {
                Label = machine.Label, Detail = machine.Detail, Value = machine
            })],
            "Start Machine",
            "Which machine to start?");

        if (picked?.Value is not { } chosen) { return; }
        await Release("starting another machine", () =>
        {
            _session.Switch(MachineCatalog.Configuration(chosen), saved: null);
            _session.Start();
        });
    }

    private async Task ResetSaved()
    {
        string? answer = await _window.Ask($"Forget the cards and media kept for {_session.Name}, and set it up as it comes?", ["Reset"]);
        if (answer == "Reset") { await Release("resetting the machine", _session.ResetSaved); }
    }

    private async Task ChangeSetting(MachineChoice choice)
    {
        if (_session.Running)
        {
            _window.Notify("Retrocore: stop the machine to change its settings.", "info");
            return;
        }

        object current = MachineCatalog.Value(choice, _session.Configuration);
        QuickPickItem<ChoiceValue>? picked = await _window.Pick(
            [.. choice.Values.Select(candidate => new QuickPickItem<ChoiceValue>
            {
                Label = candidate.Label,
                Detail = candidate.Detail,
                Description = Equals(candidate.Value, choice.Default) ? "default" : null,
                Picked = Equals(candidate.Value, current),
                Value = candidate,
            })],
            $"{_session.Name}: {choice.Label}",
            "Applies when it starts; cards and disks you added stay");

        if (picked?.Value is not { } value || Equals(value.Value, current)) { return; }
        Try(() => _session.SetSetting(choice, value.Value));
    }

    private async Task AddCard(HardwareRow row)
    {
        QuickPickItem<Card>? picked = await _window.Pick(
            [.. Card.For(row.Id, _session.Host.KeyMapName).Select(card => new QuickPickItem<Card>
            {
                Label = card.Label, Detail = card.Detail, Value = card
            })],
            $"Add a card to {row.Name}",
            "");

        if (picked?.Value is { } card) { _ = Send(args => _session.Hardware(row.Id, args), card.Args()); }
    }

    // Taking out a card with disks in it ejects them, so it asks first.
    private async Task RemoveCard(HardwareRow row, List<DeviceState> devices)
    {
        if (devices.Any(device => device.Media is not null))
        {
            string? answer = await _window.Ask($"Remove the {row.Value} from {row.Name}? Its disks are ejected.", ["Remove Card"]);
            if (answer != "Remove Card") { return; }
        }

        _ = Send(args => _session.Hardware(row.Id, args), new JsonObject { ["action"] = "removeCard" });
    }

    private async Task Insert(DeviceState device)
    {
        IReadOnlyList<IStorageFile> files = await _window.StorageProvider.OpenFilePickerAsync(new FilePickerOpenOptions
        {
            Title = $"Insert in {device.Info.Name}",
            AllowMultiple = false,
            FileTypeFilter = Filters($"{device.Info.Name} images", device.Info.Formats),
        });

        if (files.Count != 0 && files[0].TryGetLocalPath() is { } path)
        {
            Act(device, "insert", new JsonObject { ["path"] = path });
        }
    }

    private async Task Record(DeviceState device)
    {
        IStorageFile? file = await _window.StorageProvider.SaveFilePickerAsync(new FilePickerSaveOptions
        {
            Title = $"Record from {device.Info.Name} to",
            FileTypeChoices = Filters($"{device.Info.Name} images", device.Info.Formats),
        });

        if (file?.TryGetLocalPath() is { } path) { Act(device, "record", new JsonObject { ["path"] = path }); }
    }

    // Saving over the disk's own image replaces the file it was loaded from, so it asks first.
    private async Task Save(DeviceState device)
    {
        if (device.Media is not { } media) { return; }
        string? answer = await _window.Ask($"Replace {media.Label} with the disk in {device.Info.Name}?", ["Save"]);
        if (answer == "Save") { Act(device, "save"); }
    }

    // Saves a disk to an image the person picks; says whether it was saved.
    private async Task<bool> SaveAs(DeviceState device, int? generation = null)
    {
        if (device.Media is not { } media) { return false; }
        IStorageFolder? folder = Path.GetDirectoryName(media.Label) is { Length: > 0 } directory
            ? await _window.StorageProvider.TryGetFolderFromPathAsync(directory)
            : null;

        IStorageFile? file = await _window.StorageProvider.SaveFilePickerAsync(new FilePickerSaveOptions
        {
            Title = $"Save the disk in {device.Info.Name} as",
            SuggestedFileName = Path.GetFileName(media.Label),
            SuggestedStartLocation = folder,
            FileTypeChoices = Filters("Disk images", [.. device.Info.Formats.Where(format => format is "woz" or "dsk" or "do" or "po")]),
        });

        if (file?.TryGetLocalPath() is not { } path) { return false; }

        // The person chose the file as it is now, so the save may replace that and nothing that comes after it.
        JsonObject args = new() { ["path"] = path, ["generation"] = generation ?? device.Generation };
        FileRevision? chosen = null;
        Try(() => chosen = FileRevision.Read(path));
        if (chosen is not null) { args["overwrite"] = new JsonObject { ["sha256"] = chosen.Sha256 }; }
        return await Send(saveArgs => _session.Device(device.Id, "save", saveArgs), args);
    }

    private static List<FilePickerFileType> Filters(string name, IReadOnlyList<string> formats) =>
        formats.Count == 0 ? [] : [new FilePickerFileType(name)
        {
            Patterns = [.. formats.Select(format => "*." + format)]
        }];

    // Display and Sound: the display panel's options.
    private void BuildDisplay(MachineHost host)
    {
        _display.Children.Clear();
        ComboBox speed = Options.Choice(["1×", "2×", "4×", "8×", "Max"], host.Speed switch
        {
            2 => 1,
            4 => 2,
            8 => 3,
            0 => 4,
            _ => 0,
        });

        speed.SelectionChanged += (_, _) => _session.Host.Speed = speed.SelectedIndex switch
        {
            1 => 2,
            2 => 4,
            3 => 8,
            4 => 0,
            _ => 1,
        };

        _display.Children.Add(Options.Row("Speed", speed, "How fast the machine runs, as a multiple of its clock. Sound plays only at 1x."));

        // As the display panel's Fast disk: a disk or tape loads as fast as the machine can run, whatever the speed.
        if (host.FastDriveKind is { } kind)
        {
            host.FastDrives = _settings.FastDrives;
            CheckBox fast = new()
            {
                IsChecked = _settings.FastDrives,
                MinWidth = 0,
                MinHeight = 0,
                Padding = new Thickness(0)
            };

            fast.IsCheckedChanged += (_, _) =>
            {
                _settings.FastDrives = fast.IsChecked == true;
                _session.Host.FastDrives = _settings.FastDrives;
                _settings.Save();
            };

            _display.Children.Add(Options.Row(kind == "disk" ? "Fast disk" : "Fast tape", fast, kind == "disk"
                ? "Runs as fast as it can while a disk drive's motor turns, then back at the chosen speed"
                : "Runs as fast as it can while the tape plays, then back at the chosen speed"));
        }

        // The machine's own modes, starting from the one it launched with.
        IReadOnlyList<string> modes = host.SoundModes;
        ComboBox sound = Options.Choice(
            [.. modes.Select(mode => mode switch
            {
                "off" => "Off", "mockingboard" => "Speaker + Mockingboard", _ => "Speaker"
            })],
            Math.Max(0, modes.ToList().IndexOf(host.SoundMode)));

        sound.SelectionChanged += (_, _) => _session.Host.SoundMode = modes[Math.Max(0, sound.SelectedIndex)];
        _display.Children.Add(Options.Row("Sound", sound, host.KeyMapName == "apple3"
            ? "What you hear while the machine runs at its real speed: off, or the speaker and the DAC"
            : "What you hear while the machine runs at its real speed: off, the speaker, or, with the Mockingboard in slot 4, the speaker and the Mockingboard (which slows emulation by about a quarter)"));

        Slider volume = new()
        {
            Minimum = 0,
            Maximum = 100,
            Value = host.Volume * 100,
            Width = Options.Width,
            MinHeight = 0
        };

        volume.ValueChanged += (_, _) => _session.Host.Volume = (float)(volume.Value / 100);
        _display.Children.Add(Options.Row("Volume", volume, "The sound's volume"));

        ComboBox scale = Options.Choice(["Sharp", "Fit"], _window.Screen.Sharp ? 0 : 1);
        scale.SelectionChanged += (_, _) =>
        {
            _window.Screen.Sharp = scale.SelectedIndex == 0;
            _window.Screen.InvalidateVisual();
        };

        _display.Children.Add(Options.Row("Scale", scale, "Sharp: each dot a whole number of screen pixels, as large as fits. Fit: fills the window."));

        IReadOnlyList<string> screens = host.Screens;
        if (screens.Count > 1)
        {
            ComboBox screen = Options.Choice([.. screens.Select(ScreenName)], Math.Max(0, screens.ToList().IndexOf(host.Screen)));
            screen.SelectionChanged += (_, _) => _session.Host.Screen = screens[Math.Max(0, screen.SelectedIndex)];
            _display.Children.Add(Options.Row("Screen", screen,
                "The monitor: color, a IIe's RGB card and monitor (Color RGB: solid colors without fringing), or a monochrome monitor of the time"));
        }
    }

    private static string ScreenName(string screen) => screen switch
    {
        "color" => "Color",
        "rgb" => "Color RGB",
        "white" => "Black and white",
        "green" => "Green",
        "amber" => "Amber",
        _ => screen,
    };
}