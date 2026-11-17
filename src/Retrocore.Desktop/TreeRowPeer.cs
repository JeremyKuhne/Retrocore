// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Avalonia.Automation;
using Avalonia.Automation.Peers;
using Avalonia.Automation.Provider;

namespace Retrocore.Desktop;

/// <summary>
///  A <see cref="TreeRow"/> as a screen reader hears it: a tree item, selected or not, open or closed when it has
///  children, and checked or not when it has a check box.
/// </summary>
/// <param name="owner">The row.</param>
internal sealed class TreeRowPeer(TreeRow owner) : ControlAutomationPeer(owner), IExpandCollapseProvider, IToggleProvider, ISelectionItemProvider
{
    /// <inheritdoc/>
    public ExpandCollapseState ExpandCollapseState => owner.Node.State == TreeState.None
        ? ExpandCollapseState.LeafNode
        : owner.Tree.IsOpen(owner.Node) ? ExpandCollapseState.Expanded : ExpandCollapseState.Collapsed;

    /// <inheritdoc/>
    public bool ShowsMenu => false;

    /// <inheritdoc/>
    public ToggleState ToggleState => owner.Node.Checked switch
    {
        true => ToggleState.On,
        false => ToggleState.Off,
        null => ToggleState.Indeterminate,
    };

    /// <inheritdoc/>
    public bool IsSelected => owner.IsSelected;

    /// <inheritdoc/>
    public ISelectionProvider? SelectionContainer => null;

    /// <inheritdoc/>
    public void Expand() => owner.Tree.Toggle(owner, open: true);

    /// <inheritdoc/>
    public void Collapse() => owner.Tree.Toggle(owner, open: false);

    /// <inheritdoc/>
    public void Toggle()
    {
        if (owner.Node.Checked is { } ticked) { owner.Node.Check?.Invoke(!ticked); }
    }

    /// <inheritdoc/>
    public void Select() => owner.Tree.Select(owner);

    /// <inheritdoc/>
    public void AddToSelection() => owner.Tree.Select(owner);

    /// <inheritdoc/>
    public void RemoveFromSelection()
    {
    }

    /// <inheritdoc/>
    protected override AutomationControlType GetAutomationControlTypeCore() => AutomationControlType.TreeItem;

    /// <inheritdoc/>
    protected override bool IsContentElementCore() => true;

    /// <inheritdoc/>
    protected override bool IsControlElementCore() => true;
}