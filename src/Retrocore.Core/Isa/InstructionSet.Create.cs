// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Globalization;

namespace Retrocore.Isa;

public sealed partial class InstructionSet
{
    /// <summary>
    ///  Builds an instruction set with no instructions: a CPU a source writes only with macros, such as Apple
    ///  Pascal's p-code, whose <c>.cpu</c> turns its macros on.
    /// </summary>
    /// <param name="name">The set's name, as <c>.cpu</c> selects it.</param>
    /// <param name="description">The description it shares, whose sets a source can switch between.</param>
    /// <returns>The set.</returns>
    public static InstructionSet MacroOnly(string name, IsaDescription description)
    {
        ArgumentNullException.ThrowIfNull(name);
        ArgumentNullException.ThrowIfNull(description);
        InstructionSet set = new(name, description);
        set.Freeze();
        return set;
    }

    /// <summary>
    ///  Builds an instruction set from its encodings, in opcode order.
    /// </summary>
    /// <param name="name">The set's name.</param>
    /// <param name="description">The shared description.</param>
    /// <param name="entries">The opcode lines, keyed by opcode length and bytes.</param>
    /// <param name="rules">The description's settings.</param>
    /// <param name="excluded">Instructions a subset leaves out, or null.</param>
    /// <param name="message">The subset's diagnostic, with <c>{0}</c> for the operation, or null.</param>
    /// <param name="postbytes">The codec for the set's postbyte fields, or null.</param>
    /// <param name="entryPoints">The fixed entry points of the set: the description's and its own.</param>
    /// <param name="scopes">
    ///  Where effects lines are looked for, nearest first: the set, the sets it is built on, and the description.
    /// </param>
    /// <returns>The set.</returns>
    internal static InstructionSet Create(
        string name,
        IsaDescription description,
        SortedDictionary<ulong, IsaEntry> entries,
        IsaRules rules,
        HashSet<string>? excluded,
        string? message,
        PostbyteCodec? postbytes,
        IReadOnlyList<ushort> entryPoints,
        IReadOnlyList<string> scopes)
    {
        InstructionSet set = new(name, description)
        {
            IndirectPageWrap = rules.IndirectPageWrap.Contains(name),
            Postbytes = postbytes,
            EntryPoints = entryPoints,
            HasEffects = rules.Effects.Count != 0
        };

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
            ushort? target = rules.Targets.TryGetValue($"{entry.Instruction}:{form.Name}", out ushort specificTarget)
                ? specificTarget
                : rules.Targets.TryGetValue(entry.Instruction, out ushort generalTarget) ? generalTarget : null;

            InstructionEffects effects = set.HasEffects
                ? EffectsOf(rules, scopes, entry.Instruction, form.Name)
                    ?? throw new FormatException($"Instruction set '{name}': no effects line gives {entry.Instruction} {form.Name}.")
                : default;

            set.Add(
                mnemonic,
                entry,
                form,
                flow,
                access,
                rules.Access.TryGetValue($"{entry.Instruction}:{form.Name}", out MemoryAccess specific) ? specific : access,
                rules.Preferred.Contains(entry.Opcode),
                target,
                rules.Conditional.Contains(entry.Instruction) || rules.Conditional.Contains($"{entry.Instruction}:{form.Name}"),
                effects);
        }

        foreach (KeyValuePair<string, string> alias in rules.Aliases)
        {
            set.AddAlias(alias.Key, alias.Value);
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

    // The nearest scope's Instruction:Form or Instruction line, which a form's own line in its nearest scope
    // adds to; null when no line gives the instruction.
    private static InstructionEffects? EffectsOf(IsaRules rules, IReadOnlyList<string> scopes, string instruction, string form)
    {
        InstructionEffects? effects = null;
        foreach (string scope in scopes)
        {
            if (!rules.Effects.TryGetValue(scope, out Dictionary<string, (InstructionEffects Effects, int Line)>? lines))
            {
                continue;
            }

            if (lines.TryGetValue($"{instruction}:{form}", out var specific) || lines.TryGetValue(instruction, out specific))
            {
                effects = specific.Effects;
                break;
            }
        }

        if (effects is not { } own) { return null; }
        foreach (string scope in scopes)
        {
            if (!rules.Effects.TryGetValue(scope, out Dictionary<string, (InstructionEffects Effects, int Line)>? lines)
                || !lines.TryGetValue($":{form}", out var added))
            {
                continue;
            }

            InstructionEffects other = added.Effects;
            return own with
            {
                RegistersRead = own.RegistersRead | other.RegistersRead,
                RegistersWritten = own.RegistersWritten | other.RegistersWritten,
                FlagsRead = (byte)(own.FlagsRead | other.FlagsRead),
                FlagsWritten = (byte)(own.FlagsWritten | other.FlagsWritten),
                FlagsSet = (byte)(own.FlagsSet | other.FlagsSet),
                FlagsCleared = (byte)(own.FlagsCleared | other.FlagsCleared),
                FlagsFromOperand = (byte)(own.FlagsFromOperand | other.FlagsFromOperand),
                OperandBits = own.OperandBits | other.OperandBits,
                Pushed = (byte)(own.Pushed + other.Pushed),
                Pulled = (byte)(own.Pulled + other.Pulled)
            };
        }

        return own;
    }
}
