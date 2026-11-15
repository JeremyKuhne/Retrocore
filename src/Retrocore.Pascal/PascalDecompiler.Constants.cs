// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Globalization;
using System.Text.RegularExpressions;

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    // The names the hints give the values of types, by type: a constant of one is written by its name.
    private readonly Dictionary<TypeNode, IReadOnlyList<string>> _valueNames = [];

    // The lists of constants declared, in the hints' order, with their names.
    private readonly List<(string List, IReadOnlyList<string> Names)> _declaredConstants = [];

    // Names the values of the variables, fields and types the hints give a list of constants for. A constant loads as
    // the number it stands for, so the code is the same; each name, which reaches every procedure, must be unlike
    // every other name the source has, or its list is left out and its values are written as numbers.
    private void NameValues(HashSet<string> taken)
    {
        if (_options.Values.Count == 0) { return; }

        Dictionary<string, TypeNode> byName = new(StringComparer.OrdinalIgnoreCase);
        foreach ((TypeNode type, string key) in _typeKeys) { byName[key] = type; }

        Dictionary<string, List<TypeNode>> typed = new(StringComparer.OrdinalIgnoreCase);
        foreach ((string key, string list) in _options.Values)
        {
            if (!_options.Constants.ContainsKey(list))
            {
                Warn($"The constants {list} for {key} are not given.");
                continue;
            }

            if (Valued(key, byName) is not { } type)
            {
                Warn($"The values of {key} cannot be named: the source has nothing by that key.");
                continue;
            }

            if (!typed.TryGetValue(list, out List<TypeNode>? types))
            {
                types = [];
                typed[list] = types;
            }

            types.Add(type.Find());
        }

        foreach ((string list, IReadOnlyList<string> names) in _options.Constants)
        {
            if (!typed.TryGetValue(list, out List<TypeNode>? types)) { continue; }

            HashSet<string> own = [];
            bool unique = true;
            foreach (string name in names.Where(name => name.Length > 0))
            {
                // A name twice in one list is the same clash as one another name has.
                unique &= own.Add(Key(name)) && Unique(name, $"{list}'s constant", taken, out _);
            }

            if (!unique)
            {
                Warn($"The constants {list} are left out; their values are written as numbers.");
                continue;
            }

            _declaredConstants.Add((list, names));
            foreach (TypeNode type in types) { _valueNames[type] = names; }
        }
    }

    // The type a key's values are of: a variable's or parameter's (what a VAR one points to), a field's, a type's, or
    // the elements of a set type.
    private TypeNode? Valued(string key, Dictionary<string, TypeNode> byName)
    {
        if (FieldKey(key) is ({ } typeName, { } field))
        {
            return byName.TryGetValue(typeName, out TypeNode? record) ? FieldType(record, field) : null;
        }

        if (byName.TryGetValue(key, out TypeNode? named))
        {
            TypeNode root = named.Find();
            return root.Kind == TypeKind.Set ? root.Element : root;
        }

        Match match = VariableHint().Match(key);
        if (!match.Success) { return null; }

        string word = match.Groups["word"].Value;
        int offset = word.StartsWith('$')
            ? int.Parse(word.AsSpan(1), NumberStyles.HexNumber, CultureInfo.InvariantCulture)
            : int.Parse(word, CultureInfo.InvariantCulture);

        string owner = match.Groups["owner"].Value;
        IEnumerable<Variable> variables = string.Equals(owner, "SYSTEM", StringComparison.OrdinalIgnoreCase)
            ? _declared.GetValueOrDefault(_system) ?? []
            : _procedures
                .Where(procedure => string.Equals($"{procedure.Segment.Name.Trim()}.{procedure.Number}", owner, StringComparison.OrdinalIgnoreCase))
                .SelectMany(procedure => _parameters[procedure].Concat(_declared[procedure.Frame]));

        Variable? variable = variables.FirstOrDefault(variable => variable.Offset == offset);
        return variable is null ? null : variable.IsReference ? variable.Type.Target() : variable.Type;
    }

    // A record's field's type, by the field's name as the decompiler gives it.
    private TypeNode? FieldType(TypeNode record, string field)
    {
        TypeNode root = record.Find();
        IEnumerable<int> offsets = (root.Fields?.Keys ?? Enumerable.Empty<int>()).Union(root.Variants?.Keys ?? Enumerable.Empty<int>());
        foreach (int offset in offsets)
        {
            List<TypeNode> alternatives = root.Alternatives(offset);
            for (int index = 0; index < alternatives.Count; index++)
            {
                if (string.Equals(OwnFieldName(root, offset, index), field, StringComparison.OrdinalIgnoreCase))
                {
                    return alternatives[index];
                }
            }
        }

        return null;
    }

    // A value's name, where its type's values are named.
    private string? ValueName(int value, TypeNode? type) =>
        type is not null && _valueNames.TryGetValue(type.Find(), out IReadOnlyList<string>? names) && value >= 0 && value < names.Count && names[value].Length > 0
            ? names[value]
            : null;

    // The CONST declarations of the lists of constants, each list's names in order of their values, a few to a line.
    private string ConstantDeclarations()
    {
        List<string> lines = [];
        foreach ((string list, IReadOnlyList<string> names) in _declaredConstants)
        {
            lines.Add($"  (* {list} *)");
            List<string> constants = [.. names.Select((name, value) => name.Length == 0 ? "" : $"{name} = {value.ToString(CultureInfo.InvariantCulture)};").Where(text => text.Length > 0)];
            string line = "";
            foreach (string constant in constants)
            {
                if (line.Length > 0 && line.Length + constant.Length + 1 > 110)
                {
                    lines.Add($"  {line}");
                    line = "";
                }

                line = line.Length == 0 ? constant : $"{line} {constant}";
            }

            if (line.Length > 0) { lines.Add($"  {line}"); }
        }

        return string.Concat(lines.Select(line => $"{line}\n"));
    }

    // A variable's hint key: its procedure's key, or SYSTEM, an at sign, and its word.
    [GeneratedRegex("^(?<owner>.+)@(?<word>\\$[0-9A-Fa-f]+|[0-9]+)$")]
    private static partial Regex VariableHint();
}
