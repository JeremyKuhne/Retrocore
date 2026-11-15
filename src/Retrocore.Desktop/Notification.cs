// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Avalonia;
using Avalonia.Automation;
using Avalonia.Controls;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Threading;

namespace Retrocore.Desktop;

/// <summary>
///  VS Code's notifications: a toast at the bottom right of the window with an icon, the message and a close button,
///  as its error, warning and information messages show. An information message closes by itself after a while.
/// </summary>
internal static class Notification
{
    /// <summary>
    ///  Shows a notification.
    /// </summary>
    /// <param name="layer">The window's notification layer, a panel at its bottom right.</param>
    /// <param name="message">The message.</param>
    /// <param name="icon"><c>error</c>, <c>warning</c> or <c>info</c>.</param>
    internal static void Show(StackPanel layer, string message, string icon = "error")
    {
        Control glyph = Codicon.Create(icon, icon == "error" ? Palette.Error : icon == "warning" ? Palette.Seeking : Palette.Focus);
        glyph.VerticalAlignment = VerticalAlignment.Top;
        glyph.Margin = new Thickness(0, 1, 8, 0);
        FlatButton close = FlatButton.Icon("close", "Clear Notification");
        close.VerticalAlignment = VerticalAlignment.Top;

        TextBlock text = new TextBlock
        {
            Text = message,
            TextWrapping = TextWrapping.Wrap,
            FontSize = 13,
            VerticalAlignment = VerticalAlignment.Center,
        }.Themed(TextBlock.ForegroundProperty, Palette.Text);

        DockPanel row = new();
        DockPanel.SetDock(glyph, Dock.Left);
        DockPanel.SetDock(close, Dock.Right);
        row.Children.Add(glyph);
        row.Children.Add(close);
        row.Children.Add(text);

        Border toast = new Border
        {
            Width = 450,
            Padding = new Thickness(12, 10, 6, 10),
            Margin = new Thickness(0, 6, 0, 0),
            CornerRadius = new CornerRadius(4),
            BorderThickness = new Thickness(1),
            BoxShadow = BoxShadows.Parse("0 0 8 0 #5C000000"),
            Child = row,
        }.Themed(Border.BackgroundProperty, Palette.Widget).Themed(Border.BorderBrushProperty, Palette.WidgetBorder);

        AutomationProperties.SetName(toast, message);
        AutomationProperties.SetLiveSetting(toast, AutomationLiveSetting.Assertive);
        close.Click += (_, _) => layer.Children.Remove(toast);
        layer.Children.Add(toast);

        // At most three at once, the oldest going first, as VS Code stacks its own.
        while (layer.Children.Count > 3) { layer.Children.RemoveAt(0); }
        if (icon == "info")
        {
            DispatcherTimer.RunOnce(() => layer.Children.Remove(toast), TimeSpan.FromSeconds(10));
        }
    }
}