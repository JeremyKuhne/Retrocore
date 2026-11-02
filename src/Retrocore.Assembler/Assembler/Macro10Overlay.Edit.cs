// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

internal static partial class Macro10Overlay
{
    /// <summary>
    ///  One edit to the base.
    /// </summary>
    /// <param name="First">The first base line replaced, or the line the block goes before.</param>
    /// <param name="Last">The last base line replaced; one less than <paramref name="First"/> for an insertion.</param>
    /// <param name="OverlayLine">The zero-based overlay line of the block's first line.</param>
    /// <param name="Lines">The block's lines.</param>
    private sealed record Edit(int First, int Last, int OverlayLine, List<string> Lines);
}
