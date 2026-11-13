// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Isa;

namespace Retrocore.Cpu.M6809;

public static partial class M6809Isa
{
    /// <summary>
    ///  Holds the parsed description; the runtime runs its static initializer once, so every caller shares one
    ///  description and set.
    /// </summary>
    private static class Parsed
    {
        /// <summary>
        ///  The description.
        /// </summary>
        internal static readonly IsaDescription Description =
            IsaParser.Parse(DescriptionText, static _ => M6809PostbyteCodec.Instance);

        /// <summary>
        ///  The instruction set.
        /// </summary>
        internal static readonly InstructionSet Set = Description.InstructionSets[Name];
    }
}
