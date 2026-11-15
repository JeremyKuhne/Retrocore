// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Media;
using System.Text;

namespace Retrocore.Desktop;

/// <summary>
///  A tree drawn as VS Code draws its views' trees: rows 22 pixels tall, a chevron for the rows that open, an icon,
///  the label with its description dimmer after it, the row's actions at its end while it is under the pointer or
///  selected, its tooltip and context menu, and the arrow keys to move about it.
/// </summary>
internal sealed class ViewTree : Border
{
    /// <summary>
    ///  A row's height, as VS Code's trees have it.
    /// </summary>
    internal const double RowHeight = 22;

    /// <summary>
    ///  Each level's indent, as VS Code's trees have it.
    /// </summary>
    internal const double Indent = 8;

    private readonly StackPanel _rows = new();
    private readonly Dictionary<string, bool> _expanded = [];
    private readonly List<TreeRow> _visible = [];
    private IReadOnlyList<TreeNode> _roots = [];
    private string _shown = "";
    private string? _selected;

    /// <summary>
    ///  Creates an empty tree.
    /// </summary>
    internal ViewTree()
    {
        Focusable = true;
        Background = Brushes.Transparent;
        Child = _rows;
        GotFocus += (_, _) => Paint();
        LostFocus += (_, _) => Paint();
        KeyDown += OnKey;
    }

    /// <summary>
    ///  Gets the rows shown, for the tests and the smoke run: each row's depth, label and description.
    /// </summary>
    internal IEnumerable<(int Depth, string Label, string? Description)> Shown =>
        _visible.Select(row => (row.Depth, row.Node.Label, row.Node.Description));

    /// <summary>
    ///  Shows rows, keeping which are open and which is selected. Drawing the same rows again draws nothing.
    /// </summary>
    /// <param name="roots">The top-level rows.</param>
    internal void Show(IReadOnlyList<TreeNode> roots)
    {
        _roots = roots;
        string shown = Signature(roots);
        if (shown == _shown) { return; }
        _shown = shown;
        Build();
    }

    /// <summary>
    ///  Runs the action of the row with an identity, as a click would, for the smoke run's checks.
    /// </summary>
    /// <param name="id">The row's identity.</param>
    /// <returns>Whether there was such a row.</returns>
    internal bool Click(string id)
    {
        TreeRow? row = _visible.FirstOrDefault(candidate => candidate.Node.Id == id);
        if (row is null) { return false; }
        Activate(row);
        return true;
    }

    /// <summary>
    ///  Selects the row with an identity, as a click on it would without running it, for the tour.
    /// </summary>
    /// <param name="id">The row's identity.</param>
    internal void SelectRow(string id)
    {
        if (_visible.FirstOrDefault(candidate => candidate.Node.Id == id) is { } row)
        {
            Focus();
            Select(row);
        }
    }

    // Everything a row draws, and its children's, so an unchanged tree is left as it is.
    private static string Signature(IReadOnlyList<TreeNode> nodes)
    {
        StringBuilder builder = new();
        void Add(IReadOnlyList<TreeNode> level)
        {
            foreach (TreeNode node in level)
            {
                builder.Append(node.Id).Append('\u001F').Append(node.Label).Append('\u001F').Append(node.Description)
                    .Append('\u001F').Append(node.Icon).Append('\u001F').Append(node.IconColour).Append('\u001F')
                    .Append(node.Tooltip).Append('\u001F').Append(node.Checked).Append('\u001F').Append(node.State)
                    .Append('\u001F').Append(node.IconControl is null ? "" : "control")
                    .Append('\u001F').Append(string.Join(',', node.Inline.Select(action => action.Title)))
                    .Append('\u001F').Append(string.Join(',', node.Menu.SelectMany(group => group).Select(action => action.Title)))
                    .Append('\u001E');

                builder.Append('[');
                Add(node.Children);
                builder.Append(']');
            }
        }

        Add(nodes);
        return builder.ToString();
    }

    private void Build()
    {
        _rows.Children.Clear();
        _visible.Clear();
        void Add(IReadOnlyList<TreeNode> level, int depth, TreeRow? parent)
        {
            foreach (TreeNode node in level)
            {
                TreeRow row = new(this, node, depth, parent);
                _visible.Add(row);
                _rows.Children.Add(row);
                if (IsOpen(node)) { Add(node.Children, depth + 1, row); }
            }
        }

        Add(_roots, 0, parent: null);
        if (_selected is not null && _visible.All(row => row.Node.Id != _selected)) { _selected = null; }
        Paint();
    }

    /// <summary>
    ///  Gets whether a row is open, as the user left it or as it starts.
    /// </summary>
    /// <param name="node">The row.</param>
    /// <returns>True when its children show.</returns>
    internal bool IsOpen(TreeNode node) => node.State != TreeState.None
        && (_expanded.TryGetValue(node.Id, out bool open) ? open : node.State == TreeState.Expanded);

    /// <summary>
    ///  Opens or closes a row.
    /// </summary>
    /// <param name="row">The row.</param>
    /// <param name="open">Whether to open it, or null to change it.</param>
    internal void Toggle(TreeRow row, bool? open = null)
    {
        if (row.Node.State == TreeState.None) { return; }
        bool now = open ?? !IsOpen(row.Node);
        if (now == IsOpen(row.Node)) { return; }
        _expanded[row.Node.Id] = now;
        Build();
    }

    /// <summary>
    ///  Selects a row.
    /// </summary>
    /// <param name="row">The row.</param>
    internal void Select(TreeRow row)
    {
        _selected = row.Node.Id;
        Paint();
        row.BringIntoView();
    }

    /// <summary>
    ///  Clicks a row: it is selected, and opens or closes, or does what it does.
    /// </summary>
    /// <param name="row">The row.</param>
    internal void Activate(TreeRow row)
    {
        Select(row);
        if (row.Node.State != TreeState.None && row.Node.Command is null)
        {
            Toggle(row);
        }
        else
        {
            row.Node.Command?.Invoke();
        }
    }

    // The selection's colours: VS Code's active selection while the tree has the keyboard, its inactive one when not.
    private void Paint()
    {
        bool focused = IsKeyboardFocusWithin;
        foreach (TreeRow row in _visible) { row.Paint(row.Node.Id == _selected, focused); }
    }

    private void OnKey(object? sender, KeyEventArgs e)
    {
        if (_visible.Count == 0) { return; }
        int index = _visible.FindIndex(row => row.Node.Id == _selected);
        TreeRow? current = index >= 0 ? _visible[index] : null;
        switch (e.Key)
        {
            case Key.Down:
                Select(_visible[Math.Min(_visible.Count - 1, index + 1)]);
                break;
            case Key.Up:
                Select(_visible[Math.Max(0, index - 1)]);
                break;
            case Key.Home:
                Select(_visible[0]);
                break;
            case Key.End:
                Select(_visible[^1]);
                break;
            case Key.Right when current is not null:
                if (current.Node.State != TreeState.None && !IsOpen(current.Node))
                {
                    Toggle(current, open: true);
                }
                else if (index + 1 < _visible.Count && _visible[index + 1].ParentRow == current)
                {
                    Select(_visible[index + 1]);
                }

                break;
            case Key.Left when current is not null:
                if (current.Node.State != TreeState.None && IsOpen(current.Node))
                {
                    Toggle(current, open: false);
                }
                else if (current.ParentRow is { } parent)
                {
                    Select(_visible.First(row => row.Node.Id == parent.Node.Id));
                }

                break;
            case Key.Enter when current is not null:
                Activate(current);
                break;
            case Key.Space when current is not null:
                if (current.Node.Checked is { } ticked)
                {
                    current.Node.Check?.Invoke(!ticked);
                }
                else
                {
                    Activate(current);
                }

                break;
            case Key.F10 when current is not null && e.KeyModifiers == KeyModifiers.Shift:
                current.OpenMenu();
                break;
            case Key.Apps when current is not null:
                current.OpenMenu();
                break;
            default:
                return;
        }

        e.Handled = true;
    }

    /// <summary>
    ///  Builds a context menu of groups of actions with lines between, as VS Code's menus group their items.
    /// </summary>
    /// <param name="groups">The groups.</param>
    /// <returns>The menu.</returns>
    internal static ContextMenu Menu(IReadOnlyList<IReadOnlyList<TreeAction>> groups)
    {
        ContextMenu menu = new();
        List<Control> items = [];
        foreach (IReadOnlyList<TreeAction> group in groups.Where(group => group.Count != 0))
        {
            if (items.Count != 0) { items.Add(new Separator()); }
            foreach (TreeAction action in group)
            {
                MenuItem item = new() { Header = action.Title };
                item.Click += (_, _) => action.Run();
                items.Add(item);
            }
        }

        menu.ItemsSource = items;
        return menu;
    }
}