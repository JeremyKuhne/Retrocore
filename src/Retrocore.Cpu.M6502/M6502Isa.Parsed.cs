// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Isa;

namespace Retrocore.Cpu.M6502;

public static partial class M6502Isa
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
        internal static readonly IsaDescription Description = IsaParser.Parse(OpcodeTable.DescriptionText);

        /// <summary>
        ///  Each variant's set, indexed by variant, so lookups neither hash nor format the variant's name.
        /// </summary>
        internal static readonly InstructionSet[] Sets =
            [.. Enum.GetValues<ProcessorVariant>().Select(variant => Description.InstructionSets[variant.ToString()])];
    }
}
