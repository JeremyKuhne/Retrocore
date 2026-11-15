// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Desktop;

/// <summary>
///  A setting of a machine: a launch option and its values.
/// </summary>
/// <param name="Option">The launch option it sets, such as <c>monitor</c>.</param>
/// <param name="Label">What the setting is called.</param>
/// <param name="Values">The values it can take.</param>
/// <param name="Default">The value used when the launch leaves it out, as the debug host defaults it.</param>
internal sealed record MachineChoice(string Option, string Label, IReadOnlyList<ChoiceValue> Values, object Default);