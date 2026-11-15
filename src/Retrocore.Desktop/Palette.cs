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
/// <remarks>
///  <para>
///   Each colour is the theme's own where it sets one, and VS Code's default for the colour where it leaves it out,
///   as the editor resolves them. Avalonia's Fluent controls take the same colours through their own resources.
///  </para>
/// </remarks>
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
    ///  The side pane's background, drawn at the pane's opacity setting, since the pane opens over the machine's screen.
    /// </summary>
    internal const string SideBar = "Retrocore.SideBar";

    /// <summary>
    ///  Text.
    /// </summary>
    internal const string Text = "Retrocore.Text";

    /// <summary>
    ///  Text that says less: a row's description, hints.
    /// </summary>
    internal const string Dim = "Retrocore.Dim";

    /// <summary>
    ///  Icons.
    /// </summary>
    internal const string Icon = "Retrocore.Icon";

    /// <summary>
    ///  Text and icons of what is not there or cannot be used, such as an empty slot.
    /// </summary>
    internal const string Disabled = "Retrocore.Disabled";

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
    ///  A status bar item under the pointer.
    /// </summary>
    internal const string StatusHover = "Retrocore.StatusHover";

    /// <summary>
    ///  The lines between the bars and the pane, and between its sections.
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
    ///  A drive seeking, and warnings.
    /// </summary>
    internal const string Seeking = "Retrocore.Seeking";

    /// <summary>
    ///  Errors.
    /// </summary>
    internal const string Error = "Retrocore.Error";

    /// <summary>
    ///  A list row under the pointer.
    /// </summary>
    internal const string ListHover = "Retrocore.ListHover";

    /// <summary>
    ///  The selected list row while its list has the keyboard.
    /// </summary>
    internal const string ListSelection = "Retrocore.ListSelection";

    /// <summary>
    ///  The selected list row's text while its list has the keyboard.
    /// </summary>
    internal const string ListSelectionText = "Retrocore.ListSelectionText";

    /// <summary>
    ///  The selected list row while its list does not have the keyboard.
    /// </summary>
    internal const string ListInactiveSelection = "Retrocore.ListInactiveSelection";

    /// <summary>
    ///  The outline of what has the keyboard.
    /// </summary>
    internal const string Focus = "Retrocore.Focus";

    /// <summary>
    ///  A count beside a section's title.
    /// </summary>
    internal const string Badge = "Retrocore.Badge";

    /// <summary>
    ///  A count's text.
    /// </summary>
    internal const string BadgeText = "Retrocore.BadgeText";

    /// <summary>
    ///  An icon button under the pointer, such as a row's inline action.
    /// </summary>
    internal const string ToolbarHover = "Retrocore.ToolbarHover";

    /// <summary>
    ///  The quick pick's and dialogs' background.
    /// </summary>
    internal const string Widget = "Retrocore.Widget";

    /// <summary>
    ///  Their border.
    /// </summary>
    internal const string WidgetBorder = "Retrocore.WidgetBorder";

    /// <summary>
    ///  Their shadow.
    /// </summary>
    internal const string WidgetShadow = "Retrocore.WidgetShadow";

    /// <summary>
    ///  A text box's background.
    /// </summary>
    internal const string Input = "Retrocore.Input";

    /// <summary>
    ///  A text box's border.
    /// </summary>
    internal const string InputBorder = "Retrocore.InputBorder";

    /// <summary>
    ///  A text box's placeholder.
    /// </summary>
    internal const string InputPlaceholder = "Retrocore.InputPlaceholder";

    /// <summary>
    ///  A primary button's background.
    /// </summary>
    internal const string Button = "Retrocore.Button";

    /// <summary>
    ///  A primary button's text.
    /// </summary>
    internal const string ButtonText = "Retrocore.ButtonText";

    /// <summary>
    ///  A primary button under the pointer.
    /// </summary>
    internal const string ButtonHover = "Retrocore.ButtonHover";

    /// <summary>
    ///  A secondary button's background.
    /// </summary>
    internal const string SecondaryButton = "Retrocore.SecondaryButton";

    /// <summary>
    ///  A secondary button's text.
    /// </summary>
    internal const string SecondaryButtonText = "Retrocore.SecondaryButtonText";

    /// <summary>
    ///  A secondary button under the pointer.
    /// </summary>
    internal const string SecondaryButtonHover = "Retrocore.SecondaryButtonHover";

    /// <summary>
    ///  A button's border.
    /// </summary>
    internal const string ButtonBorder = "Retrocore.ButtonBorder";

    /// <summary>
    ///  A hover's background, as VS Code draws a tooltip.
    /// </summary>
    internal const string Hover = "Retrocore.Hover";

    /// <summary>
    ///  A hover's border.
    /// </summary>
    internal const string HoverBorder = "Retrocore.HoverBorder";

    /// <summary>
    ///  A menu's background.
    /// </summary>
    internal const string Menu = "Retrocore.Menu";

    /// <summary>
    ///  A menu's border.
    /// </summary>
    internal const string MenuBorder = "Retrocore.MenuBorder";

    /// <summary>
    ///  A menu's selected item.
    /// </summary>
    internal const string MenuSelection = "Retrocore.MenuSelection";

    /// <summary>
    ///  A menu's selected item's text.
    /// </summary>
    internal const string MenuSelectionText = "Retrocore.MenuSelectionText";

    /// <summary>
    ///  A drop-down's background.
    /// </summary>
    internal const string Dropdown = "Retrocore.Dropdown";

    /// <summary>
    ///  A drop-down's border.
    /// </summary>
    internal const string DropdownBorder = "Retrocore.DropdownBorder";

    /// <summary>
    ///  A drop-down's list.
    /// </summary>
    internal const string DropdownList = "Retrocore.DropdownList";

    /// <summary>
    ///  A check box's background.
    /// </summary>
    internal const string Checkbox = "Retrocore.Checkbox";

    /// <summary>
    ///  A check box's border.
    /// </summary>
    internal const string CheckboxBorder = "Retrocore.CheckboxBorder";

    /// <summary>
    ///  A quick pick's separator labels, as VS Code's pickerGroup.foreground.
    /// </summary>
    internal const string PickerGroup = "Retrocore.PickerGroup";

    // Each colour in Dark Modern and Light Modern.
    private static readonly (string Key, string Dark, string Light)[] s_colours =
    [
        (ActivityBar, "#181818", "#F8F8F8"),
        (ActivityActive, "#D7D7D7", "#1F1F1F"),
        (ActivityInactive, "#868686", "#616161"),
        (ActivityBorder, "#0078D4", "#005FB8"),
        (SideBar, "#181818", "#F8F8F8"),
        (Text, "#CCCCCC", "#3B3B3B"),
        (Dim, "#9D9D9D", "#717171"),
        (Icon, "#CCCCCC", "#3B3B3B"),
        (Disabled, "#CCCCCC80", "#61616180"),
        (Editor, "#1F1F1F", "#FFFFFF"),
        (StatusBar, "#181818", "#F8F8F8"),
        (StatusText, "#CCCCCC", "#3B3B3B"),
        (StatusHover, "#F1F1F133", "#1F1F1F11"),
        (Border, "#2B2B2B", "#E5E5E5"),
        (Reading, "#89D185", "#388A34"),
        (Writing, "#F14C4C", "#E51400"),
        (Seeking, "#CCA700", "#BF8803"),
        (Error, "#F85149", "#E51400"),
        (ListHover, "#2A2D2E", "#F2F2F2"),
        (ListSelection, "#04395E", "#E8E8E8"),
        (ListSelectionText, "#FFFFFF", "#000000"),
        (ListInactiveSelection, "#37373D", "#E4E6F1"),
        (Focus, "#0078D4", "#005FB8"),
        (Badge, "#616161", "#CCCCCC"),
        (BadgeText, "#F8F8F8", "#3B3B3B"),
        (ToolbarHover, "#5A5D5E50", "#B8B8B850"),
        (Widget, "#222222", "#F8F8F8"),
        (WidgetBorder, "#313131", "#E5E5E5"),
        (WidgetShadow, "#0000005C", "#00000029"),
        (Input, "#313131", "#FFFFFF"),
        (InputBorder, "#3C3C3C", "#CECECE"),
        (InputPlaceholder, "#989898", "#767676"),
        (Button, "#0078D4", "#005FB8"),
        (ButtonText, "#FFFFFF", "#FFFFFF"),
        (ButtonHover, "#026EC1", "#0258A8"),
        (SecondaryButton, "#313131", "#E5E5E5"),
        (SecondaryButtonText, "#CCCCCC", "#3B3B3B"),
        (SecondaryButtonHover, "#3C3C3C", "#CCCCCC"),
        (ButtonBorder, "#FFFFFF1A", "#0000001A"),
        (Hover, "#202020", "#F8F8F8"),
        (HoverBorder, "#454545", "#C8C8C8"),
        (Menu, "#1F1F1F", "#FFFFFF"),
        (MenuBorder, "#454545", "#CECECE"),
        (MenuSelection, "#0078D4", "#005FB8"),
        (MenuSelectionText, "#FFFFFF", "#FFFFFF"),
        (Dropdown, "#313131", "#FFFFFF"),
        (DropdownBorder, "#3C3C3C", "#CECECE"),
        (DropdownList, "#1F1F1F", "#FFFFFF"),
        (Checkbox, "#313131", "#F8F8F8"),
        (CheckboxBorder, "#3C3C3C", "#CECECE"),
        (PickerGroup, "#3794FF", "#8B949E"),
        (MachineIcon.Frame, "#C5C5C5", "#424242"),
    ];

    // Avalonia's Fluent controls' own resources, given VS Code's colours: the drop-downs, check boxes, sliders, menus
    // and tooltips. Each is the palette colour it takes.
    private static readonly (string Fluent, string Ours)[] s_fluent =
    [
        ("ComboBoxBackground", Dropdown),
        ("ComboBoxBackgroundPointerOver", Dropdown),
        ("ComboBoxBackgroundPressed", Dropdown),
        ("ComboBoxBackgroundFocused", Dropdown),
        ("ComboBoxBorderBrush", DropdownBorder),
        ("ComboBoxBorderBrushPointerOver", DropdownBorder),
        ("ComboBoxBorderBrushPressed", Focus),
        ("ComboBoxForeground", Text),
        ("ComboBoxForegroundPointerOver", Text),
        ("ComboBoxDropDownBackground", DropdownList),
        ("ComboBoxDropDownBorderBrush", Focus),
        ("ComboBoxDropDownForeground", Text),
        ("ComboBoxDropDownGlyphForeground", Icon),
        ("ComboBoxItemBackgroundPointerOver", ListHover),
        ("ComboBoxItemBackgroundSelected", ListSelection),
        ("ComboBoxItemBackgroundSelectedPointerOver", ListSelection),
        ("ComboBoxItemForegroundSelected", ListSelectionText),
        ("ComboBoxItemForegroundSelectedPointerOver", ListSelectionText),
        ("CheckBoxCheckBackgroundFillUnchecked", Checkbox),
        ("CheckBoxCheckBackgroundFillUncheckedPointerOver", Checkbox),
        ("CheckBoxCheckBackgroundStrokeUnchecked", CheckboxBorder),
        ("CheckBoxCheckBackgroundStrokeUncheckedPointerOver", CheckboxBorder),
        ("CheckBoxCheckBackgroundFillChecked", Checkbox),
        ("CheckBoxCheckBackgroundFillCheckedPointerOver", Checkbox),
        ("CheckBoxCheckBackgroundStrokeChecked", CheckboxBorder),
        ("CheckBoxCheckBackgroundStrokeCheckedPointerOver", CheckboxBorder),
        ("CheckBoxCheckGlyphForegroundChecked", Text),
        ("CheckBoxCheckGlyphForegroundCheckedPointerOver", Text),
        ("CheckBoxForegroundUnchecked", Text),
        ("CheckBoxForegroundChecked", Text),
        ("ToolTipBackground", Hover),
        ("ToolTipBorderBrush", HoverBorder),
        ("ToolTipForeground", Text),
        ("MenuFlyoutPresenterBackground", Menu),
        ("MenuFlyoutPresenterBorderBrush", MenuBorder),
        ("MenuFlyoutItemForeground", Text),
        ("MenuFlyoutItemBackgroundPointerOver", MenuSelection),
        ("MenuFlyoutItemForegroundPointerOver", MenuSelectionText),
        ("MenuFlyoutItemBackgroundPressed", MenuSelection),
        ("MenuFlyoutItemForegroundPressed", MenuSelectionText),
        ("MenuFlyoutSeparatorBackground", MenuBorder),
        ("SliderTrackValueFill", Button),
        ("SliderTrackValueFillPointerOver", ButtonHover),
        ("SliderTrackValueFillPressed", Button),
        ("SliderThumbBackground", Button),
        ("SliderThumbBackgroundPointerOver", ButtonHover),
        ("SliderThumbBackgroundPressed", Button),
        ("SliderTrackFill", InputBorder),
        ("SliderTrackFillPointerOver", InputBorder),
        ("SliderTrackFillPressed", InputBorder),
        ("TextControlBackground", Input),
        ("TextControlBackgroundPointerOver", Input),
        ("TextControlBackgroundFocused", Input),
        ("TextControlBorderBrush", InputBorder),
        ("TextControlBorderBrushPointerOver", InputBorder),
        ("TextControlBorderBrushFocused", Focus),
        ("TextControlForeground", Text),
        ("TextControlForegroundPointerOver", Text),
        ("TextControlForegroundFocused", Text),
        ("TextControlPlaceholderForeground", InputPlaceholder),
        ("TextControlPlaceholderForegroundPointerOver", InputPlaceholder),
        ("TextControlPlaceholderForegroundFocused", InputPlaceholder),
    ];

    /// <summary>
    ///  Adds the colours to an application, one set for each theme variant.
    /// </summary>
    /// <param name="application">The application.</param>
    internal static void Install(Application application)
    {
        application.Resources.ThemeDictionaries[ThemeVariant.Dark] = Colours(dark: true);
        application.Resources.ThemeDictionaries[ThemeVariant.Light] = Colours(dark: false);
    }

    private static ResourceDictionary Colours(bool dark)
    {
        ResourceDictionary resources = [];
        Dictionary<string, SolidColorBrush> brushes = [];
        foreach ((string key, string darkColour, string lightColour) in s_colours)
        {
            SolidColorBrush brush = Brush(dark ? darkColour : lightColour);
            brushes[key] = brush;
            resources[key] = brush;
        }

        foreach ((string fluent, string ours) in s_fluent)
        {
            resources[fluent] = brushes[ours];
        }

        // Fluent's accent, which its controls' focus and checked states take, is VS Code's blue.
        resources["SystemAccentColor"] = brushes[Focus].Color;
        return resources;
    }

    // VS Code writes a colour with alpha as #RRGGBBAA; Avalonia reads #AARRGGBB, so the alpha moves to the front.
    private static SolidColorBrush Brush(string colour) => new(Color.Parse(colour.Length == 9 ? $"#{colour[7..]}{colour[1..7]}" : colour));

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