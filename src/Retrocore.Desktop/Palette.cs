// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Avalonia;
using Avalonia.Controls;
using Avalonia.Media;
using Avalonia.Styling;

namespace Retrocore.Desktop;

/// <summary>
///  The window's colours: VS Code's Light Modern and Dark Modern themes, as resources that follow the application's
///  theme variant, so every control coloured from them changes when the theme does.
/// </summary>
internal static class Palette
{
    /// <summary>
    ///  The activity bar's background.
    /// </summary>
    internal const string ActivityBar = "Retrocore.ActivityBar";

    /// <summary>
    ///  The active view's icon in the activity bar.
    /// </summary>
    internal const string ActivityActive = "Retrocore.ActivityActive";

    /// <summary>
    ///  The other views' icons in the activity bar.
    /// </summary>
    internal const string ActivityInactive = "Retrocore.ActivityInactive";

    /// <summary>
    ///  The bar beside the active view's icon.
    /// </summary>
    internal const string ActivityBorder = "Retrocore.ActivityBorder";

    /// <summary>
    ///  The side pane's background.
    /// </summary>
    internal const string SideBar = "Retrocore.SideBar";

    /// <summary>
    ///  Text.
    /// </summary>
    internal const string Text = "Retrocore.Text";

    /// <summary>
    ///  Text that says less: values, empty slots and drives.
    /// </summary>
    internal const string Dim = "Retrocore.Dim";

    /// <summary>
    ///  The space around the machine's screen, as an editor's background.
    /// </summary>
    internal const string Editor = "Retrocore.Editor";

    /// <summary>
    ///  The status bar's background.
    /// </summary>
    internal const string StatusBar = "Retrocore.StatusBar";

    /// <summary>
    ///  The status bar's text.
    /// </summary>
    internal const string StatusText = "Retrocore.StatusText";

    /// <summary>
    ///  The lines between the bars and the pane.
    /// </summary>
    internal const string Border = "Retrocore.Border";

    /// <summary>
    ///  A drive reading.
    /// </summary>
    internal const string Reading = "Retrocore.Reading";

    /// <summary>
    ///  A drive writing.
    /// </summary>
    internal const string Writing = "Retrocore.Writing";

    /// <summary>
    ///  A drive seeking.
    /// </summary>
    internal const string Seeking = "Retrocore.Seeking";

    /// <summary>
    ///  Adds the colours to an application, one set for each theme variant.
    /// </summary>
    /// <param name="application">The application.</param>
    internal static void Install(Application application)
    {
        application.Resources.ThemeDictionaries[ThemeVariant.Dark] = Colours(
            activityBar: "#181818", active: "#D7D7D7", inactive: "#868686", border: "#0078D4", sideBar: "#181818",
            text: "#CCCCCC", dim: "#9D9D9D", editor: "#1F1F1F", statusBar: "#181818", statusText: "#CCCCCC",
            line: "#2B2B2B", reading: "#89D185", writing: "#F14C4C", seeking: "#CCA700");

        application.Resources.ThemeDictionaries[ThemeVariant.Light] = Colours(
            activityBar: "#F8F8F8", active: "#1F1F1F", inactive: "#616161", border: "#005FB8", sideBar: "#F8F8F8",
            text: "#3B3B3B", dim: "#717171", editor: "#FFFFFF", statusBar: "#F8F8F8", statusText: "#3B3B3B",
            line: "#E5E5E5", reading: "#388A34", writing: "#E51400", seeking: "#BF8803");
    }

    private static ResourceDictionary Colours(
        string activityBar,
        string active,
        string inactive,
        string border,
        string sideBar,
        string text,
        string dim,
        string editor,
        string statusBar,
        string statusText,
        string line,
        string reading,
        string writing,
        string seeking) => new()
        {
            [ActivityBar] = Brush(activityBar),
            [ActivityActive] = Brush(active),
            [ActivityInactive] = Brush(inactive),
            [ActivityBorder] = Brush(border),
            [SideBar] = Brush(sideBar),
            [Text] = Brush(text),
            [Dim] = Brush(dim),
            [Editor] = Brush(editor),
            [StatusBar] = Brush(statusBar),
            [StatusText] = Brush(statusText),
            [Border] = Brush(line),
            [Reading] = Brush(reading),
            [Writing] = Brush(writing),
            [Seeking] = Brush(seeking),
        };

    private static SolidColorBrush Brush(string colour) => new(Color.Parse(colour));

    /// <summary>
    ///  Colours a property of a control from a theme resource, following the theme as it changes.
    /// </summary>
    /// <typeparam name="T">The control's type.</typeparam>
    /// <param name="control">The control.</param>
    /// <param name="property">The property, such as <see cref="TextBlock.ForegroundProperty"/>.</param>
    /// <param name="key">The resource, such as <see cref="Text"/>.</param>
    /// <returns>The control.</returns>
    internal static T Themed<T>(this T control, AvaloniaProperty property, string key) where T : Control
    {
        control.Bind(property, control.GetResourceObservable(key));
        return control;
    }

    /// <summary>
    ///  Gets the theme variant a setting names.
    /// </summary>
    /// <param name="theme"><c>light</c>, <c>dark</c>, or anything else for the system's.</param>
    /// <returns>The variant; <see cref="ThemeVariant.Default"/> follows the system.</returns>
    internal static ThemeVariant Variant(string theme) => theme switch
    {
        "light" => ThemeVariant.Light,
        "dark" => ThemeVariant.Dark,
        _ => ThemeVariant.Default,
    };
}