// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

/// <summary>
///  A condition of an action: what it tests, or 0 for a parameter of the action's codes, and its value.
/// </summary>
/// <param name="Type">The test, 0 to 19.</param>
/// <param name="Value">The item, room, flag or count tested, or the parameter.</param>
internal sealed record GameCondition(int Type, int Value);
