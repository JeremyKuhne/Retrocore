// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Avalonia;
using Avalonia.Automation;
using Avalonia.Controls;
using Avalonia.Layout;

namespace Retrocore.Desktop;

/// <summary>
///  The rows of options in Display and Sound and in Settings: a label, then a control at the same edge in every row,
///  drawn at VS Code's sizes, 26 pixels tall with 13 pixel text.
/// </summary>
internal static class Options
{
    /// <summary>
    ///  The drop-downs' and sliders' width, the same in every row so the column lines up.
    /// </summary>
    internal const double Width = 200;

    /// <summary>
    ///  Makes a drop-down.
    /// </summary>
    /// <param name="items">Its items.</param>
    /// <param name="selected">The one selected.</param>
    /// <returns>The drop-down.</returns>
    internal static ComboBox Choice(string[] items, int selected) => new()
    {
        ItemsSource = items,
        SelectedIndex = selected,
        Width = Width,
        MinHeight = 26,
        Height = 26,
        Padding = new Thickness(6, 0, 0, 0),
        FontSize = 13,
        CornerRadius = new CornerRadius(2),
        VerticalContentAlignment = VerticalAlignment.Center,
    };

    /// <summary>
    ///  Makes a row: the option's name and its control.
    /// </summary>
    /// <param name="name">The option's name.</param>
    /// <param name="control">Its control.</param>
    /// <param name="tooltip">What it does, or null.</param>
    /// <returns>The row.</returns>
    internal static Grid Row(string name, Control control, string? tooltip = null)
    {
        control.HorizontalAlignment = HorizontalAlignment.Left;
        control.VerticalAlignment = VerticalAlignment.Center;
        if (tooltip is not null) { ToolTip.SetTip(control, tooltip); }

        // The label beside it is visual only, so the control carries its name for a screen reader.
        if (AutomationProperties.GetName(control) is null) { AutomationProperties.SetName(control, name); }
        TextBlock label = new TextBlock
        {
            Text = name,
            FontSize = 13,
            VerticalAlignment = VerticalAlignment.Center,
        }.Themed(TextBlock.ForegroundProperty, Palette.Text);

        Grid.SetColumn(control, 1);
        return new Grid
        {
            ColumnDefinitions = [new ColumnDefinition(new GridLength(90)), new ColumnDefinition(GridLength.Star)],
            Margin = new Thickness(20, 3, 12, 3),
            MinHeight = 26,
            Children = { label, control },
        };
    }
}