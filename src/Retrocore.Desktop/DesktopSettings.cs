// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json;
using System.Text.Json.Nodes;

namespace Retrocore.Desktop;

/// <summary>
///  The desktop app's own settings, its theme, zoom and pane opacity, kept under <c>desktop</c> in Retrocore's roaming
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
    ///  How opaque the side pane is unless set, in percent: enough that the machine is barely visible through it.
    /// </summary>
    internal const int DefaultPaneOpacity = 85;

    private readonly string? _path;

    private DesktopSettings(string? path, string theme, int zoom, int paneOpacity)
    {
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
        if (path is not null && Read(path)?["desktop"] is JsonObject desktop)
        {
            if (desktop["theme"] is JsonValue themeValue && themeValue.GetValueKind() == JsonValueKind.String)
            {
                theme = themeValue.GetValue<string>();
            }

            if (desktop["zoom"] is JsonValue zoomValue && zoomValue.GetValueKind() == JsonValueKind.Number)
            {
                zoom = zoomValue.GetValue<int>();
            }

            if (desktop["paneOpacity"] is JsonValue opacityValue && opacityValue.GetValueKind() == JsonValueKind.Number)
            {
                paneOpacity = opacityValue.GetValue<int>();
            }
        }

        return new(
            path,
            theme is "light" or "dark" ? theme : "system",
            Math.Clamp(zoom, MinimumZoom, MaximumZoom),
            Math.Clamp(paneOpacity, MinimumPaneOpacity, 100));
    }

    /// <summary>
    ///  Writes the settings, keeping everything else in the file as it was.
    /// </summary>
    internal void Save()
    {
        if (_path is null) { return; }
        JsonObject root = Read(_path) ?? [];
        root["desktop"] = new JsonObject { ["theme"] = ThemeName, ["zoom"] = Zoom, ["paneOpacity"] = PaneOpacity };

        // Written beside the file and moved over it, so a failed write leaves the settings as they were.
        if (Path.GetDirectoryName(_path) is { Length: > 0 } directory) { Directory.CreateDirectory(directory); }
        string temporary = _path + ".saving";
        File.WriteAllText(temporary, root.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
        File.Move(temporary, _path, overwrite: true);
    }

    private static JsonObject? Read(string path)
    {
        try
        {
            return File.Exists(path) ? JsonNode.Parse(File.ReadAllText(path)) as JsonObject : null;
        }
        catch (JsonException)
        {
            // A file someone broke by hand is left for them to fix; the defaults hold until then.
            return null;
        }
    }
}