// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Media;

namespace Retrocore.Pascal;

public static partial class PascalAssemblyWriter
{
    /// <summary>
    ///  An assembled procedure as read for writing: its code, data, relocated words and the names it gives and takes.
    /// </summary>
    /// <param name="code">The procedure in its segment.</param>
    /// <param name="written">How its host declares it.</param>
    private sealed class Parsed(PascalProcedure code, PascalAssembledProcedure written)
    {
        /// <summary>
        ///  Gets the procedure in its segment.
        /// </summary>
        public PascalProcedure Code { get; } = code;

        /// <summary>
        ///  Gets how its host declares it.
        /// </summary>
        public PascalAssembledProcedure Written { get; } = written;

        /// <summary>
        ///  Gets the name its <c>.PROC</c> or <c>.FUNC</c> gives it, the Assembler's eight letters.
        /// </summary>
        public string Name => Significant(Written.Name);

        /// <summary>
        ///  Gets or sets its entry, the offset in the segment its code starts at.
        /// </summary>
        public int Entry { get; set; }

        /// <summary>
        ///  Gets or sets where its relocation lists start, the end of its code and data.
        /// </summary>
        public int Bottom { get; set; }

        /// <summary>
        ///  Gets its relocated words, by offset in the segment, with the list each is in.
        /// </summary>
        public Dictionary<int, int> Relocated { get; } = [];

        /// <summary>
        ///  Gets the places its code is decoded from: its entry, and those another procedure's JSR or JMP reaches.
        /// </summary>
        public HashSet<int> Roots { get; } = [];

        /// <summary>
        ///  Gets its instructions, by offset in the segment.
        /// </summary>
        public SortedDictionary<int, DisassembledInstruction> Starts { get; } = [];

        /// <summary>
        ///  Gets the places in it that are referred to, by offset in the segment.
        /// </summary>
        public HashSet<int> Targets { get; } = [];

        /// <summary>
        ///  Gets its labels, by offset in the segment.
        /// </summary>
        public Dictionary<int, string> Labels { get; } = [];

        /// <summary>
        ///  Gets the places named from a label before them, such as <c>L0003+1</c>, by offset in the segment.
        /// </summary>
        public Dictionary<int, string> Inside { get; } = [];

        /// <summary>
        ///  Gets the names it uses, in the Assembler's eight letters, so a label of its own takes none of them.
        /// </summary>
        public HashSet<string> Used { get; } = new(StringComparer.Ordinal);

        /// <summary>
        ///  Gets the labels it defines for other procedures, <c>.DEF</c>.
        /// </summary>
        public SortedSet<string> Defined { get; } = new(StringComparer.Ordinal);

        /// <summary>
        ///  Gets the names it refers to in other procedures, <c>.REF</c>.
        /// </summary>
        public SortedSet<string> Referred { get; } = new(StringComparer.Ordinal);

        /// <summary>
        ///  Gets the host's globals it refers to, <c>.PUBLIC</c>.
        /// </summary>
        public SortedSet<string> Publics { get; } = new(StringComparer.Ordinal);

        /// <summary>
        ///  Gets the expressions its relocated words other than procedure-relative ones are written as, by offset in
        ///  the segment of the word.
        /// </summary>
        public Dictionary<int, string> Expressions { get; } = [];

        /// <summary>
        ///  Gets the instruction a place is inside of, after its first byte.
        /// </summary>
        /// <param name="at">The place, an offset in the segment.</param>
        /// <returns>Where the instruction starts, or -1 where none holds the place.</returns>
        public int Within(int at)
        {
            foreach ((int start, DisassembledInstruction instruction) in Starts)
            {
                if (start >= at) { break; }
                if (at < start + instruction.Size) { return start; }
            }

            return -1;
        }
    }
}
