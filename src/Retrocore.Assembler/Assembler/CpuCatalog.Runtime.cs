// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Cpu.M6502;
using Retrocore.Cpu.M6809;
using Retrocore.Cpu.Z80;
using Retrocore.Isa;

namespace Retrocore.Assembler;

/// <summary>
///  The instruction sets the assembler and disassembler know, by the names <c>.cpu</c> selects them with.
/// </summary>
public static class CpuCatalog
{
    private static readonly Dictionary<string, InstructionSet> s_sets = Create();

    /// <summary>
    ///  Gets every instruction set by name, such as <c>Mos6502</c>, <c>65SC02</c>, <c>Z80</c>, <c>M6809</c> or <c>Pcode</c>; names
    ///  ignore case.
    /// </summary>
    public static IReadOnlyDictionary<string, InstructionSet> InstructionSets => s_sets;

    /// <summary>
    ///  Gets an instruction set by name.
    /// </summary>
    /// <param name="name">The name, in any case.</param>
    /// <returns>The set.</returns>
    /// <exception cref="ArgumentException">No set has the name.</exception>
    public static InstructionSet Get(string name) =>
        s_sets.TryGetValue(name ?? throw new ArgumentNullException(nameof(name)), out InstructionSet? set)
            ? set
            : throw new ArgumentException($"Unknown CPU '{name}'.", nameof(name));

    private static Dictionary<string, InstructionSet> Create()
    {
        Dictionary<string, InstructionSet> sets = new(StringComparer.OrdinalIgnoreCase);
        foreach (IsaDescription description in (IsaDescription[])[M6502Isa.Description, Z80Isa.Description, M6809Isa.Description])
        {
            foreach (KeyValuePair<string, InstructionSet> pair in description.InstructionSets)
            {
                sets.Add(pair.Key, pair.Value);
            }
        }

        // Apple Pascal's p-code has no instructions here: Pcode.asm's macros write it, and only under .cpu Pcode.
        sets.Add(MacroCpus.Pcode, InstructionSet.MacroOnly(MacroCpus.Pcode, M6502Isa.Description));
        return sets;
    }
}
