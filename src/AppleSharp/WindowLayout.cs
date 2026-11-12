// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using SDL3;

namespace AppleSharp;

/// <summary>
///  Letterboxes the 560-dot signal at the Apple II's 280:192 display aspect ratio.
/// </summary>
internal static class WindowLayout
{
    /// <summary>
    ///  Uses whole physical pixels for the debug font, with a readable two-times minimum.
    /// </summary>
    /// <param name="displayScale">The display's content scale.</param>
    /// <returns>The default integer UI scale.</returns>
    internal static int DefaultUiScale(float displayScale) => Math.Clamp((int)Math.Ceiling(displayScale), 2, 4);

    /// <summary>
    ///  Places controls in the same scaled coordinate system used for drawing and hit testing.
    /// </summary>
    /// <param name="index">The control index.</param>
    /// <param name="width">The UI width.</param>
    /// <returns>The control bounds.</returns>
    internal static SDL.FRect Button(int index, int width)
    {
        int columns = Math.Max(1, width / 106);
        return new()
        {
            X = 6 + index % columns * 106,
            Y = 6 + index / columns * 30,
            W = 100,
            H = 26
        };
    }

    /// <summary>
    ///  Wraps debug-font text to the available width without losing long paths.
    /// </summary>
    /// <param name="text">The text, including explicit line breaks.</param>
    /// <param name="width">The available UI width.</param>
    /// <returns>The display lines.</returns>
    internal static string[] WrapText(string text, int width)
    {
        int columns = Math.Max(1, width / 8);
        List<string> lines = [];
        foreach (string paragraph in text.Split('\n'))
        {
            string remaining = paragraph;
            while (remaining.Length > columns)
            {
                int split = remaining.LastIndexOf(' ', columns, columns);
                if (split <= 0) { split = columns; }
                lines.Add(remaining[..split]);
                remaining = remaining[split..].TrimStart(' ');
            }

            lines.Add(remaining);
        }

        return [.. lines];
    }

    /// <summary>
    ///  Fits the screen between the emulator controls and status area.
    /// </summary>
    /// <param name="width">The logical window width.</param>
    /// <param name="height">The logical window height.</param>
    /// <param name="toolbarHeight">The height reserved for current emulator controls.</param>
    /// <param name="statusHeight">The height reserved for live status.</param>
    /// <returns>The image destination.</returns>
    internal static SDL.FRect Screen(int width, int height, int toolbarHeight = 72, int statusHeight = 48)
    {
        float availableWidth = Math.Max(1, width - 16);
        float availableHeight = Math.Max(1, height - toolbarHeight - statusHeight);
        float screenWidth = Math.Min(availableWidth, availableHeight * (280f / 192));
        float screenHeight = screenWidth * (192f / 280);

        return new()
        {
            X = (width - screenWidth) / 2,
            Y = toolbarHeight + (availableHeight - screenHeight) / 2,
            W = screenWidth,
            H = screenHeight
        };
    }
}
