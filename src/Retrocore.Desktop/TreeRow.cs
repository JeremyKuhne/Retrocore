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
///  One row: its indent and chevron, check box, icon, label and description, and its actions.
/// </summary>
internal sealed class TreeRow : Border
{
    private readonly ViewTree _tree;
    private readonly TextBlock _label;
    private readonly TextBlock? _description;
    private readonly Control? _chevron;
    private readonly StackPanel _actions = new()
    {
        Orientation = Orientation.Horizontal, Margin = new Thickness(0, 0, 4, 0)
    };
    private bool _selected;
    private bool _focused;

    /// <summary>
    ///  Creates a row.
    /// </summary>
    /// <param name="tree">The tree it is in.</param>
    /// <param name="node">What it shows.</param>
    /// <param name="depth">How deep it is, 0 at the top.</param>
    /// <param name="parent">The row it is under, or null.</param>
    internal TreeRow(ViewTree tree, TreeNode node, int depth, TreeRow? parent)
    {
        _tree = tree;
        Node = node;
        Depth = depth;
        ParentRow = parent;
        Height = ViewTree.RowHeight;
        Background = Brushes.Transparent;
        BorderThickness = new Thickness(1);
        BorderBrush = Brushes.Transparent;

        DockPanel content = new() { LastChildFill = true };

        // The indent, then the chevron or the room for one.
        Panel twistie = new()
        {
            Width = 16, Height = 16, Margin = new Thickness(ViewTree.Indent + (depth * ViewTree.Indent), 0, 4, 0)
        };

        if (node.State != TreeState.None)
        {
            _chevron = Codicon.Create(tree.IsOpen(node) ? "chevron-down" : "chevron-right");
            twistie.Children.Add(_chevron);
        }

        DockPanel.SetDock(twistie, Dock.Left);
        content.Children.Add(twistie);

        if (node.Checked is { } ticked)
        {
            Control box = CheckBox(ticked);
            DockPanel.SetDock(box, Dock.Left);
            content.Children.Add(box);
        }

        Control? icon = node.IconControl?.Invoke() ?? (node.Icon is { } name ? Codicon.Create(name, node.IconColour) : null);
        if (icon is not null)
        {
            icon.Margin = Codicon.Gap;
            icon.VerticalAlignment = VerticalAlignment.Center;
            DockPanel.SetDock(icon, Dock.Left);
            content.Children.Add(icon);
        }

        DockPanel.SetDock(_actions, Dock.Right);
        content.Children.Add(_actions);
        foreach (TreeAction action in node.Inline) { _actions.Children.Add(ActionButton(action)); }

        _label = new TextBlock
        {
            Text = node.Label,
            VerticalAlignment = VerticalAlignment.Center,
            FontSize = 13,
        };

        StackPanel text = new() { Orientation = Orientation.Horizontal, ClipToBounds = true };
        text.Children.Add(_label);
        if (!string.IsNullOrEmpty(node.Description))
        {
            // As VS Code draws a description: a little smaller, at 70% of the label's colour, after a gap.
            _description = new TextBlock
            {
                Text = node.Description,
                VerticalAlignment = VerticalAlignment.Center,
                FontSize = 12,
                Opacity = 0.7,
                Margin = new Thickness(6, 0, 0, 0),
                TextTrimming = TextTrimming.CharacterEllipsis,
            };

            text.Children.Add(_description);
        }

        content.Children.Add(text);
        Child = content;
        AutomationProperties.SetName(this, string.IsNullOrEmpty(node.Description) ? node.Label : $"{node.Label}, {node.Description}");
        Tip.Set(this, node.Tooltip);

        if (node.Menu.Count != 0)
        {
            ContextMenu = ViewTree.Menu(node.Menu);
        }

        PointerEntered += (_, _) => PaintHover();
        PointerExited += (_, _) => PaintHover();
        PointerPressed += OnPressed;
    }

    /// <summary>
    ///  Gets what the row shows.
    /// </summary>
    internal TreeNode Node { get; }

    /// <summary>
    ///  Gets how deep it is, 0 at the top.
    /// </summary>
    internal int Depth { get; }

    /// <summary>
    ///  Gets the row it is under, or null.
    /// </summary>
    internal TreeRow? ParentRow { get; }

    /// <summary>
    ///  Opens its context menu, as Shift+F10 does.
    /// </summary>
    internal void OpenMenu() => ContextMenu?.Open(this);

    /// <summary>
    ///  Colours the row for whether it is selected and whether its tree has the keyboard.
    /// </summary>
    /// <param name="selected">Whether it is selected.</param>
    /// <param name="focused">Whether its tree has the keyboard.</param>
    internal void Paint(bool selected, bool focused)
    {
        _selected = selected;
        _focused = focused;
        string text = selected && focused ? Palette.ListSelectionText : Palette.Text;
        _label.Themed(TextBlock.ForegroundProperty, text);
        _description?.Themed(TextBlock.ForegroundProperty, text);
        if (_chevron is not null)
        {
            Codicon.Recolour(_chevron, selected && focused ? Palette.ListSelectionText : Palette.Icon);
        }

        if (selected && focused)
        {
            this.Themed(BorderBrushProperty, Palette.Focus);
        }
        else
        {
            BorderBrush = Brushes.Transparent;
        }

        PaintHover();
    }

    private void PaintHover()
    {
        bool hover = IsPointerOver;
        if (_selected)
        {
            this.Themed(BackgroundProperty, _focused ? Palette.ListSelection : Palette.ListInactiveSelection);
        }
        else if (hover)
        {
            this.Themed(BackgroundProperty, Palette.ListHover);
        }
        else
        {
            Background = Brushes.Transparent;
        }

        // The row's actions show while it is under the pointer or selected, keeping their room either way so
        // the row does not move under the pointer.
        bool show = hover || _selected;
        _actions.Opacity = show ? 1 : 0;
        _actions.IsHitTestVisible = show;
    }

    private void OnPressed(object? sender, PointerPressedEventArgs e)
    {
        PointerPointProperties point = e.GetCurrentPoint(this).Properties;
        _tree.Focus(NavigationMethod.Pointer);
        if (point.IsRightButtonPressed)
        {
            _tree.Select(this);
            return;
        }

        if (!point.IsLeftButtonPressed) { return; }
        e.Handled = true;

        // The chevron opens and closes the row even when the row does something of its own.
        if (_chevron is not null && e.GetPosition(_chevron) is { } at && at.X >= -2 && at.X <= 18)
        {
            _tree.Select(this);
            _tree.Toggle(this);
            return;
        }

        _tree.Activate(this);
    }

    private Border CheckBox(bool ticked)
    {
        Border box = new()
        {
            Width = 16,
            Height = 16,
            CornerRadius = new CornerRadius(3),
            BorderThickness = new Thickness(1),
            Margin = new Thickness(0, 0, 6, 0),
            VerticalAlignment = VerticalAlignment.Center,
            Child = ticked ? Codicon.Create("check", Palette.Text, 14) : null,
        };

        box.Themed(BackgroundProperty, Palette.Checkbox).Themed(BorderBrushProperty, Palette.CheckboxBorder);
        AutomationProperties.SetName(box, Node.Label);
        box.PointerPressed += (_, e) =>
        {
            if (!e.GetCurrentPoint(box).Properties.IsLeftButtonPressed) { return; }
            e.Handled = true;
            _tree.Select(this);
            Node.Check?.Invoke(!ticked);
        };

        return box;
    }

    private FlatButton ActionButton(TreeAction action)
    {
        FlatButton button = FlatButton.Icon(action.Icon ?? "ellipsis", action.Title);
        button.Click += (_, _) =>
        {
            _tree.Select(this);
            action.Run();
        };

        return button;
    }
}