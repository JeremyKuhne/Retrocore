// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Globalization;

namespace Retrocore.Isa;

public static partial class IsaParser
{
    private const string ExpectedEffects =
        "Expected 'effects [in Set] Instruction ... [reads ...] [writes ...] [may-write ...] [push|pull|may-push|may-pull [Register] n] [copies ...]', or '... none'.";

    // The register map effects lines share; the registers and flags lines must come before it.
    private static EffectRegisterMap Map(int number, List<IsaRegister> registers, List<IsaFlag> flags, IsaRules rules)
    {
        if (rules.EffectRegisters is { } existing) { return existing; }
        if (registers.Count > 32) { throw Error(number, "Effects describe at most 32 registers."); }
        rules.EffectRegisters = EffectRegisterMap.Create(registers, flags)
            ?? throw Error(number, "Effects need the flags line before them, naming one 8-bit register of the registers line.");

        return rules.EffectRegisters;
    }

    // parts Whole=Part,Part ...: what a register pair is made of, so writing HL writes H and L.
    private static void Parts(List<string> tokens, int number, List<IsaRegister> registers, List<IsaFlag> flags, IsaRules rules)
    {
        EffectRegisterMap map = Map(number, registers, flags, rules);
        if (tokens.Count < 2 || map.InUse)
        {
            throw Error(number, "Expected 'parts Register=Part,Part ...' before any effects line.");
        }

        for (int index = 1; index < tokens.Count; index++)
        {
            string[] halves = tokens[index].Split('=');
            string[] parts = halves.Length == 2 ? halves[1].Split(',') : [];
            if (parts.Length < 2 || Array.IndexOf(parts, "") >= 0)
            {
                throw Error(number, $"Expected 'Register=Part,Part', not '{tokens[index]}'.");
            }

            if (map.AddParts(halves[0], parts) is { } problem) { throw Error(number, problem); }
        }
    }

    // stack Register: the stack push and pull move through unless they name another.
    private static void Stack(List<string> tokens, int number, List<IsaRegister> registers, List<IsaFlag> flags, IsaRules rules)
    {
        EffectRegisterMap map = Map(number, registers, flags, rules);
        int bit = tokens.Count == 2 ? map.Names.IndexOf(tokens[1]) : -1;
        if (bit < 0 || map.Mask(tokens[1]) != 1u << bit || map.Stack >= 0)
        {
            throw Error(number, "Expected one 'stack Register', naming a register without parts.");
        }

        map.Stack = bit;
    }

    // effects [in Set] Instruction|Instruction:Form|:Form ... then reads, writes and may-write lists of registers,
    // flags by word and operand slots $n; push, pull, may-push and may-pull with an optional register and a count;
    // or none.
    private static void Effects(List<string> tokens, int number, List<IsaRegister> registers, List<IsaFlag> flags, IsaRules rules)
    {
        EffectRegisterMap map = Map(number, registers, flags, rules);
        map.InUse = true;
        int index = 1;
        string scope = "";
        if (tokens.Count > 2 && tokens[1] == "in")
        {
            scope = tokens[2];
            index = 3;
        }

        int first = index;
        while (index < tokens.Count && !IsEffectKeyword(tokens[index])) { index++; }
        if (index == first || index == tokens.Count) { throw Error(number, ExpectedEffects); }
        int keys = index;

        uint registersRead = 0, registersWritten = 0, registersMay = 0, operandBits = 0;
        byte flagsRead = 0, flagsWritten = 0, flagsMay = 0, set = 0, cleared = 0, fromOperand = 0;
        byte pushed = 0, pulled = 0, mayPush = 0, mayPull = 0, readSlots = 0, writeSlots = 0, maySlots = 0;
        byte pushSlot = 0, pullSlot = 0;
        List<(int Destination, int Source)> copies = [];
        int stack = -1;
        HashSet<string> seen = [];
        while (index < tokens.Count)
        {
            string keyword = tokens[index++];
            if (!seen.Add(keyword) || (keyword == "none" && (seen.Count > 1 || index != tokens.Count)))
            {
                throw Error(number, ExpectedEffects);
            }

            if (keyword is "push" or "pull" or "may-push" or "may-pull")
            {
                // An optional register names another stack than the description's, as the 6809's U.
                int own = map.Stack;
                if (index < tokens.Count && map.Mask(tokens[index]) is var named && named != 0)
                {
                    own = map.Names.IndexOf(tokens[index]);
                    if (own < 0 || named != 1u << own)
                    {
                        throw Error(number, $"'{tokens[index]}' is not a stack register.");
                    }

                    index++;
                }

                // A count, or an operand slot whose register list gives it, as the MC6809's PSHS.
                byte count = 0;
                if (index < tokens.Count && keyword is "push" or "pull" && Slot(tokens[index]) is var countSlot && countSlot != 0)
                {
                    if (keyword == "push") { pushSlot = countSlot; } else { pullSlot = countSlot; }
                }
                else
                {
                    count = index < tokens.Count
                        && byte.TryParse(tokens[index], NumberStyles.None, CultureInfo.InvariantCulture, out byte parsed)
                        && parsed != 0
                            ? parsed
                            : throw Error(number, $"Expected '{keyword} [Register] n', a byte count, or 'push|pull [Register] $n'.");
                }

                index++;
                if (own < 0)
                {
                    throw Error(number, $"'{keyword}' needs a 'stack' line, or a register of its own.");
                }

                if (stack >= 0 && own != stack)
                {
                    throw Error(number, "An instruction's pushes and pulls use one stack.");
                }

                stack = own;
                switch (keyword)
                {
                    case "push": pushed = count; break;
                    case "pull": pulled = count; break;
                    case "may-push": mayPush = count; break;
                    default: mayPull = count; break;
                }

                continue;
            }

            if (keyword == "copies")
            {
                // copies Destination=Source ...: a register, or $n for an operand, set to another's value.
                for (; index < tokens.Count && !IsEffectKeyword(tokens[index]); index++)
                {
                    string[] sides = tokens[index].Split('=');
                    int destination = sides.Length == 2 ? CopySide(sides[0], map) : int.MinValue;
                    int source = sides.Length == 2 ? CopySide(sides[1], map) : int.MinValue;
                    if (destination == int.MinValue || source == int.MinValue)
                    {
                        throw Error(number, $"Expected 'copies Register=Register', a register without parts or $n each, not '{tokens[index]}'.");
                    }

                    copies.Add((destination, source));
                }

                if (copies.Count is 0 or > 4) { throw Error(number, "Expected one to four copies."); }
                continue;
            }

            bool reads = keyword == "reads";
            bool may = keyword == "may-write";
            for (; index < tokens.Count && !IsEffectKeyword(tokens[index]); index++)
            {
                string token = tokens[index];
                if (Slot(token) is var slotNumber && slotNumber != 0)
                {
                    byte slot = (byte)(1 << (slotNumber - 1));
                    if (reads) { readSlots |= slot; } else if (may) { maySlots |= slot; } else { writeSlots |= slot; }
                    continue;
                }

                int equals = token.IndexOf('=');
                string name = equals < 0 ? token : token[..equals];
                uint mask = map.Mask(name);
                if (mask != 0 && equals < 0)
                {
                    byte all = map.FlagsOf(mask);
                    if (reads)
                    {
                        registersRead |= mask;
                        flagsRead |= all;
                    }
                    else if (may)
                    {
                        registersMay |= mask;
                        flagsMay |= all;
                    }
                    else
                    {
                        registersWritten |= mask;
                        flagsWritten |= all;
                    }

                    continue;
                }

                // Flags go by the words documentation names them by; one without words, by its name.
                int found = flags.FindIndex(flag => HasWord(flag, name) || (flag.Words.Count == 0 && flag.Name == name));
                if (found < 0)
                {
                    throw Error(number, $"'{name}' is not a register, or a flag by its word, in effects.");
                }

                byte bit = (byte)(1 << flags[found].Bit);
                if (!reads && !may)
                {
                    flagsWritten |= bit;
                }
                else if (equals >= 0)
                {
                    throw Error(number, $"Only written flags take a value, not '{token}'.");
                }
                else if (reads)
                {
                    flagsRead |= bit;
                }
                else
                {
                    flagsMay |= bit;
                }

                string value = equals < 0 ? "" : token[(equals + 1)..];
                if (value == "0") { cleared |= bit; }
                else if (value == "1") { set |= bit; }
                else if (value.Length == 4 && value.StartsWith("bit", StringComparison.Ordinal) && value[3] is >= '0' and <= '7')
                {
                    fromOperand |= bit;
                    operandBits |= (uint)(value[3] - '0' + 1) << (flags[found].Bit * 4);
                }
                else if (equals >= 0)
                {
                    throw Error(number, $"Expected flag=0, flag=1 or flag=bitN, not '{token}'.");
                }
            }
        }

        // What is written on every path is not also written on some.
        registersMay &= ~registersWritten;
        flagsMay = (byte)(flagsMay & ~flagsWritten);
        maySlots = (byte)(maySlots & ~writeSlots);
        if (stack >= 0)
        {
            uint bit = 1u << stack;
            bool always = (pushed | pulled | pushSlot | pullSlot) != 0;
            if ((registersRead & bit) == 0 || ((always ? registersWritten : registersWritten | registersMay) & bit) == 0)
            {
                throw Error(number, $"Pushes and pulls read and write {map.Names[stack]}; list it in reads and in writes or may-write.");
            }
        }

        InstructionEffects effects = new()
        {
            IsKnown = true,
            RegistersRead = registersRead,
            RegistersWritten = registersWritten,
            RegistersMayWrite = registersMay,
            FlagsRead = flagsRead,
            FlagsWritten = flagsWritten,
            FlagsMayWrite = flagsMay,
            FlagsSet = set,
            FlagsCleared = cleared,
            FlagsFromOperand = fromOperand,
            OperandBits = operandBits,
            Pushed = pushed,
            Pulled = pulled,
            MayPush = mayPush,
            MayPull = mayPull,
            StackRegisterPlusOne = (byte)(stack + 1)
        };

        // Copies between registers are kept now; those naming an operand wait for its encoding.
        List<(int Destination, int Source)> slotCopies = [];
        foreach ((int destination, int source) in copies)
        {
            if (destination >= 0 && source >= 0) { effects = effects.WithCopy(destination, source); }
            else { slotCopies.Add((destination, source)); }
        }

        if (!rules.Effects.TryGetValue(scope, out Dictionary<string, EffectsLine>? scoped))
        {
            scoped = [with(StringComparer.OrdinalIgnoreCase)];
            rules.Effects[scope] = scoped;
        }

        for (int key = first; key < keys; key++)
        {
            string name = tokens[key];
            int colon = name.IndexOf(':');
            if (colon == name.Length - 1 || name.IndexOf(':', colon + 1) >= 0 || scoped.ContainsKey(name))
            {
                throw Error(number, $"Effects for '{name}' are malformed or already given.");
            }

            scoped[name] = new(effects, number)
            {
                ReadSlots = readSlots,
                WriteSlots = writeSlots,
                MayWriteSlots = maySlots,
                PushSlot = pushSlot,
                PullSlot = pullSlot,
                SlotCopies = slotCopies
            };
        }
    }

    // $1 to $8 as 1 to 8, or 0 for any other token.
    private static byte Slot(string token) =>
        token.Length == 2 && token[0] == '$' && token[1] is >= '1' and <= '8' ? (byte)(token[1] - '0') : (byte)0;

    private static bool HasWord(IsaFlag flag, string word)
    {
        foreach (string known in flag.Words)
        {
            if (known == word) { return true; }
        }

        return false;
    }

    private static bool IsEffectKeyword(string token) =>
        token is "reads" or "writes" or "may-write" or "push" or "pull" or "may-push" or "may-pull" or "copies" or "none";

    // A side of a copy: a register without parts by its bit, or an operand slot as minus its number.
    private static int CopySide(string token, EffectRegisterMap map)
    {
        if (Slot(token) is var slot && slot != 0) { return -slot; }
        int bit = map.Names.IndexOf(token);
        return bit >= 0 && map.Mask(token) == 1u << bit ? bit : int.MinValue;
    }

    // Each effects line names a known set, and some encoding takes it, so a misspelling or a line every set
    // overrides fails.
    private static void CheckEffects(IsaRules rules, Dictionary<string, InstructionSet> sets)
    {
        foreach (KeyValuePair<string, Dictionary<string, EffectsLine>> scope in rules.Effects)
        {
            if (scope.Key.Length != 0 && !sets.ContainsKey(scope.Key))
            {
                throw Error(0, $"Effects name an unknown instruction set '{scope.Key}'.");
            }

            foreach (KeyValuePair<string, EffectsLine> entry in scope.Value)
            {
                if (!entry.Value.Used)
                {
                    throw Error(entry.Value.Line, $"No encoding takes the effects for '{entry.Key}'.");
                }
            }
        }
    }
}
