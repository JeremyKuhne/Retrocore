// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Avalonia.Controls;

namespace Retrocore.Desktop;

/// <summary>
///  A row of a <see cref="ViewTree"/>, as a VS Code tree item describes one: its label, description, icon and
///  tooltip, its children, what a click does, and the actions beside it and in its context menu.
/// </summary>
internal sealed class TreeNode
{
    /// <summary>
    ///  Gets the row's identity, which keeps it expanded or selected when the tree is drawn again.
    /// </summary>
    internal required string Id { get; init; }

    /// <summary>
    ///  Gets the row's label.
    /// </summary>
    internal required string Label { get; init; }

    /// <summary>
    ///  Gets the dimmer text after the label, or null.
    /// </summary>
    internal string? Description { get; init; }

    /// <summary>
    ///  Gets the Codicon the row shows, or null for none.
    /// </summary>
    internal string? Icon { get; init; }

    /// <summary>
    ///  Gets the theme colour of the row's icon.
    /// </summary>
    internal string IconColour { get; init; } = Palette.Icon;

    /// <summary>
    ///  Gets a control the row shows in place of a Codicon, such as the machine's screen, or null.
    /// </summary>
    internal Func<Control>? IconControl { get; init; }

    /// <summary>
    ///  Gets the row's tooltip, in Markdown, or null.
    /// </summary>
    internal string? Tooltip { get; init; }

    /// <summary>
    ///  Gets the rows under it.
    /// </summary>
    internal IReadOnlyList<TreeNode> Children { get; init; } = [];

    /// <summary>
    ///  Gets whether the row opens to its children, and whether it starts open.
    /// </summary>
    internal TreeState State { get; init; } = TreeState.None;

    /// <summary>
    ///  Gets what a click on the row does, or null.
    /// </summary>
    internal Action? Command { get; init; }

    /// <summary>
    ///  Gets the row's check box: null for none, or whether it is ticked.
    /// </summary>
    internal bool? Checked { get; init; }

    /// <summary>
    ///  Gets what ticking or clearing the check box does.
    /// </summary>
    internal Action<bool>? Check { get; init; }

    /// <summary>
    ///  Gets the icon buttons shown beside the row while it is under the pointer or selected.
    /// </summary>
    internal IReadOnlyList<TreeAction> Inline { get; init; } = [];

    /// <summary>
    ///  Gets the row's context menu, in groups separated by lines.
    /// </summary>
    internal IReadOnlyList<IReadOnlyList<TreeAction>> Menu { get; init; } = [];
}