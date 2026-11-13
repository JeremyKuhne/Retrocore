// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Globalization;

namespace Retrocore.Isa;

/// <summary>
///  Reads an instruction set description file.
/// </summary>
/// <remarks>
///  <para>
///   The file has an <c>[isa]</c> section (byte order, registers, flags and the words documentation names
///   them by, mnemonic rules and subsets), a
///   <c>[forms]</c> section (operand forms in matching order), and one section per instruction set holding
///   <c>opcode Mnemonic Form</c> lines. <c>[Name : Base]</c> starts from <c>Base</c>'s encodings and replaces
///   the opcodes it lists. <c>#</c> starts a comment outside quotes.
///  </para>
///  <para>
///   An opcode is one to four hex bytes. A <c>*</c> among them marks where the operand bytes go when the rest
///   of the opcode follows them, as in the Z80's <c>DD CB * 46</c>. With <c>literal-forms</c> set, an opcode
///   line may name an undeclared form, which becomes a literal form whose pattern is its name.
///  </para>
/// </remarks>
public static partial class IsaParser
{
    /// <summary>
    ///  Parses a description.
    /// </summary>
    /// <param name="text">The file's text.</param>
    /// <param name="postbytes">
    ///  Supplies each instruction set's <see cref="PostbyteCodec"/> by set name, for a description whose forms
    ///  have postbyte fields; without one, those forms do not decode.
    /// </param>
    /// <returns>The description, with its instruction sets.</returns>
    /// <exception cref="FormatException">The text is malformed; the message names the line.</exception>
    public static IsaDescription Parse(string text, Func<string, PostbyteCodec?>? postbytes = null)
    {
        Endianness endianness = Endianness.Little;
        int addressBits = 16;
        List<IsaRegister> registers = [];
        List<IsaFlag> flags = [];
        List<OperandForm> forms = [];
        IsaRules rules = new();
        List<(string Name, string Base, HashSet<string> Excluded, string Message)> subsets = [];
        Dictionary<string, (string? Base, SortedDictionary<ulong, IsaEntry> Entries)> sets = new(StringComparer.Ordinal);

        List<string> order = [];
        HashSet<string> formNames = new(StringComparer.Ordinal);
        HashSet<(string Section, ulong Key)> listed = [];
        string section = "";
        string[] lines = text.Replace("\r\n", "\n").Split('\n');
        for (int index = 0; index < lines.Length; index++)
        {
            int number = index + 1;
            List<string> tokens = Tokens(lines[index]);
            if (tokens.Count == 0) { continue; }
            // A header is the whole line in brackets; a form named like [IX+d] still has its quoted pattern.
            if (tokens[0].StartsWith('[') && tokens[^1].EndsWith(']'))
            {
                string header = string.Join(" ", tokens).Trim('[', ']');
                string[] parts = header.Split(':');
                section = parts[0].Trim();
                if (section is not ("isa" or "forms"))
                {
                    string? baseName = parts.Length > 1 ? parts[1].Trim() : null;
                    if (sets.ContainsKey(section) || (baseName is not null && !sets.ContainsKey(baseName)))
                    {
                        throw Error(number, $"Unknown, malformed, or duplicate section '{header}'.");
                    }

                    SortedDictionary<ulong, IsaEntry> entries = baseName is null
                        ? []
                        : new(sets[baseName].Entries);

                    sets[section] = (baseName, entries);
                    order.Add(section);
                }

                continue;
            }

            switch (section)
            {
                case "isa":
                    Setting(tokens, number, ref endianness, ref addressBits, registers, flags, rules, subsets);
                    break;
                case "forms":
                    if (!formNames.Add(tokens[0])) { throw Error(number, $"Duplicate form '{tokens[0]}'."); }
                    forms.Add(Form(tokens, number, checked((ushort)forms.Count), forms));
                    break;
                case "":
                    throw Error(number, "Expected a section.");
                default:
                    (uint opcode, byte length, byte splitAt, int next) = Opcode(tokens, number);
                    (bool undocumented, byte cycles, byte taken) = Options(tokens, next + 2, number);
                    string formName = tokens[next + 1];
                    if (rules.LiteralForms && !formNames.Contains(formName))
                    {
                        if (formName.Contains("{}"))
                        {
                            throw Error(number, $"Form '{formName}' has an expression; declare it in [forms].");
                        }

                        formNames.Add(formName);
                        forms.Add(new((ushort)forms.Count, formName, [formName], []));
                    }

                    // The length is part of the key, so a prefix byte and a longer opcode starting with it differ.
                    // A derived section replaces its base's opcodes, but lists each of its own only once.
                    ulong key = ((ulong)length << 32) | opcode;
                    if (!listed.Add((section, key))) { throw Error(number, "The section lists this opcode twice."); }
                    sets[section].Entries[key] = new(opcode, length, tokens[next], formName, undocumented, splitAt)
                    {
                        Cycles = cycles,
                        CyclesTaken = taken
                    };

                    break;
            }
        }

        IsaDescription description = new()
        {
            Endianness = endianness,
            AddressBits = addressBits,
            Registers = registers,
            Flags = flags,
            Forms = forms,
            Vectors = rules.Vectors,
            EntryPoints = rules.EntryPoints,
            AngleWidths = rules.AngleWidths
        };

        Dictionary<string, InstructionSet> result = new(StringComparer.OrdinalIgnoreCase);
        foreach (string name in order)
        {
            result[name] = InstructionSet.Create(
                name,
                description,
                sets[name].Entries,
                rules,
                excluded: null,
                message: null,
                postbytes?.Invoke(name));
        }

        foreach ((string name, string baseName, HashSet<string> excluded, string message) in subsets)
        {
            if (!sets.TryGetValue(baseName, out var source))
            {
                throw Error(0, $"Subset '{name}' names an unknown base '{baseName}'.");
            }

            result[name] = InstructionSet.Create(name, description, source.Entries, rules, excluded, message, postbytes?.Invoke(name));
        }

        description.InstructionSets = result;
        return description;
    }

    private static void Setting(
        List<string> tokens,
        int number,
        ref Endianness endianness,
        ref int addressBits,
        List<IsaRegister> registers,
        List<IsaFlag> flags,
        IsaRules rules,
        List<(string, string, HashSet<string>, string)> subsets)
    {
        switch (tokens[0])
        {
            case "endian":
                if (tokens.Count != 2 || tokens[1] is not ("big" or "little"))
                {
                    throw Error(number, "Expected 'endian little' or 'endian big'.");
                }

                endianness = tokens[1] == "big" ? Endianness.Big : Endianness.Little;
                break;
            case "address-bits":
                addressBits = tokens.Count == 2 && int.TryParse(tokens[1], NumberStyles.None, CultureInfo.InvariantCulture, out int bits)
                    ? bits
                    : throw Error(number, "Expected 'address-bits n'.");

                break;
            case "registers":
                for (int index = 1; index < tokens.Count; index++)
                {
                    string[] parts = tokens[index].Split(':');
                    if (parts.Length != 2 || !int.TryParse(parts[1], NumberStyles.None, CultureInfo.InvariantCulture, out int width))
                    {
                        throw Error(number, $"Expected 'Name:bits', not '{tokens[index]}'.");
                    }

                    registers.Add(new(parts[0], width));
                }

                break;
            case "flags":
                if (tokens.Count < 3) { throw Error(number, "Expected 'flags Register Name=bit ...'."); }
                for (int index = 2; index < tokens.Count; index++)
                {
                    string[] parts = tokens[index].Split('=');
                    if (parts.Length != 2 || !int.TryParse(parts[1], NumberStyles.None, CultureInfo.InvariantCulture, out int bit))
                    {
                        throw Error(number, $"Expected 'Name=bit', not '{tokens[index]}'.");
                    }

                    flags.Add(new(parts[0], tokens[1], bit));
                }

                break;
            case "flag":
                // flag Name word|word "what it means": the words documentation names the flag by.
                int flag = tokens.Count == 4 && tokens[3].StartsWith('"')
                    ? flags.FindIndex(known => known.Name == tokens[1])
                    : throw Error(number, "Expected 'flag Name word \"description\"'.");

                if (flag < 0) { throw Error(number, $"'{tokens[1]}' is not a flag the flags line lists."); }
                flags[flag] = flags[flag] with
                {
                    Words = tokens[2].Split('|'),
                    Description = Unquote(tokens[3])
                };

                break;
            case "bit-suffix":
                for (int index = 1; index < tokens.Count; index++) { rules.BitSuffix.Add(tokens[index]); }
                break;
            case "prefer":
                for (int index = 1; index < tokens.Count; index++)
                {
                    rules.Preferred.Add(uint.Parse(tokens[index], NumberStyles.HexNumber, CultureInfo.InvariantCulture));
                }

                break;
            case "subset":
                // subset Name of Base exclude A B C message "text with {0} for the operation"
                int of = tokens.IndexOf("of");
                int exclude = tokens.IndexOf("exclude");
                int message = tokens.IndexOf("message");
                if (of != 2 || exclude != 4 || message < exclude || message + 2 != tokens.Count)
                {
                    throw Error(number, "Expected 'subset Name of Base exclude ... message \"text\"'.");
                }

                HashSet<string> excluded = new(tokens.GetRange(5, message - 5), StringComparer.OrdinalIgnoreCase);
                subsets.Add((tokens[1], tokens[3], excluded, Unquote(tokens[message + 1])));
                break;
            case "flow":
                InstructionFlow flow = tokens.Count < 2 ? InstructionFlow.Next : tokens[1] switch
                {
                    "branch" => InstructionFlow.ConditionalBranch,
                    "jump" => InstructionFlow.Jump,
                    "indirect-jump" => InstructionFlow.IndirectJump,
                    "call" => InstructionFlow.Call,
                    "return" => InstructionFlow.Return,
                    "break" => InstructionFlow.Break,
                    "wait" => InstructionFlow.Wait,
                    "stop" => InstructionFlow.Stop,
                    _ => throw Error(number, $"Unknown flow class '{tokens[1]}'.")
                };

                if (flow == InstructionFlow.Next) { throw Error(number, "Expected 'flow class Instruction ...'."); }
                for (int index = 2; index < tokens.Count; index++) { rules.Flows[tokens[index]] = flow; }
                break;
            case "access":
                MemoryAccess access = tokens.Count < 2 ? MemoryAccess.Read : tokens[1] switch
                {
                    "write" => MemoryAccess.Write,
                    "read-write" => MemoryAccess.ReadWrite,
                    _ => throw Error(number, $"Unknown access '{tokens[1]}'; reads need no entry.")
                };

                if (access == MemoryAccess.Read) { throw Error(number, "Expected 'access kind Instruction ...'."); }
                for (int index = 2; index < tokens.Count; index++) { rules.Access[tokens[index]] = access; }
                break;
            case "literal-forms":
                rules.LiteralForms = tokens.Count == 1 ? true : throw Error(number, "Expected 'literal-forms'.");
                break;
            case "vectors":
                Addresses(tokens, number, rules.Vectors);
                break;
            case "entry-points":
                Addresses(tokens, number, rules.EntryPoints);
                break;
            case "indirect-page-wrap":
                for (int index = 1; index < tokens.Count; index++) { rules.IndirectPageWrap.Add(tokens[index]); }
                break;
            case "angle-widths":
                rules.AngleWidths = tokens.Count == 1 ? true : throw Error(number, "Expected 'angle-widths'.");
                break;
            case "alias":
                if (tokens.Count < 2) { throw Error(number, "Expected 'alias Alias=Mnemonic ...'."); }
                for (int index = 1; index < tokens.Count; index++)
                {
                    string[] parts = tokens[index].Split('=');
                    if (parts.Length != 2 || parts[0].Length == 0 || parts[1].Length == 0)
                    {
                        throw Error(number, $"Expected 'Alias=Mnemonic', not '{tokens[index]}'.");
                    }

                    rules.Aliases[parts[0]] = parts[1];
                }

                break;
            default:
                throw Error(number, $"Unknown setting '{tokens[0]}'.");
        }
    }

    private static void Addresses(List<string> tokens, int number, List<ushort> addresses)
    {
        for (int index = 1; index < tokens.Count; index++)
        {
            addresses.Add(ushort.TryParse(tokens[index], NumberStyles.HexNumber, CultureInfo.InvariantCulture, out ushort address)
                ? address
                : throw Error(number, $"Expected a hex address, not '{tokens[index]}'."));
        }
    }

    private static OperandForm Form(List<string> tokens, int number, ushort id, List<OperandForm> forms)
    {
        List<string> patterns = [];
        List<OperandFieldKind> fields = [];
        bool exclusive = false;
        bool narrow = false;
        bool indexed = false;
        OperandRole role = OperandRole.None;
        int narrowOf = -1;
        string? message = null;
        for (int index = 1; index < tokens.Count; index++)
        {
            string token = tokens[index];
            if (token.StartsWith('"'))
            {
                patterns.Add(Unquote(token));
            }
            else if (token == "exclusive")
            {
                exclusive = true;
            }
            else if (token == "narrow")
            {
                narrow = true;
            }
            else if (token == "indexed")
            {
                indexed = true;
            }
            else if (token is "memory" or "pointer")
            {
                role = token == "memory" ? OperandRole.Memory : OperandRole.Pointer;
            }
            else if (token.StartsWith("fields=", StringComparison.Ordinal))
            {
                foreach (string field in token[7..].Split(','))
                {
                    fields.Add(field switch
                    {
                        "byte" => OperandFieldKind.Byte,
                        "word" => OperandFieldKind.Word,
                        "rel8" => OperandFieldKind.Relative8,
                        "rel16" => OperandFieldKind.Relative16,
                        "disp8" => OperandFieldKind.Displacement8,
                        "bit" => OperandFieldKind.BitNumber,
                        "rst" => OperandFieldKind.Restart,
                        "rstn" => OperandFieldKind.RestartNumber,
                        "indexed" => OperandFieldKind.IndexedPostbyte,
                        "pair" => OperandFieldKind.RegisterPair,
                        "sysmask" => OperandFieldKind.SystemStackMask,
                        "usermask" => OperandFieldKind.UserStackMask,
                        _ => throw Error(number, $"Unknown field kind '{field}'.")
                    });
                }
            }
            else if (token.StartsWith("narrow-of=", StringComparison.Ordinal))
            {
                string wide = token[10..];
                narrowOf = forms.FindIndex(form => form.Name == wide);
                if (narrowOf < 0) { throw Error(number, $"'{wide}' must be a form declared earlier."); }
            }
            else if (token.StartsWith("message=", StringComparison.Ordinal))
            {
                message = Unquote(token[8..]);
            }
            else
            {
                throw Error(number, $"Unknown form option '{token}'.");
            }
        }

        if (patterns.Count == 0) { throw Error(number, $"Form '{tokens[0]}' needs a quoted pattern."); }
        foreach (string pattern in patterns)
        {
            int holes = OperandForm.HoleCount(pattern);
            if (pattern.Length != 0 && holes != fields.Count && !(holes == 1 && fields.Count > 1))
            {
                throw Error(number, $"Pattern \"{pattern}\" needs one hole per field, or one hole for a field list.");
            }
        }

        int opcodeFields = 0;
        foreach (OperandFieldKind field in fields)
        {
            if (OperandForm.IsOpcodeField(field)) { opcodeFields++; }
        }

        if (opcodeFields > 1) { throw Error(number, $"Form '{tokens[0]}' can hold only one field in the opcode."); }
        OperandForm result = new(id, tokens[0], patterns, fields)
        {
            Exclusive = exclusive,
            NarrowOf = narrowOf,
            IsNarrow = narrow || narrowOf >= 0,
            Role = role,
            IsIndexed = indexed,
            FieldMessage = message
        };

        if (narrowOf >= 0) { forms[narrowOf].Narrow = id; }
        return result;
    }

    // After the mnemonic and form: 'undocumented', and 't=n' or 't=taken/not' for the nominal clock cycles.
    private static (bool Undocumented, byte Cycles, byte Taken) Options(List<string> tokens, int start, int number)
    {
        const string Expected = "Expected 'opcode Mnemonic Form', optionally followed by 'undocumented' and 't=cycles'.";
        if (tokens.Count < start) { throw Error(number, Expected); }
        bool undocumented = false;
        byte cycles = 0;
        byte taken = 0;
        for (int index = start; index < tokens.Count; index++)
        {
            string token = tokens[index];
            if (token == "undocumented" && !undocumented)
            {
                undocumented = true;
                continue;
            }

            if (cycles != 0 || !token.StartsWith("t=", StringComparison.Ordinal)) { throw Error(number, Expected); }
            string[] parts = token[2..].Split('/');
            if (parts.Length > 2
                || !byte.TryParse(parts[0], NumberStyles.None, CultureInfo.InvariantCulture, out cycles)
                || cycles == 0)
            {
                throw Error(number, Expected);
            }

            // A conditional instruction lists its cycles when taken first; an unconditional one takes them always.
            taken = cycles;
            if (parts.Length == 2 && !byte.TryParse(parts[1], NumberStyles.None, CultureInfo.InvariantCulture, out cycles))
            {
                throw Error(number, Expected);
            }
        }

        return (undocumented, cycles, taken);
    }

    // Leading two-digit hex tokens are the opcode bytes; one '*' among them marks where the operand bytes go. A
    // mnemonic and a form always follow them, before any options, so a mnemonic that reads as hex, such as the
    // 8080's CC, is not taken for an opcode byte.
    private static (uint Opcode, byte Length, byte SplitAt, int Next) Opcode(List<string> tokens, int number)
    {
        int options = tokens.Count;
        while (options > 0 && (tokens[options - 1] == "undocumented" || tokens[options - 1].StartsWith("t=", StringComparison.Ordinal)))
        {
            options--;
        }

        int limit = options - 2;
        uint opcode = 0;
        int length = 0;
        int splitAt = 0;
        int index = 0;
        for (; index < limit; index++)
        {
            if (tokens[index] == "*" && splitAt == 0 && length > 0)
            {
                splitAt = length;
                continue;
            }

            if (length == 4 || !IsHexByte(tokens[index], out uint value)) { break; }
            opcode |= value << (length * 8);
            length++;
        }

        return length == 0
            ? throw Error(number, "Expected opcode bytes.")
            : splitAt == length
                ? throw Error(number, "'*' must come between opcode bytes.")
                : (opcode, (byte)length, (byte)splitAt, index);
    }

    private static bool IsHexByte(string token, out uint value)
    {
        value = 0;
        return token.Length == 2 && uint.TryParse(token, NumberStyles.HexNumber, CultureInfo.InvariantCulture, out value);
    }

    // Splits a line into tokens; quoted strings stay whole, and # outside quotes starts a comment.
    private static List<string> Tokens(string line)
    {
        List<string> tokens = [];
        int index = 0;
        while (index < line.Length)
        {
            char character = line[index];
            if (char.IsWhiteSpace(character))
            {
                index++;
                continue;
            }

            if (character == '#') { break; }
            int start = index;
            bool quoted = false;
            while (index < line.Length && (quoted || !char.IsWhiteSpace(line[index])))
            {
                if (line[index] == '"') { quoted = !quoted; }
                index++;
            }

            tokens.Add(line[start..index]);
        }

        return tokens;
    }

    private static string Unquote(string token) =>
        token.Length >= 2 && token[0] == '"' && token[^1] == '"' ? token[1..^1] : token;

    private static FormatException Error(int line, string message) =>
        new(line > 0 ? $"Line {line}: {message}" : message);
}
