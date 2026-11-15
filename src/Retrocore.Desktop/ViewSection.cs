// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Avalonia;
using Avalonia.Automation;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Layout;
using Avalonia.Media;

namespace Retrocore.Desktop;

/// <summary>
///  A section of the side pane, as VS Code draws a view in its side bar: a header 22 pixels tall with a chevron, the
///  title in capitals, a count of what needs attention, and its actions while the pointer is over it; then a message,
///  when there is one, and the section's contents.
/// </summary>
internal sealed class ViewSection : StackPanel
{
    private readonly Border _header = new() { Height = 22, Background = Brushes.Transparent, Focusable = true };
    private readonly Panel _chevronHolder = new() { Width = 16, Height = 16, Margin = new Thickness(2, 0, 2, 0) };
    private readonly Border _badge = new()
    {
        MinWidth = 18,
        Height = 18,
        CornerRadius = new CornerRadius(11),
        Padding = new Thickness(5, 0),
        Margin = new Thickness(6, 0, 0, 0),
        VerticalAlignment = VerticalAlignment.Center,
        IsVisible = false,
    };

    private readonly TextBlock _badgeText = new()
    {
        FontSize = 11,
        VerticalAlignment = VerticalAlignment.Center,
        HorizontalAlignment = HorizontalAlignment.Center,
    };

    private readonly StackPanel _actions = new()
    {
        Orientation = Orientation.Horizontal, Margin = new Thickness(0, 0, 8, 0)
    };
    private readonly TextBlock _message = new()
    {
        TextWrapping = TextWrapping.Wrap,
        Margin = new Thickness(20, 4, 12, 4),
        FontSize = 13,
        IsVisible = false,
    };

    private readonly Control _content;
    private bool _open;

    /// <summary>
    ///  Creates a section.
    /// </summary>
    /// <param name="title">Its title, such as <c>Machine</c>.</param>
    /// <param name="content">What it shows under its header.</param>
    /// <param name="first">Whether it is the pane's first, which has no line above it.</param>
    internal ViewSection(string title, Control content, bool first = false)
    {
        _content = content;
        _badge.Child = _badgeText;
        _badge.Themed(Border.BackgroundProperty, Palette.Badge);
        _badgeText.Themed(TextBlock.ForegroundProperty, Palette.BadgeText);
        _message.Themed(TextBlock.ForegroundProperty, Palette.Text);

        TextBlock caption = new TextBlock
        {
            Text = title.ToUpperInvariant(),
            FontSize = 11,
            FontWeight = FontWeight.Bold,
            VerticalAlignment = VerticalAlignment.Center,
        }.Themed(TextBlock.ForegroundProperty, Palette.Text);

        DockPanel row = new();
        DockPanel.SetDock(_chevronHolder, Dock.Left);
        DockPanel.SetDock(_actions, Dock.Right);
        row.Children.Add(_chevronHolder);
        row.Children.Add(_actions);
        row.Children.Add(new StackPanel { Orientation = Orientation.Horizontal, Children = { caption, _badge } });

        _header.Child = new Border
        {
            BorderThickness = new Thickness(0, first ? 0 : 1, 0, 0),
            Child = row,
        }.Themed(Border.BorderBrushProperty, Palette.Border);

        AutomationProperties.SetName(_header, title);
        _header.PointerPressed += (_, e) =>
        {
            if (!e.GetCurrentPoint(_header).Properties.IsLeftButtonPressed) { return; }
            _header.Focus(NavigationMethod.Pointer);
            Open = !Open;
        };

        _header.KeyDown += (_, e) =>
        {
            if (e.Key is Key.Enter or Key.Space)
            {
                Open = !Open;
                e.Handled = true;
            }
            else if (e.Key == Key.Right && !Open)
            {
                Open = true;
                e.Handled = true;
            }
            else if (e.Key == Key.Left && Open)
            {
                Open = false;
                e.Handled = true;
            }
        };

        _header.GotFocus += (_, _) => PaintActions();
        _header.LostFocus += (_, _) => PaintActions();
        _header.PointerEntered += (_, _) => PaintActions();
        _header.PointerExited += (_, _) => PaintActions();
        _header.Themed(Border.BorderBrushProperty, Palette.Focus);

        Children.Add(_header);
        Children.Add(_message);
        Children.Add(content);
        Open = true;
        PaintActions();
    }

    /// <summary>
    ///  Gets or sets whether the section is open.
    /// </summary>
    internal bool Open
    {
        get => _open;
        set
        {
            _open = value;
            _content.IsVisible = value;
            _message.IsVisible = value && !string.IsNullOrEmpty(_message.Text);
            _chevronHolder.Children.Clear();
            _chevronHolder.Children.Add(Codicon.Create(value ? "chevron-down" : "chevron-right"));
            AutomationProperties.SetHelpText(_header, value ? "expanded" : "collapsed");
            PaintActions();
        }
    }

    /// <summary>
    ///  Sets the count beside the title, with what it counts as its tooltip, or none.
    /// </summary>
    /// <param name="count">The count, or 0 for none.</param>
    /// <param name="tooltip">What it counts.</param>
    internal void SetBadge(int count, string? tooltip)
    {
        _badge.IsVisible = count != 0;
        _badgeText.Text = count.ToString(System.Globalization.CultureInfo.CurrentCulture);
        ToolTip.SetTip(_badge, tooltip);
    }

    /// <summary>
    ///  Sets the message shown above the contents, as a VS Code view's message, or none.
    /// </summary>
    /// <param name="message">The message, or null.</param>
    internal void SetMessage(string? message)
    {
        _message.Text = message;
        _message.IsVisible = _open && !string.IsNullOrEmpty(message);
    }

    /// <summary>
    ///  Sets the header's actions: icon buttons, then the rest under an ellipsis, as a view's title bar has them.
    /// </summary>
    /// <param name="primary">The icon buttons.</param>
    /// <param name="secondary">The ellipsis menu's groups, or none.</param>
    internal void SetActions(IReadOnlyList<TreeAction> primary, IReadOnlyList<IReadOnlyList<TreeAction>>? secondary = null)
    {
        _actions.Children.Clear();
        foreach (TreeAction action in primary)
        {
            _actions.Children.Add(HeaderButton(action.Icon ?? "ellipsis", action.Title, _ => action.Run()));
        }

        if (secondary is { Count: > 0 } && secondary.Any(group => group.Count != 0))
        {
            ContextMenu menu = ViewTree.Menu(secondary);
            _actions.Children.Add(HeaderButton("ellipsis", "More Actions...", button => menu.Open(button)));
        }

        PaintActions();
    }

    // The actions show while the section is open and the pointer is over its header or the header has the keyboard,
    // as VS Code shows a view's.
    private void PaintActions()
    {
        bool show = _open && (_header.IsPointerOver || _header.IsKeyboardFocusWithin);
        _actions.Opacity = show ? 1 : 0;
        _actions.IsHitTestVisible = show;
        _header.BorderThickness = _header.IsKeyboardFocusWithin ? new Thickness(1) : new Thickness(0);
    }

    private static FlatButton HeaderButton(string icon, string title, Action<FlatButton> press)
    {
        FlatButton button = FlatButton.Icon(icon, title);
        button.Click += (_, _) => press(button);
        return button;
    }
}