// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Avalonia;
using Avalonia.Automation;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Layout;
using Avalonia.LogicalTree;
using Avalonia.Media;
using Avalonia.Threading;

namespace Retrocore.Desktop;

/// <summary>
///  VS Code's quick pick: a box at the top of the window with a title, a filter and a list, which the keyboard or the
///  pointer picks from and Escape or a click outside it dismisses.
/// </summary>
internal static class QuickPick
{
    // VS Code's quick input is 600 pixels wide in a window that has room, and lists about twenty rows before scrolling.
    private const double Width = 600;
    private const double ListHeight = 440;

    /// <summary>
    ///  Shows a quick pick and waits for a choice.
    /// </summary>
    /// <typeparam name="T">What an item gives.</typeparam>
    /// <param name="layer">The window's overlay layer.</param>
    /// <param name="items">The items, separators among them.</param>
    /// <param name="title">The title, or null.</param>
    /// <param name="placeholder">The filter's placeholder.</param>
    /// <returns>The item picked, or null when dismissed.</returns>
    internal static Task<QuickPickItem<T>?> Show<T>(Panel layer, IReadOnlyList<QuickPickItem<T>> items, string? title, string placeholder)
    {
        TaskCompletionSource<QuickPickItem<T>?> done = new();
        IInputElement? before = TopLevel.GetTopLevel(layer)?.FocusManager?.GetFocusedElement();

        // A click outside the box dismisses it, as VS Code's does.
        Border shade = new() { Background = Brushes.Transparent };
        TextBox filter = new()
        {
            PlaceholderText = placeholder,
            FontSize = 13,
            MinHeight = 26,
            Height = 26,
            Padding = new Thickness(6, 3),
            CornerRadius = new CornerRadius(2),
            BorderThickness = new Thickness(1),
            Margin = new Thickness(6, title is null ? 6 : 0, 6, 6),
            VerticalContentAlignment = VerticalAlignment.Center,
        };

        AutomationProperties.SetName(filter, title ?? placeholder);
        StackPanel list = new();
        ScrollViewer scroller = new()
        {
            MaxHeight = ListHeight,
            Content = list,
            HorizontalScrollBarVisibility = Avalonia.Controls.Primitives.ScrollBarVisibility.Disabled
        };

        StackPanel box = new();
        if (title is not null)
        {
            box.Children.Add(new TextBlock
            {
                Text = title,
                FontSize = 13,
                HorizontalAlignment = HorizontalAlignment.Center,
                Margin = new Thickness(0, 6, 0, 6),
            }.Themed(TextBlock.ForegroundProperty, Palette.Text));
        }

        box.Children.Add(filter);
        box.Children.Add(scroller);

        Border frame = new Border
        {
            Width = Width,
            MaxWidth = Math.Max(200, layer.Bounds.Width - 32),
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Top,
            Margin = new Thickness(0, 8, 0, 0),
            CornerRadius = new CornerRadius(6),
            BorderThickness = new Thickness(1),
            Padding = new Thickness(0, 0, 0, 6),
            BoxShadow = BoxShadows.Parse("0 0 8 0 #5C000000"),
            Child = box,
            ClipToBounds = true,
        }.Themed(Border.BackgroundProperty, Palette.Widget).Themed(Border.BorderBrushProperty, Palette.WidgetBorder);

        Grid host = new() { Children = { shade, frame } };
        layer.Children.Add(host);

        List<(QuickPickItem<T> Item, Border Row)> shown = [];
        int focused = -1;

        void Close(QuickPickItem<T>? picked)
        {
            if (done.Task.IsCompleted) { return; }
            layer.Children.Remove(host);
            before?.Focus();
            done.SetResult(picked);
        }

        void Paint()
        {
            for (int index = 0; index < shown.Count; index++)
            {
                (QuickPickItem<T> item, Border row) = shown[index];
                if (item.Separator) { continue; }
                bool on = index == focused;
                if (on)
                {
                    row.Themed(Border.BackgroundProperty, Palette.ListSelection);
                }
                else if (row.IsPointerOver)
                {
                    row.Themed(Border.BackgroundProperty, Palette.ListHover);
                }
                else
                {
                    row.Background = Brushes.Transparent;
                }

                foreach (TextBlock text in row.GetLogicalDescendants().OfType<TextBlock>())
                {
                    text.Themed(TextBlock.ForegroundProperty, on ? Palette.ListSelectionText : Palette.Text);
                }
            }
        }

        void Focus(int index)
        {
            if (shown.Count == 0) { return; }
            index = Math.Clamp(index, 0, shown.Count - 1);
            focused = index;
            Paint();
            shown[index].Row.BringIntoView();
        }

        void Move(int step)
        {
            // A filter that matches nothing leaves nothing to move to.
            if (shown.Count == 0) { return; }
            int index = focused;
            for (int moved = 0; moved < shown.Count; moved++)
            {
                index = Math.Clamp(index + Math.Sign(step), 0, shown.Count - 1);
                if (!shown[index].Item.Separator) { break; }
            }

            if (!shown[index].Item.Separator) { Focus(index); }
        }

        void Fill()
        {
            string query = filter.Text?.Trim() ?? "";
            list.Children.Clear();
            shown.Clear();
            bool Matches(QuickPickItem<T> item) => query.Length == 0
                || item.Label.Contains(query, StringComparison.CurrentCultureIgnoreCase)
                || (item.Description?.Contains(query, StringComparison.CurrentCultureIgnoreCase) ?? false)
                || (item.Detail?.Contains(query, StringComparison.CurrentCultureIgnoreCase) ?? false);

            // A separator shows while any item under it matches; while filtering, VS Code leaves them out.
            for (int index = 0; index < items.Count; index++)
            {
                QuickPickItem<T> item = items[index];
                if (item.Separator)
                {
                    if (query.Length != 0) { continue; }
                    bool any = items.Skip(index + 1).TakeWhile(next => !next.Separator).Any(Matches);
                    if (!any) { continue; }
                }
                else if (!Matches(item))
                {
                    continue;
                }

                Border row = Row(item, first: shown.Count == 0);
                int at = shown.Count;
                shown.Add((item, row));
                list.Children.Add(row);
                if (item.Separator) { continue; }
                row.PointerEntered += (_, _) => Paint();
                row.PointerExited += (_, _) => Paint();
                row.PointerPressed += (_, e) =>
                {
                    if (!e.GetCurrentPoint(row).Properties.IsLeftButtonPressed) { return; }
                    e.Handled = true;
                    Close(item);
                };
            }

            focused = -1;
            int start = query.Length == 0 ? shown.FindIndex(entry => entry.Item.Picked) : -1;
            if (start < 0) { start = shown.FindIndex(entry => !entry.Item.Separator); }
            if (start >= 0) { Focus(start); }
        }

        filter.TextChanged += (_, _) => Fill();
        filter.KeyDown += (_, e) =>
        {
            switch (e.Key)
            {
                case Key.Down:
                    Move(1);
                    break;
                case Key.Up:
                    Move(-1);
                    break;
                case Key.PageDown:
                    for (int step = 0; step < 10; step++) { Move(1); }
                    break;
                case Key.PageUp:
                    for (int step = 0; step < 10; step++) { Move(-1); }
                    break;
                case Key.Enter:
                    if (focused >= 0 && !shown[focused].Item.Separator) { Close(shown[focused].Item); }
                    break;
                case Key.Escape:
                    Close(picked: null);
                    break;
                default:
                    return;
            }

            e.Handled = true;
        };

        shade.PointerPressed += (_, e) =>
        {
            e.Handled = true;
            Close(picked: null);
        };

        Fill();
        Dispatcher.UIThread.Post(() => filter.Focus(), DispatcherPriority.Input);
        return done.Task;
    }

    // A row: the icon, label and description on one line and the detail under them, or a separator's line and label.
    private static Border Row<T>(QuickPickItem<T> item, bool first)
    {
        if (item.Separator)
        {
            return new Border
            {
                BorderThickness = new Thickness(0, first ? 0 : 1, 0, 0),
                Margin = new Thickness(0, first ? 0 : 2, 0, 0),
                Height = 22,
                Padding = new Thickness(11, 0),
                Child = new TextBlock
                {
                    Text = item.Label,
                    FontSize = 11,
                    HorizontalAlignment = HorizontalAlignment.Right,
                    VerticalAlignment = VerticalAlignment.Center,
                }.Themed(TextBlock.ForegroundProperty, Palette.PickerGroup),
            }.Themed(Border.BorderBrushProperty, Palette.Border);
        }

        StackPanel line = new() { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
        if (item.Icon is { } icon)
        {
            Control glyph = Codicon.Create(icon);
            glyph.Margin = Codicon.Gap;
            line.Children.Add(glyph);
        }

        line.Children.Add(new TextBlock
        {
            Text = item.Label,
            FontSize = 13,
            VerticalAlignment = VerticalAlignment.Center
        });

        if (item.DescriptionIcon is { } marker)
        {
            Control mark = Codicon.Create(marker, Palette.Text, 14);
            mark.Margin = new Thickness(6, 0, 0, 0);
            mark.Opacity = 0.7;
            line.Children.Add(mark);
        }

        if (!string.IsNullOrEmpty(item.Description))
        {
            line.Children.Add(new TextBlock
            {
                Text = item.Description,
                FontSize = 12,
                Opacity = 0.7,
                Margin = new Thickness(6, 0, 0, 0),
                VerticalAlignment = VerticalAlignment.Center,
            });
        }

        StackPanel content = new() { VerticalAlignment = VerticalAlignment.Center, Children = { line } };
        if (!string.IsNullOrEmpty(item.Detail))
        {
            content.Children.Add(new TextBlock
            {
                Text = item.Detail,
                FontSize = 12,
                Opacity = 0.7,
                TextTrimming = TextTrimming.CharacterEllipsis,
            });
        }

        Border row = new()
        {
            Height = string.IsNullOrEmpty(item.Detail) ? 22 : 44,
            Padding = new Thickness(11, 0),
            Margin = new Thickness(6, 0),
            CornerRadius = new CornerRadius(3),
            Background = Brushes.Transparent,
            Child = content,
        };

        AutomationProperties.SetName(row, item.Label);
        return row;
    }
}