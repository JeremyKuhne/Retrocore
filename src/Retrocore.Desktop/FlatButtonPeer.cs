// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Avalonia.Automation.Peers;
using Avalonia.Automation.Provider;

namespace Retrocore.Desktop;

/// <summary>
///  A <see cref="FlatButton"/> as a screen reader hears it: a button it can press.
/// </summary>
/// <param name="owner">The button.</param>
internal sealed class FlatButtonPeer(FlatButton owner) : ControlAutomationPeer(owner), IInvokeProvider
{
    /// <inheritdoc/>
    public void Invoke() => owner.Press();

    /// <inheritdoc/>
    protected override AutomationControlType GetAutomationControlTypeCore() => AutomationControlType.Button;

    /// <inheritdoc/>
    protected override bool IsContentElementCore() => true;

    /// <inheritdoc/>
    protected override bool IsControlElementCore() => true;
}