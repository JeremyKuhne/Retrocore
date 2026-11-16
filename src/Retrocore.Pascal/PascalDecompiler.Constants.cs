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

    // The type a key's values are of: a variable's or parameter's (what a VAR one points to), a field's or a type's,
    // or, for an array or a set, its elements'.
    private TypeNode? Valued(string key, Dictionary<string, TypeNode> byName)
    {
        // A field's integer view, T35.F2.I: a type of its own, for the uses of that word only.
        Match view = ViewHint().Match(key);
        if (view.Success)
        {
            if (!byName.TryGetValue(view.Groups["type"].Value, out TypeNode? holder)
                || FieldOffset(holder, view.Groups["field"].Value) is not { } viewed)
            {
                return null;
            }

            TypeNode integer = TypeNode.Scalar(ScalarKind.Integer);
            _viewValues[(holder.Find(), viewed)] = integer;
            return integer;
        }

        if (FieldKey(key) is ({ } typeName, { } field))
        {
            return byName.TryGetValue(typeName, out TypeNode? record) && FieldType(record, field) is { } fieldType ? Elements(fieldType) : null;
        }

        if (byName.TryGetValue(key, out TypeNode? named)) { return Elements(named); }

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
        return variable is null ? null : Elements(variable.IsReference ? variable.Type.Target() : variable.Type);
    }

    // The type whose values a type's are named by: an array's (an array of arrays') elements', a set's members'; else
    // its own.
    private static TypeNode Elements(TypeNode type)
    {
        TypeNode root = type.Find();
        while (root.Kind == TypeKind.Array && root.Element is { } element) { root = element.Find(); }
        return root.Kind == TypeKind.Set && root.Element is { } member ? member.Find() : root;
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

    // The integer views of words used both ways whose values are named, by the record and the word they are at
    // (T35.F2.I, an ATTR's CVAL read as its ACCESS): each is a type of its own, which _valueNames names.
    private readonly Dictionary<(TypeNode Record, int Offset), TypeNode> _viewValues = [];

    // While a constant set is written, the type its members are written as: the elements of the set it is compared
    // with, joined with or passed for, whose values are named.
    private TypeNode? _elementOverride;

    // Whether a type's values are named.
    private bool ValueNamed(TypeNode? type) => type is not null && _valueNames.ContainsKey(type.Find());

    // The type of a word's integer view whose values are named, where an expression loads one.
    private TypeNode? ViewValued(Expr expression) =>
        expression is Load { Designator: var designator } && IsPunned(designator.Type) ? ViewValued(designator) : null;

    private TypeNode? ViewValued(Designator designator) => designator switch
    {
        FieldDesignator field => _viewValues.GetValueOrDefault((field.Record.Type.Find(), field.Offset)),
        VariableDesignator { Variable: { Container: { } container } word } =>
            _viewValues.GetValueOrDefault((container.Type.Find(), word.FieldOffset)),
        _ => null
    };

    // A record's field's word, by the field's name as the decompiler gives it.
    private int? FieldOffset(TypeNode record, string field)
    {
        TypeNode root = record.Find();
        IEnumerable<int> offsets = (root.Fields?.Keys ?? Enumerable.Empty<int>()).Union(root.Variants?.Keys ?? Enumerable.Empty<int>());
        foreach (int offset in offsets)
        {
            for (int index = 0; index < root.Alternatives(offset).Count; index++)
            {
                if (string.Equals(OwnFieldName(root, offset, index), field, StringComparison.OrdinalIgnoreCase))
                {
                    return offset;
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

        foreach (IGrouping<string, KeyValuePair<(string Type, int Label), string>> type in _labelNames.GroupBy(label => label.Key.Type))
        {
            lines.Add($"  (* {_types.FirstOrDefault(named => _typeKeys.GetValueOrDefault(named) == type.Key)?.Name ?? type.Key}'s variants *)");
            lines.AddRange(type.OrderBy(label => label.Key.Label).Select(label => $"  {label.Value} = {label.Key.Label.ToString(CultureInfo.InvariantCulture)};"));
        }

        return string.Concat(lines.Select(line => $"{line}\n"));
    }

    // The names the hints give records' variants' labels, by the decompiler's names for their types and the labels:
    // T2:109 (NEW's variant 9 words long).
    private readonly SortedDictionary<(string Type, int Label), string> _labelNames = [];

    // Names the labels of records' variants as the hints do, each a constant unlike every other name the source has.
    private void NameVariantLabels(HashSet<string> taken)
    {
        foreach ((string key, string given) in _options.Names)
        {
            Match match = LabelHint().Match(key);
            if (!match.Success || !_typeKeys.ContainsValue(match.Groups["type"].Value.ToUpperInvariant())) { continue; }

            int label = int.Parse(match.Groups["label"].Value, CultureInfo.InvariantCulture);
            if (Unique(given, key, taken, out string name))
            {
                _labelNames[(match.Groups["type"].Value.ToUpperInvariant(), label)] = name;
            }
        }
    }

    // A variant's label, by its name where the hints give one.
    private string VariantLabel(TypeNode record, int label) =>
        _typeKeys.TryGetValue(record.Find(), out string? type) && _labelNames.TryGetValue((type, label), out string? name)
            ? name
            : label.ToString(CultureInfo.InvariantCulture);

    [GeneratedRegex("^(?<type>T[0-9]+)\\.(?<field>[A-Za-z][A-Za-z0-9]*)\\.(?<view>[A-Za-z][A-Za-z0-9]*)$", RegexOptions.IgnoreCase)]
    private static partial Regex ViewHint();

    [GeneratedRegex("^(?<type>T[0-9]+):(?<label>[0-9]+)$", RegexOptions.IgnoreCase)]
    private static partial Regex LabelHint();

    // A variable's hint key: its procedure's key, or SYSTEM, an at sign, and its word.
    [GeneratedRegex("^(?<owner>.+)@(?<word>\\$[0-9A-Fa-f]+|[0-9]+)$")]
    private static partial Regex VariableHint();
}
