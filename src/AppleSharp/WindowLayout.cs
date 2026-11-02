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
