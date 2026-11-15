// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json;
using System.Text.Json.Nodes;

namespace Retrocore.Desktop;

/// <summary>
///  The desktop app's own settings, its theme, zoom, pane opacity and fast drives, kept under <c>desktop</c> in Retrocore's roaming
///  <c>settings.json</c>, beside the settings the hosts share.
/// </summary>
internal sealed class DesktopSettings
{
    /// <summary>
    ///  The fewest zoom steps: 1.2 to the -3, about 58%.
    /// </summary>
    internal const int MinimumZoom = -3;

    /// <summary>
    ///  The most zoom steps: 1.2 to the 6, about 300%.
    /// </summary>
    internal const int MaximumZoom = 6;

    /// <summary>
    ///  The least opaque the side pane can be, in percent.
    /// </summary>
    internal const int MinimumPaneOpacity = 50;

    /// <summary>
    ///  How opaque the side pane is unless set, in percent: just enough that the machine shows faintly through it.
    /// </summary>
    internal const int DefaultPaneOpacity = 95;

    private readonly string? _path;

    private DesktopSettings(string? path, string theme, int zoom, int paneOpacity, bool fastDrives)
    {
        FastDrives = fastDrives;
        _path = path;
        ThemeName = theme;
        Zoom = zoom;
        PaneOpacity = paneOpacity;
    }

    /// <summary>
    ///  Gets or sets the theme: <c>system</c>, <c>light</c> or <c>dark</c>.
    /// </summary>
    internal string ThemeName { get; set; }

    /// <summary>
    ///  Gets or sets the zoom, in VS Code's steps of 20%: 0 is 100%.
    /// </summary>
    internal int Zoom { get; set; }

    /// <summary>
    ///  Gets the zoom as a scale, 1.2 to the power of <see cref="Zoom"/>.
    /// </summary>
    internal double Scale => Math.Pow(1.2, Zoom);

    /// <summary>
    ///  Gets or sets how opaque the side pane's background is, in percent, from
    ///  <see cref="MinimumPaneOpacity"/> to 100.
    /// </summary>
    internal int PaneOpacity { get; set; }

    /// <summary>
    ///  Gets or sets whether machines run as fast as they can while a disk or tape is busy, true unless set.
    /// </summary>
    internal bool FastDrives { get; set; }

    /// <summary>
    ///  Gets the roaming settings file: <c>%APPDATA%\Retrocore\settings.json</c> on Windows.
    /// </summary>
    internal static string DefaultPath =>
        Path.Join(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Retrocore", "settings.json");

    /// <summary>
    ///  Reads the settings, or the defaults when there are none.
    /// </summary>
    /// <param name="path">The settings file, or null to keep them in memory only, as a smoke run does.</param>
    /// <returns>The settings.</returns>
    internal static DesktopSettings Load(string? path)
    {
        string theme = "system";
        int zoom = 0;
        int paneOpacity = DefaultPaneOpacity;
        bool fastDrives = true;
        if (path is not null && Read(path).Root?["desktop"] is JsonObject desktop)
        {
            if (desktop["theme"] is JsonValue themeValue && themeValue.GetValueKind() == JsonValueKind.String)
            {
                theme = themeValue.GetValue<string>();
            }

            // A number that is not a whole one in range, such as 1.5, keeps the default.
            if (desktop["zoom"] is JsonValue zoomValue && zoomValue.TryGetValue(out int zoomLevel))
            {
                zoom = zoomLevel;
            }

            if (desktop["paneOpacity"] is JsonValue opacityValue && opacityValue.TryGetValue(out int opacity))
            {
                paneOpacity = opacity;
            }

            if (desktop["fastDrives"] is JsonValue fastValue
                && fastValue.GetValueKind() is JsonValueKind.True or JsonValueKind.False)
            {
                fastDrives = fastValue.GetValue<bool>();
            }
        }

        return new(
            path,
            theme is "light" or "dark" ? theme : "system",
            Math.Clamp(zoom, MinimumZoom, MaximumZoom),
            Math.Clamp(paneOpacity, MinimumPaneOpacity, 100),
            fastDrives);
    }

    /// <summary>
    ///  Writes the settings, keeping everything else in the file as it was.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   The file is shared with the other hosts and other copies of the app, so its read, merge and replace hold a
    ///   lock file beside it, and each write goes to a temporary file of its own that is moved over the settings, so
    ///   a failed write leaves them as they were. A file that is there but is not a settings object, such as one
    ///   broken by hand, is left for its owner to fix rather than replaced with these settings alone.
    ///  </para>
    /// </remarks>
    /// <returns>Whether the settings were written.</returns>
    internal bool Save()
    {
        if (_path is null) { return false; }
        try
        {
            if (Path.GetDirectoryName(_path) is { Length: > 0 } directory) { Directory.CreateDirectory(directory); }
            using FileStream? held = Hold(_path + ".lock");
            if (held is null) { return false; }
            (JsonObject? read, bool broken) = Read(_path);
            if (broken) { return false; }
            JsonObject root = read ?? [];
            root["desktop"] = new JsonObject
            {
                ["theme"] = ThemeName,
                ["zoom"] = Zoom,
                ["paneOpacity"] = PaneOpacity,
                ["fastDrives"] = FastDrives
            };

            string temporary = $"{_path}.{Environment.ProcessId}.{Guid.NewGuid():N}.saving";
            try
            {
                File.WriteAllText(temporary, root.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
                File.Move(temporary, _path, overwrite: true);
            }
            finally
            {
                File.Delete(temporary);
            }

            return true;
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            // A setting that cannot be kept now is kept in memory: the app goes on, and the next change tries again.
            return false;
        }
    }

    // Takes the lock file, waiting a little for another copy of the app that holds it, or null when it stays held.
    private static FileStream? Hold(string path)
    {
        for (int attempt = 0; attempt < 20; attempt++)
        {
            try
            {
                return new FileStream(path, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
            }
            catch (IOException)
            {
                Thread.Sleep(25);
            }
        }

        return null;
    }

    // Reads the file: its object, or null with Broken false when there is none, or null with Broken true when it is
    // there but is not a settings object.
    private static (JsonObject? Root, bool Broken) Read(string path)
    {
        if (!File.Exists(path)) { return (null, false); }
        try
        {
            return JsonNode.Parse(File.ReadAllText(path)) is JsonObject root ? (root, false) : (null, true);
        }
        catch (JsonException)
        {
            // A file someone broke by hand is left for them to fix; the defaults hold until then.
            return (null, true);
        }
    }
}