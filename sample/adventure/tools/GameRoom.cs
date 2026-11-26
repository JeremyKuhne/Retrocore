// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

/// <summary>
///  A room: its exits to the north, south, east, west, up and down (0 for none), and its description.
/// </summary>
/// <param name="Exits">The six exits.</param>
/// <param name="Description">The description; one starting with <c>*</c> is shown as it is.</param>
internal sealed record GameRoom(int[] Exits, string Description);
