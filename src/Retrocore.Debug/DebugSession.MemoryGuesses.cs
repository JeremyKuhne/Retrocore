// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug;

internal sealed partial class DebugSession
{
    /// <summary>
    ///  What analysis guesses each byte of a space is, from where its code is known to start.
    /// </summary>
    /// <param name="Space">The space analyzed: the memory reference's bank, or empty for the CPU's memory.</param>
    /// <param name="Image">The bytes analyzed, unreadable ones as zero.</param>
    /// <param name="Entries">The entry points, in order.</param>
    /// <param name="Kinds">Each byte's guess.</param>
    private sealed record MemoryGuesses(string Space, byte[] Image, int[] Entries, GuessKind[] Kinds);
}
