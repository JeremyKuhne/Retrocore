// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

/// <summary>
///  An item: its description, which may end in the word GET and DROP know it by between slashes, and where it starts.
/// </summary>
/// <param name="Description">The description; one starting with <c>*</c> is a treasure.</param>
/// <param name="Location">The room it starts in, 0 for none, or <see cref="ScottFreeGame.Carried"/>.</param>
internal sealed record GameItem(string Description, int Location);
