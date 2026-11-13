// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug;

/// <summary>
///  The monitors a machine's video can be shown on, by the names the launch's <c>screen</c> option and the
///  <c>retro/screen</c> request take.
/// </summary>
internal static class DebugScreens
{
    /// <summary>
    ///  A color monitor or television.
    /// </summary>
    internal const string Color = "color";

    /// <summary>
    ///  A black and white monochrome monitor.
    /// </summary>
    internal const string White = "white";

    /// <summary>
    ///  A green-phosphor monochrome monitor.
    /// </summary>
    internal const string Green = "green";

    /// <summary>
    ///  An amber-phosphor monochrome monitor.
    /// </summary>
    internal const string Amber = "amber";

    /// <summary>
    ///  Gets the monitors of a machine with color video, color first.
    /// </summary>
    internal static IReadOnlyList<string> WithColor { get; } = [Color, White, Green, Amber];

    /// <summary>
    ///  Gets the monitors of a machine whose video has no color, green first, as its default.
    /// </summary>
    internal static IReadOnlyList<string> Monochrome { get; } = [Green, White, Amber];

    /// <summary>
    ///  Checks that a machine can be shown on a monitor.
    /// </summary>
    /// <param name="screen">The monitor's name.</param>
    /// <param name="screens">The machine's monitors.</param>
    /// <returns>The monitor's name.</returns>
    /// <exception cref="ArgumentException">The machine has no such monitor.</exception>
    internal static string Require(string screen, IReadOnlyList<string> screens) => screens.Contains(screen)
        ? screen
        : throw new ArgumentException($"screen must be {string.Join(", ", screens.SkipLast(1))} or {screens[^1]} on this machine.");

    /// <summary>
    ///  Shows RGBA video on a monochrome monitor: each pixel lit in the phosphor's color by its brightness, so
    ///  white at the machines' 240 lights the phosphor fully. A color monitor leaves the pixels as they are.
    /// </summary>
    /// <param name="rgba">The pixels, changed in place.</param>
    /// <param name="screen">The monitor.</param>
    internal static void Show(Span<byte> rgba, string screen)
    {
        // The phosphors the Apple II's monochrome video draws in.
        (int red, int green, int blue) = screen switch
        {
            White => (240, 240, 240),
            Green => (51, 255, 102),
            Amber => (255, 176, 0),
            _ => (-1, -1, -1)
        };

        if (red < 0) { return; }

        for (int i = 0; i + 3 < rgba.Length; i += 4)
        {
            // Rec. 601 luma, in thousandths, scaled so the machines' white (240) is full brightness.
            int luma = (299 * rgba[i]) + (587 * rgba[i + 1]) + (114 * rgba[i + 2]);
            rgba[i] = Lit(red, luma);
            rgba[i + 1] = Lit(green, luma);
            rgba[i + 2] = Lit(blue, luma);
        }
    }

    private static byte Lit(int phosphor, int luma) => (byte)Math.Min(255, phosphor * luma / 240_000);
}
