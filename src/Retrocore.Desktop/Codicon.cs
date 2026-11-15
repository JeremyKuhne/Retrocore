// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Shapes;
using Avalonia.Layout;
using Avalonia.Media;
using Path = Avalonia.Controls.Shapes.Path;

namespace Retrocore.Desktop;

/// <summary>
///  VS Code's icons, from its Codicon font, by the names the extension gives its views' icons, such as
///  <c>circuit-board</c>.
/// </summary>
internal static class Codicon
{
    private static readonly FontFamily s_font = new("avares://retrocore-desktop/Assets#codicon");

    private static readonly Dictionary<string, char> s_glyphs = new()
    {
        ["add"] = '\uEA60',
        ["arrow-swap"] = '\uEBCB',
        ["check"] = '\uEAB2',
        ["chevron-down"] = '\uEAB4',
        ["chevron-right"] = '\uEAB6',
        ["chip"] = '\uEC19',
        ["circle-outline"] = '\uEABC',
        ["circuit-board"] = '\uEABE',
        ["close"] = '\uEA76',
        ["database"] = '\uEACE',
        ["debug-restart"] = '\uEAD2',
        ["debug-stop"] = '\uEAD7',
        ["device-desktop"] = '\uEA7A',
        ["ellipsis"] = '\uEA7C',
        ["error"] = '\uEA87',
        ["extensions"] = '\uEAE6',
        ["file-binary"] = '\uEAE8',
        ["file-code"] = '\uEAE9',
        ["game"] = '\uEC17',
        ["history"] = '\uEA82',
        ["info"] = '\uEA74',
        ["keyboard"] = '\uEA65',
        ["lock"] = '\uEA75',
        ["play"] = '\uEB2C',
        ["plug"] = '\uEB2D',
        ["record"] = '\uEBA7',
        ["record-keys"] = '\uEA65',
        ["refresh"] = '\uEB37',
        ["save"] = '\uEB4B',
        ["save-as"] = '\uEB4A',
        ["server"] = '\uEB50',
        ["settings-gear"] = '\uEB51',
        ["trash"] = '\uEA81',
        ["zoom-in"] = '\uEB81',
        ["zoom-out"] = '\uEB82',
        ["unlock"] = '\uEB74',
        ["warning"] = '\uEA6C',
    };

    // VS Code has no eject icon, so the extension's Eject shows none there; here it is drawn in the Codicons' style,
    // a triangle over a bar, on their 16 by 16 grid.
    private const string EjectPath = "M8,2.5 L13.5,9 H2.5 Z M2.5,11 H13.5 V13 H2.5 Z";

    /// <summary>
    ///  Gets whether there is an icon of a name.
    /// </summary>
    /// <param name="name">The icon's name, such as <c>save</c>.</param>
    /// <returns>True when <see cref="Create"/> draws it.</returns>
    internal static bool Has(string name) => name == "eject" || s_glyphs.ContainsKey(name);

    /// <summary>
    ///  Creates an icon, coloured from the theme or with a colour of its own.
    /// </summary>
    /// <param name="name">The icon's name, such as <c>save</c>.</param>
    /// <param name="colour">The theme resource it is coloured from, such as <see cref="Palette.Icon"/>.</param>
    /// <param name="size">Its size, 16 as in VS Code's trees.</param>
    /// <returns>The icon.</returns>
    internal static Control Create(string name, string colour = Palette.Icon, double size = 16)
    {
        if (name == "eject")
        {
            Path eject = new()
            {
                Data = StreamGeometry.Parse(EjectPath),
                Width = size,
                Height = size,
                Stretch = Stretch.None,
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center,
                RenderTransform = size == 16 ? null : new ScaleTransform(size / 16, size / 16),
            };

            return eject.Themed(Shape.FillProperty, colour);
        }

        return new TextBlock
        {
            Text = s_glyphs.TryGetValue(name, out char glyph) ? glyph.ToString() : "",
            FontFamily = s_font,
            FontSize = size,
            LineHeight = size,
            Width = size,
            Height = size,
            TextAlignment = TextAlignment.Center,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
            IsHitTestVisible = false,
        }.Themed(TextBlock.ForegroundProperty, colour);
    }

    /// <summary>
    ///  Recolours an icon <see cref="Create"/> made.
    /// </summary>
    /// <param name="icon">The icon.</param>
    /// <param name="colour">The theme resource it is coloured from.</param>
    internal static void Recolour(Control icon, string colour)
    {
        if (icon is Path path)
        {
            path.Themed(Shape.FillProperty, colour);
        }
        else
        {
            icon.Themed(TextBlock.ForegroundProperty, colour);
        }
    }

    /// <summary>
    ///  The space an icon takes beside a label, as in VS Code's trees.
    /// </summary>
    internal static Thickness Gap => new(0, 0, 6, 0);
}