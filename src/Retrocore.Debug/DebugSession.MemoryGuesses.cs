// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Isa;

namespace Retrocore.Debug;

internal sealed partial class DebugSession
{
    /// <summary>
    ///  What analysis guesses each byte of a space is, from where its code is known to start.
    /// </summary>
    /// <param name="Target">The machine analyzed, which a new launch replaces.</param>
    /// <param name="Set">The instruction set it decoded with.</param>
    /// <param name="Space">The space analyzed: the memory reference's bank, or empty for the CPU's memory.</param>
    /// <param name="Image">The bytes analyzed, unreadable ones as zero.</param>
    /// <param name="Runs">The readable runs, as start and length pairs.</param>
    /// <param name="Entries">The entry points the analysis infers from, in order.</param>
    /// <param name="Starts">The Decode from here starts, which the analysis takes as given, in order.</param>
    /// <param name="Data">
    ///  The sources' data statements that apply, as start and length pairs, which the analysis keeps out of.
    /// </param>
    /// <param name="Kinds">Each byte's guess.</param>
    private sealed record MemoryGuesses(
        IDebugTarget Target,
        InstructionSet Set,
        string Space,
        byte[] Image,
        int[] Runs,
        int[] Entries,
        int[] Starts,
        int[] Data,
        GuessKind[] Kinds);
}
