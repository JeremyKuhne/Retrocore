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

        if (set.HasEffects && set._effects is { } list) { list.Capacity = entries.Count; }
        if (rules.EffectRegisters is { FlagsRegister: >= 0 } map)
        {
            set._flagsRegisterMask = 1u << map.FlagsRegister;
            set._allFlags = map.AllFlags;
        }

        // The :Form keys effects are looked up by, built once per form rather than once per encoding.
        string?[] formKeys = new string?[description.Forms.Count];
        foreach (IsaEntry entry in entries.Values)
        {
            OperandForm form = description.Form(entry.Form)
                ?? throw new FormatException($"Instruction set '{name}': unknown form '{entry.Form}' for {entry.Instruction}.");

            string mnemonic = rules.BitSuffix.Contains(entry.Instruction)
                ? entry.Instruction + ((entry.Opcode >> 4) & 7).ToString(CultureInfo.InvariantCulture)
                : entry.Instruction;

            string specificKey = $"{entry.Instruction}:{form.Name}";
            // A form-qualified flow class overrides the instruction's own.
            InstructionFlow flow = rules.Flows.TryGetValue(specificKey, out InstructionFlow specificFlow)
                ? specificFlow
                : rules.Flows.TryGetValue(entry.Instruction, out InstructionFlow generalFlow) ? generalFlow : InstructionFlow.Next;

            MemoryAccess access = rules.Access.TryGetValue(entry.Instruction, out MemoryAccess general) ? general : MemoryAccess.Read;
            ushort? target = rules.Targets.TryGetValue(specificKey, out ushort specificTarget)
                ? specificTarget
                : rules.Targets.TryGetValue(entry.Instruction, out ushort generalTarget) ? generalTarget : null;

            InstructionEffects effects = default;
            if (set.HasEffects)
            {
                string formKey = formKeys[form.Id] ??= ":" + form.Name;
                effects = EffectsOf(rules, scopes, entry.Instruction, specificKey, formKey, form.Name, out PostbyteRule rule)
                    ?? throw new FormatException($"Instruction set '{name}': no effects line gives {entry.Instruction} {form.Name}.");

                // A postbyte field's registers come from the codec per decoded postbyte, an indexed one's always.
                bool named = rule.Slots != 0 || (form.HasPostbyte && form.Field(0) == OperandFieldKind.IndexedPostbyte);
                if (postbytes is not null && form.HasPostbyte && named && set.PostbyteTable(form.Field(0), postbytes))
                {
                    effects = effects with { DependsOnPostbyte = true };
                    (set._postbyteRules ??= [])[set._encodings.Count] = rule with { Kind = form.Field(0) };
                }
            }

            set.Add(
                mnemonic,
                entry,
                form,
                flow,
                access,
                rules.Access.TryGetValue(specificKey, out MemoryAccess specific) ? specific : access,
                rules.Preferred.Contains(entry.Opcode),
                target,
                rules.Conditional.Contains(entry.Instruction) || rules.Conditional.Contains(specificKey),
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
    // adds to; null when no line gives the instruction. The keys are built once per encoding, not per scope.
    private static InstructionEffects? EffectsOf(
        IsaRules rules,
        IReadOnlyList<string> scopes,
        string instruction,
        string instructionAndForm,
        string formKey,
        string form,
        out PostbyteRule rule)
    {
        rule = default;
        EffectsLine? own = null;
        foreach (string scope in scopes)
        {
            if (rules.Effects.TryGetValue(scope, out Dictionary<string, EffectsLine>? lines)
                && (lines.TryGetValue(instructionAndForm, out own) || lines.TryGetValue(instruction, out own)))
            {
                break;
            }
        }

        if (own is null) { return null; }
        own.Used = true;
        rule = rule.With(own);
        InstructionEffects effects = Resolve(rules, own, form);
        foreach (string scope in scopes)
        {
            if (!rules.Effects.TryGetValue(scope, out Dictionary<string, EffectsLine>? lines)
                || !lines.TryGetValue(formKey, out EffectsLine? added))
            {
                continue;
            }

            added.Used = true;
            rule = rule.With(added);
            return Combine(effects, Resolve(rules, added, form));
        }

        return effects;
    }

    // A line's effects with its operand slots filled in from the form's name, such as A and [HL] for A,[HL].
    private static InstructionEffects Resolve(IsaRules rules, EffectsLine line, string form)
    {
        InstructionEffects effects = line.Effects;
        if (!line.HasSlots || rules.EffectRegisters is not { } map)
        {
            return effects;
        }

        uint read = 0, written = 0, may = 0;
        Span<int> registers = [-1, -1, -1, -1, -1, -1, -1, -1];
        int slot = 0;
        for (int start = 0; start <= form.Length && slot < 8; slot++)
        {
            int end = form.IndexOf(',', start);
            if (end < 0) { end = form.Length; }
            string operand = form[start..end];
            start = end + 1;
            uint single = map.Mask(operand);
            if (single != 0 && (single & (single - 1)) == 0) { registers[slot] = BitIndex(single); }
            byte bit = (byte)(1 << slot);
            if ((bit & (line.ReadSlots | line.WriteSlots | line.MayWriteSlots)) == 0) { continue; }

            // A bracketed operand is memory, whose address register is read wherever the line names it.
            if (operand.Length > 2 && operand[0] == '[' && operand[^1] == ']')
            {
                string inside = operand[1..^1];
                int offset = inside.IndexOfAny(['+', '-']);
                read |= map.Mask(offset < 0 ? inside : inside[..offset]);
                continue;
            }

            uint mask = map.Mask(operand);
            if ((line.ReadSlots & bit) != 0) { read |= mask; }
            if ((line.WriteSlots & bit) != 0) { written |= mask; }
            else if ((line.MayWriteSlots & bit) != 0) { may |= mask; }
        }

        // A copy between operands that are registers without parts, as LD A,B; others, as LD A,[HL], copy nothing.
        foreach ((int destination, int source) in line.SlotCopies)
        {
            int to = destination >= 0 ? destination : registers[-destination - 1];
            int from = source >= 0 ? source : registers[-source - 1];
            if (to >= 0 && from >= 0 && to != from) { effects = effects.WithCopy(to, from); }
        }

        return Combine(effects, new InstructionEffects
        {
            RegistersRead = read,
            RegistersWritten = written,
            RegistersMayWrite = may,
            FlagsRead = map.FlagsOf(read),
            FlagsWritten = map.FlagsOf(written),
            FlagsMayWrite = map.FlagsOf(may)
        });
    }

    private static int BitIndex(uint single)
    {
        int index = 0;
        while ((single & 1) == 0)
        {
            single >>= 1;
            index++;
        }

        return index;
    }

    private static InstructionEffects Combine(InstructionEffects effects, InstructionEffects other)
    {
        uint written = effects.RegistersWritten | other.RegistersWritten;
        byte flagsWritten = (byte)(effects.FlagsWritten | other.FlagsWritten);
        InstructionEffects combined = effects with
        {
            RegistersRead = effects.RegistersRead | other.RegistersRead,
            RegistersWritten = written,
            RegistersMayWrite = (effects.RegistersMayWrite | other.RegistersMayWrite) & ~written,
            FlagsRead = (byte)(effects.FlagsRead | other.FlagsRead),
            FlagsWritten = flagsWritten,
            FlagsMayWrite = (byte)((effects.FlagsMayWrite | other.FlagsMayWrite) & ~flagsWritten),
            FlagsSet = (byte)(effects.FlagsSet | other.FlagsSet),
            FlagsCleared = (byte)(effects.FlagsCleared | other.FlagsCleared),
            FlagsFromOperand = (byte)(effects.FlagsFromOperand | other.FlagsFromOperand),
            OperandBits = effects.OperandBits | other.OperandBits,
            Pushed = (byte)(effects.Pushed + other.Pushed),
            Pulled = (byte)(effects.Pulled + other.Pulled),
            MayPush = (byte)(effects.MayPush + other.MayPush),
            MayPull = (byte)(effects.MayPull + other.MayPull),
            StackRegisterPlusOne = effects.StackRegisterPlusOne != 0 ? effects.StackRegisterPlusOne : other.StackRegisterPlusOne,
            ConditionFlags = effects.ConditionFlags != 0 ? effects.ConditionFlags : other.ConditionFlags,
            ConditionTable = effects.ConditionFlags != 0 ? effects.ConditionTable : other.ConditionTable
        };

        return combined.WithCopies(other);
    }
}
