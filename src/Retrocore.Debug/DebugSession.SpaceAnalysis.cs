// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Isa;

namespace Retrocore.Debug;

internal sealed partial class DebugSession
{
    /// <summary>
    ///  What the listing and the inspector know of a memory view's space: its bytes, labels and names, each address's
    ///  source position, and analysis's guesses at what no source describes.
    /// </summary>
    /// <param name="Memory">The space's bytes, each read once.</param>
    /// <param name="Set">The instruction set its code is in.</param>
    /// <param name="Labels">The code labels by address.</param>
    /// <param name="Names">The names by address, constants included.</param>
    /// <param name="Guesses">Analysis's guesses.</param>
    /// <param name="Forced">
    ///  The addresses an instruction starts at whatever else is known: Decode from here's starts and code marked.
    /// </param>
    /// <param name="MarkedCode">Code marked in the hints file, with its instructions' sizes.</param>
    /// <param name="Position">The source position of an address, found once.</param>
    /// <param name="Marked">Whether an address is data marked in the hints file.</param>
    private sealed record SpaceAnalysis(
        ListingMemory Memory,
        InstructionSet Set,
        SortedDictionary<int, string> Labels,
        SortedDictionary<int, string> Names,
        MemoryGuesses Guesses,
        HashSet<int> Forced,
        Dictionary<int, int> MarkedCode,
        Func<int, DebugPosition?> Position,
        Func<int, bool> Marked);
}
