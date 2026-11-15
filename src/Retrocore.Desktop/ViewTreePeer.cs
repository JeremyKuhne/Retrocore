// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Avalonia.Automation.Peers;

namespace Retrocore.Desktop;

/// <summary>
///  A <see cref="ViewTree"/> as a screen reader hears it: a tree, its rows its items.
/// </summary>
/// <param name="owner">The tree.</param>
internal sealed class ViewTreePeer(ViewTree owner) : ControlAutomationPeer(owner)
{
    /// <inheritdoc/>
    protected override AutomationControlType GetAutomationControlTypeCore() => AutomationControlType.Tree;

    /// <inheritdoc/>
    protected override bool IsContentElementCore() => true;

    /// <inheritdoc/>
    protected override bool IsControlElementCore() => true;
}