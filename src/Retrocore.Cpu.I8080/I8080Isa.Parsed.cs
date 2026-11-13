// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Isa;

namespace Retrocore.Cpu.I8080;

public static partial class I8080Isa
{
    /// <summary>
    ///  Holds the parsed description; the runtime runs its static initializer once, so every caller shares one
    ///  description and its sets.
    /// </summary>
    private static class Parsed
    {
        /// <summary>
        ///  The description.
        /// </summary>
        internal static readonly IsaDescription Description = IsaParser.Parse(DescriptionText);

        /// <summary>
        ///  The 8080's instruction set.
        /// </summary>
        internal static readonly InstructionSet Set = Description.InstructionSets[Name];

        /// <summary>
        ///  The 8085's instruction set.
        /// </summary>
        internal static readonly InstructionSet Set8085 = Description.InstructionSets[Name8085];
    }
}
