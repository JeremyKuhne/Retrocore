// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Avalonia;
using Avalonia.Automation;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Threading;

namespace Retrocore.Desktop;

/// <summary>
///  VS Code's modal dialog, as a warning with <c>modal: true</c> shows one: an icon, the message, and its buttons with
///  Cancel, over the window dimmed.
/// </summary>
internal static class Dialog
{
    /// <summary>
    ///  Asks a question and waits for the answer.
    /// </summary>
    /// <param name="layer">The window's overlay layer.</param>
    /// <param name="message">The question.</param>
    /// <param name="buttons">The answers, the first the default; Cancel is added after them.</param>
    /// <param name="icon">The Codicon, such as <c>warning</c> or <c>error</c>.</param>
    /// <returns>The answer, or null for Cancel.</returns>
    internal static Task<string?> Ask(Panel layer, string message, IReadOnlyList<string> buttons, string icon = "warning")
    {
        TaskCompletionSource<string?> done = new();
        IInputElement? before = TopLevel.GetTopLevel(layer)?.FocusManager?.GetFocusedElement();
        Border shade = new() { Background = new SolidColorBrush(Color.Parse("#4D000000")) };
        StackPanel row = new()
        {
            Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Spacing = 8
        };

        Grid host = new();

        void Close(string? answer)
        {
            if (done.Task.IsCompleted) { return; }
            layer.Children.Remove(host);
            before?.Focus();
            done.SetResult(answer);
        }

        FlatButton? first = null;
        foreach (string answer in buttons)
        {
            FlatButton button = FlatButton.Text(answer, primary: first is null);
            button.Click += (_, _) => Close(answer);
            first ??= button;
            row.Children.Add(button);
        }

        FlatButton cancel = FlatButton.Text("Cancel", primary: false);
        cancel.Click += (_, _) => Close(answer: null);
        row.Children.Add(cancel);

        Control glyph = Codicon.Create(icon, icon == "error" ? Palette.Error : icon == "info" ? Palette.Focus : Palette.Seeking, 32);
        glyph.VerticalAlignment = VerticalAlignment.Top;
        glyph.Margin = new Thickness(0, 0, 12, 0);
        TextBlock text = new TextBlock
        {
            Text = message,
            TextWrapping = TextWrapping.Wrap,
            FontSize = 13,
            FontWeight = FontWeight.SemiBold,
            VerticalAlignment = VerticalAlignment.Center,
        }.Themed(TextBlock.ForegroundProperty, Palette.Text);

        DockPanel body = new() { Margin = new Thickness(0, 0, 0, 16) };
        DockPanel.SetDock(glyph, Dock.Left);
        body.Children.Add(glyph);
        body.Children.Add(text);

        Border box = new Border
        {
            Width = 500,
            MaxWidth = Math.Max(240, layer.Bounds.Width - 32),
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Top,
            Margin = new Thickness(0, Math.Max(16, layer.Bounds.Height * 0.2), 0, 0),
            Padding = new Thickness(20, 20, 20, 16),
            CornerRadius = new CornerRadius(6),
            BorderThickness = new Thickness(1),
            BoxShadow = BoxShadows.Parse("0 0 8 0 #5C000000"),
            Child = new StackPanel { Children = { body, row } },
        }.Themed(Border.BackgroundProperty, Palette.Widget).Themed(Border.BorderBrushProperty, Palette.WidgetBorder);

        AutomationProperties.SetName(box, message);
        host.Children.Add(shade);
        host.Children.Add(box);
        host.KeyDown += (_, e) =>
        {
            if (e.Key == Key.Escape)
            {
                Close(answer: null);
                e.Handled = true;
            }
        };

        layer.Children.Add(host);
        Dispatcher.UIThread.Post(() => first?.Focus(), DispatcherPriority.Input);
        return done.Task;
    }
}