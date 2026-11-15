// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Desktop;

/// <summary>
///  A value a setting can take: what it is called, a note, and the launch option's value, a string, a number or a
///  bool.
/// </summary>
/// <param name="Label">What the value is called.</param>
/// <param name="Value">The launch option's value.</param>
/// <param name="Detail">A note on it, or null.</param>
internal sealed record ChoiceValue(string Label, object Value, string? Detail = null);