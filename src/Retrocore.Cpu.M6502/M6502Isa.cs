// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Isa;

namespace Retrocore.Cpu.M6502;

/// <summary>
///  The 6502 family's instruction-set description, read from <c>OpcodeTables.txt</c>.
/// </summary>
public static partial class M6502Isa
{
    /// <summary>
    ///  Gets the description, parsed once on first use.
    /// </summary>
    public static IsaDescription Description => Parsed.Description;

    /// <summary>
    ///  Gets the instruction set of a CPU variant.
    /// </summary>
    /// <param name="variant">The variant.</param>
    /// <returns>Its instruction set.</returns>
    /// <exception cref="ArgumentOutOfRangeException">The variant is not defined.</exception>
    public static InstructionSet Get(ProcessorVariant variant) => (uint)variant < (uint)Parsed.Sets.Length
        ? Parsed.Sets[(int)variant]
        : throw new ArgumentOutOfRangeException(nameof(variant));

    /// <summary>
    ///  Gets the CPU variant whose opcode map an instruction set decodes with; the 65SC02 subset decodes as the
    ///  65C02.
    /// </summary>
    /// <param name="set">One of this description's instruction sets.</param>
    /// <returns>The variant.</returns>
    /// <exception cref="ArgumentException">The set is not a 6502 family set.</exception>
    public static ProcessorVariant VariantOf(InstructionSet set)
    {
        ProcessorVariant? variant = ReferenceEquals(set.Description, Description) ? set.Name switch
        {
            nameof(ProcessorVariant.Mos6502) => ProcessorVariant.Mos6502,
            nameof(ProcessorVariant.Wdc65C02) or "65SC02" => ProcessorVariant.Wdc65C02,
            nameof(ProcessorVariant.Rockwell65C02) => ProcessorVariant.Rockwell65C02,
            _ => null
        } : null;

        return variant ?? throw new ArgumentException("The instruction set is not a 6502 family set.", nameof(set));
    }
}
