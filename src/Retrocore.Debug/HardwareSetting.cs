// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug;

/// <summary>
///  A switch on a piece of installed hardware, such as a card's DIP switch, which the Retro Devices view shows as a
///  checkbox under its row and <c>retro/hardware</c>'s <c>setSetting</c> changes.
/// </summary>
/// <param name="Id">A stable identifier within its row, such as <c>translation</c>.</param>
/// <param name="Label">What it is, such as "Address translation".</param>
/// <param name="Value">Whether it is on.</param>
/// <param name="Description">What it does on and off.</param>
internal sealed record HardwareSetting(string Id, string Label, bool Value, string Description);
