// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Desktop;

/// <summary>
///  An item of a <see cref="QuickPick"/>: a label, a description after it, a detail under it, or a separator with a
///  label of its own, as VS Code's quick pick items are.
/// </summary>
/// <typeparam name="T">What picking it gives.</typeparam>
internal sealed class QuickPickItem<T>
{
    /// <summary>
    ///  Gets the label.
    /// </summary>
    internal required string Label { get; init; }

    /// <summary>
    ///  Gets the dimmer text after the label, or null.
    /// </summary>
    internal string? Description { get; init; }

    /// <summary>
    ///  Gets the dimmer line under the label, or null.
    /// </summary>
    internal string? Detail { get; init; }

    /// <summary>
    ///  Gets a Codicon shown before the label, or null.
    /// </summary>
    internal string? Icon { get; init; }

    /// <summary>
    ///  Gets a Codicon shown where the description starts, as <c>$(check)</c> in one, or null.
    /// </summary>
    internal string? DescriptionIcon { get; init; }

    /// <summary>
    ///  Gets whether the item is a separator, which is never picked.
    /// </summary>
    internal bool Separator { get; init; }

    /// <summary>
    ///  Gets whether the item starts out selected, as VS Code's picked items do.
    /// </summary>
    internal bool Picked { get; init; }

    /// <summary>
    ///  Gets what picking the item gives.
    /// </summary>
    internal T? Value { get; init; }
}