// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json.Nodes;
using Touki;

using Retrocore.Debug;

namespace Retrocore.Desktop;

/// <summary>
///  The machine the window shows, running or off, as the extension's views show the active session's machine or,
///  with none, the off machine: started, stopped, switched for another and set up while off, with its cards and
///  media kept for the next time it starts.
/// </summary>
/// <remarks>
///  <para>
///   An off machine is built and never run, as the extension's off machine is, so its hardware and drives can be
///   shown and changed. Stopping a running machine captures its cards and media, writes its recordings and builds it
///   again, off, with them.
///  </para>
/// </remarks>
internal sealed class MachineSession : DisposableBase
{
    private readonly DesktopSettings _settings;
    private readonly bool _keep;

    /// <summary>
    ///  Sets up a machine, off, with the cards and media kept for it.
    /// </summary>
    /// <param name="configuration">The machine's launch configuration.</param>
    /// <param name="saved">Its saved cards and media, or null.</param>
    /// <param name="settings">The settings it is kept in.</param>
    /// <param name="keep">Whether the machine and its cards and media are kept in the settings as they change.</param>
    internal MachineSession(JsonObject configuration, JsonObject? saved, DesktopSettings settings, bool keep)
    {
        _settings = settings;
        _keep = keep;
        Host = Build(configuration, saved);
    }

    /// <summary>
    ///  Raised when the machine starts, stops, is switched for another, or its hardware or media change.
    /// </summary>
    internal event EventHandler? Changed;

    /// <summary>
    ///  Gets the machine.
    /// </summary>
    internal MachineHost Host { get; private set; }

    /// <summary>
    ///  Gets the machine's launch configuration.
    /// </summary>
    internal JsonObject Configuration => Host.Configuration;

    /// <summary>
    ///  Gets the configuration's name, such as <c>Apple IIe (enhanced)</c>.
    /// </summary>
    internal string Name => Configuration["name"] is JsonValue name && name.TryGetValue(out string? text) ? text : CatalogMachine?.Label ?? Host.Name;

    /// <summary>
    ///  Gets the catalog's machine it is, whose settings it has, or null.
    /// </summary>
    internal CatalogMachine? CatalogMachine => MachineCatalog.Find(Configuration);

    /// <summary>
    ///  Gets whether the machine runs.
    /// </summary>
    internal bool Running => Host.Running;

    /// <summary>
    ///  Gets what of the saved cards and media could not be put back, the last time any were.
    /// </summary>
    internal IReadOnlyList<string> Problems { get; private set; } = [];

    /// <summary>
    ///  Starts the machine, if it is off.
    /// </summary>
    internal void Start()
    {
        if (Host.Running) { return; }
        Host.Start();
        OnChanged();
    }

    /// <summary>
    ///  Stops the machine: its recordings are written and it is built again, off, with the cards and media it had.
    /// </summary>
    /// <exception cref="IOException">A recording could not be written; the machine runs on.</exception>
    /// <exception cref="UnauthorizedAccessException">A recording's path cannot be written; likewise.</exception>
    internal void Stop()
    {
        if (!Host.Running) { return; }
        Host.SaveRecordings();
        JsonObject saved = Host.Capture();
        Replace(Configuration, saved);
    }

    /// <summary>
    ///  Stops the machine and starts it again, with the cards and media it had, as the panel's Restart does.
    /// </summary>
    internal void Restart()
    {
        Stop();
        Start();
    }

    /// <summary>
    ///  Puts another machine in its place, off, as Switch Machine does.
    /// </summary>
    /// <param name="configuration">The machine's launch configuration.</param>
    /// <param name="saved">Its cards and media, or null for those its configuration gives.</param>
    internal void Switch(JsonObject configuration, JsonObject? saved)
    {
        if (Host.Running) { Host.SaveRecordings(); }
        Replace(configuration, saved);
    }

    /// <summary>
    ///  Changes a setting while the machine is off. The cards and media changed since it was set up stay on top of the
    ///  new setting, where the whole saved machine would put back what the setting replaced.
    /// </summary>
    /// <param name="choice">The setting.</param>
    /// <param name="value">Its new value.</param>
    /// <exception cref="InvalidOperationException">The machine runs, or cannot drop what its disks need.</exception>
    internal void SetSetting(MachineChoice choice, object value)
    {
        if (Host.Running) { throw new InvalidOperationException("Stop the machine to change its settings."); }
        if (choice.Option is "diskController" or "expansionInterface" or "diskInterface" && Equals(value, objB: false) && MachineCatalog.StartsWithDisks(Configuration))
        {
            throw new InvalidOperationException($"{Name} starts with disks in its drives, so it keeps its {choice.Label.ToLowerInvariant()}.");
        }

        JsonObject saved = Host.Capture();
        JsonObject next = MachineCatalog.WithSetting(Configuration, choice, value);
        JsonObject changes;
        using (MachineHost plain = new(Configuration))
        {
            changes = ChangesFrom(saved, plain.Capture());
        }

        Replace(next, changes, choice.Option);
    }

    /// <summary>
    ///  Changes the installed hardware, running or off.
    /// </summary>
    /// <param name="id">The hardware row's id.</param>
    /// <param name="args">The arguments, with the action.</param>
    /// <returns>
    ///  Media's answer, such as <c>changed</c> for a card with a changed disk; null when the machine acted.
    /// </returns>
    internal JsonObject? Hardware(string id, JsonObject args)
    {
        JsonObject? answer = Host.HardwareAction(id, args["action"]?.GetValue<string>() ?? throw new ArgumentException("action is required."), args);
        Keep();
        OnChanged();
        return answer;
    }

    /// <summary>
    ///  Changes a device's media, running or off.
    /// </summary>
    /// <param name="id">The device's id.</param>
    /// <param name="action">The action.</param>
    /// <param name="args">Its arguments.</param>
    /// <returns>Media's answer, such as <c>saved</c> or <c>changed</c>; null when the machine simply acted.</returns>
    internal JsonObject? Device(string id, string action, JsonObject? args = null)
    {
        JsonObject? answer = Host.DeviceAction(id, action, args ?? []);
        Keep();
        OnChanged();
        return answer;
    }

    /// <summary>
    ///  Forgets the cards and media kept for the machine, and sets it up again as its configuration gives it, off.
    /// </summary>
    internal void ResetSaved()
    {
        if (Host.Running) { Host.SaveRecordings(); }
        Replace(Configuration, saved: null);
    }

    /// <summary>
    ///  Keeps the machine and its cards and media in the settings, for the next time the app starts.
    /// </summary>
    internal void Keep()
    {
        if (!_keep) { return; }
        _settings.Machine = (JsonObject)Configuration.DeepClone();
        _settings.MachineState = Host.Capture();
        _settings.Save();
    }

    /// <summary>
    ///  Gets what of a saved machine differs from the machine its configuration gives by itself: the cards, their
    ///  switches and the media someone changed, as the extension's <c>changesFrom</c> finds them.
    /// </summary>
    /// <param name="saved">The saved machine.</param>
    /// <param name="plain">The machine as its configuration gives it.</param>
    /// <returns>The changes alone.</returns>
    internal static JsonObject ChangesFrom(JsonObject saved, JsonObject plain)
    {
        JsonObject changes = [];
        foreach (string section in (string[])["cards", "settings", "media"])
        {
            if (saved[section] is not JsonObject ours) { continue; }
            JsonObject theirs = plain[section] as JsonObject ?? [];
            JsonObject kept = [];
            foreach ((string key, JsonNode? value) in ours)
            {
                if (!JsonNode.DeepEquals(value, theirs[key])) { kept[key] = value?.DeepClone(); }
            }

            changes[section] = kept;
        }

        return changes;
    }

    private MachineHost Build(JsonObject configuration, JsonObject? saved)
    {
        MachineHost host = new(configuration, saved);
        Problems = saved is null ? [] : host.Restore(saved);
        host.SetMediaSpeed(tape: true, MediaSpeedPolicy.LaunchMode(configuration, tape: true) ?? _settings.TapeSpeed);
        host.SetMediaSpeed(tape: false, MediaSpeedPolicy.LaunchMode(configuration, tape: false) ?? _settings.DiskSpeed);
        return host;
    }

    // Builds the machine again. It keeps the old one's display and sound, as the panel keeps them across sessions:
    // its monitor and sound mode where it offers them, unless the setting just changed is that one.
    private void Replace(JsonObject configuration, JsonObject? saved, string? changed = null)
    {
        MachineHost before = Host;
        MachineHost after = Build(configuration, saved);
        after.Speed = before.Speed;
        after.Volume = before.Volume;
        if (changed != "monitor" && after.Screens.Contains(before.Screen)) { after.Screen = before.Screen; }
        if (changed != "sound")
        {
            string mode = before.SoundMode;
            after.SoundMode = after.SoundModes.Contains(mode) ? mode : "speaker";
        }

        Host = after;
        before.Dispose();
        Keep();
        OnChanged();
    }

    private void OnChanged() => Changed?.Invoke(this, EventArgs.Empty);

    /// <inheritdoc/>
    protected override void Dispose(bool disposing)
    {
        if (!disposing) { return; }
        try
        {
            if (Host.Running) { Host.SaveRecordings(); }
            Keep();
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            // The app is closing; a recording that cannot be written now is lost, as a debug session's is.
        }

        Host.Dispose();
    }
}