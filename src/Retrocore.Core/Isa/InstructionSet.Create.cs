// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Globalization;

namespace Retrocore.Isa;

public sealed partial class InstructionSet
{
    /// <summary>
    ///  Builds an instruction set from its encodings, in opcode order.
    /// </summary>
    /// <param name="name">The set's name.</param>
    /// <param name="description">The shared description.</param>
    /// <param name="entries">The opcode lines, keyed by opcode length and bytes.</param>
    /// <param name="rules">The description's settings.</param>
    /// <param name="excluded">Instructions a subset leaves out, or null.</param>
    /// <param name="message">The subset's diagnostic, with <c>{0}</c> for the operation, or null.</param>
    /// <returns>The set.</returns>
    internal static InstructionSet Create(
        string name,
        IsaDescription description,
        SortedDictionary<ulong, IsaEntry> entries,
        IsaRules rules,
        HashSet<string>? excluded,
        string? message)
    {
        InstructionSet set = new(name, description) { IndirectPageWrap = rules.IndirectPageWrap.Contains(name) };
        foreach (IsaEntry entry in entries.Values)
        {
            OperandForm form = description.Form(entry.Form)
                ?? throw new FormatException($"Instruction set '{name}': unknown form '{entry.Form}' for {entry.Instruction}.");

            string mnemonic = rules.BitSuffix.Contains(entry.Instruction)
                ? entry.Instruction + ((entry.Opcode >> 4) & 7).ToString(CultureInfo.InvariantCulture)
                : entry.Instruction;

            // A form-qualified flow class overrides the instruction's own.
            InstructionFlow flow = rules.Flows.TryGetValue($"{entry.Instruction}:{form.Name}", out InstructionFlow specificFlow)
                ? specificFlow
                : rules.Flows.TryGetValue(entry.Instruction, out InstructionFlow generalFlow) ? generalFlow : InstructionFlow.Next;

            MemoryAccess access = rules.Access.TryGetValue(entry.Instruction, out MemoryAccess general) ? general : MemoryAccess.Read;
            set.Add(
                mnemonic,
                entry,
                form,
                flow,
                access,
                rules.Access.TryGetValue($"{entry.Instruction}:{form.Name}", out MemoryAccess specific) ? specific : access,
                rules.Preferred.Contains(entry.Opcode));
        }

        if (excluded is not null && message is not null)
        {
            for (int mnemonic = 0; mnemonic < set._mnemonics.Count; mnemonic++)
            {
                if (excluded.Contains(set._baseNames[mnemonic])) { set._exclusions[mnemonic] = message; }
            }
        }

        set.Freeze();
        return set;
    }
}
