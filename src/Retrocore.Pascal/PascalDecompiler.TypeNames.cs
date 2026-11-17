// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.RegularExpressions;

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    // The decompiler's own names for the types the hints name, by type: T2.
    private readonly Dictionary<TypeNode, string> _typeKeys = [];

    // The names hints give fields, by the decompiler's names for their type and for them: T2 and F0.
    private readonly Dictionary<(string Type, string Field), string> _fieldNames = [];

    // The records whose fields the hints name or comment, which are written a field to a line.
    private readonly HashSet<string> _hintedRecords = [with(StringComparer.OrdinalIgnoreCase)];

    // Names types and their fields as the hints do: a type by the decompiler's name for it, T2, and a field by its
    // type's and its own, T2.F0. Fields go by name alone inside a WITH, where they hide any other name, and a type's
    // name reaches every procedure, so each name given must be unlike every other name the source has in its first
    // eight letters: the procedures', the variables', the other types' and fields', and the predeclared words.
    private void NameTypesFromHints()
    {
        if (_options.Names.Count == 0 && _options.Comments.Count == 0 && _options.Values.Count == 0) { return; }

        HashSet<string> taken = Taken();
        Dictionary<string, TypeNode> byName = [with(StringComparer.OrdinalIgnoreCase)];
        foreach (TypeNode type in _types)
        {
            string own = type.Name ?? "";
            _typeKeys[type] = own;
            byName[own] = type;
        }

        foreach (TypeNode type in _types)
        {
            string own = _typeKeys[type];
            if (Given(own) is { } given && Unique(given, own, taken, out string name)) { type.Name = name; }
        }

        foreach (string key in _options.Names.Keys.Union(_options.Comments.Keys, StringComparer.OrdinalIgnoreCase))
        {
            if (FieldKey(key) is not ({ } type, { } field) || !byName.ContainsKey(type)) { continue; }

            _hintedRecords.Add(type);
            if (Given(key) is { } given
                && !_fieldNames.ContainsKey((type, field))
                && Unique(given, key, taken, out string name))
            {
                _fieldNames[(type, field)] = name;
            }
        }

        NameValues(taken);
        NameVariantLabels(taken);
    }

    // A field's key, T2.F0, as its type's name and its own; null for others, such as a procedure's, PASCALCO.4.
    private static (string? Type, string? Field) FieldKey(string key)
    {
        Match match = FieldHint().Match(key);
        return match.Success ? (match.Groups["type"].Value.ToUpperInvariant(), match.Groups["field"].Value.ToUpperInvariant()) : (null, null);
    }

    // Whether a type's or a field's name can be given: an identifier unlike any other the source has.
    private bool Unique(string given, string key, HashSet<string> taken, out string name)
    {
        name = new string([.. given.Where(char.IsAsciiLetterOrDigit)]);
        string? clash = name.Length == 0 || !char.IsAsciiLetter(name[0])
            ? "no identifier"
            : s_predeclared.Contains(Key(name))
                ? Key(name)
                : DecompilerName().IsMatch(name) || GeneratedField().IsMatch(name)
                    ? "the decompiler's names for types, fields and constants"
                    : taken.Contains(Key(name)) ? "another name the source has" : null;

        if (clash is null)
        {
            taken.Add(Key(name));
            return true;
        }

        Warn($"The name {given} for {key} would clash with {clash}; it is left as the decompiler names it.");
        return false;
    }

    // The first eight letters of every name the source has: its procedures', variables' and parameters', the
    // system's globals' and procedures', the library units', and the types' as the decompiler names them.
    private HashSet<string> Taken()
    {
        HashSet<string> taken = [];
        foreach (Procedure procedure in _procedures)
        {
            taken.Add(Key(procedure.Name));
            foreach (Variable variable in _parameters[procedure].Concat(_declared[procedure.Frame]))
            {
                taken.Add(Key(variable.Name));
            }
        }

        foreach (Variable global in _declared.GetValueOrDefault(_system) ?? []) { taken.Add(Key(global.Name)); }
        foreach (int number in _systemProcedures.Keys) { taken.Add(Key(SystemName(SystemProcedure(number)) ?? "")); }
        foreach (string name in _systemNames.Values) { taken.Add(Key(name)); }
        foreach (string name in UnitNames()) { taken.Add(Key(name)); }
        foreach (TypeNode type in _types) { taken.Add(Key(type.Name ?? "")); }
        if (_shell is not null) { taken.Add(Key(Identifier(_shell.Name))); }
        return taken;
    }

    // A field's name as the hints give it, or the decompiler's own.
    private string HintedField(TypeNode record, string generated) =>
        _typeKeys.TryGetValue(record.Find(), out string? type) && _fieldNames.TryGetValue((type, generated.ToUpperInvariant()), out string? name)
            ? name
            : generated;

    // The comment the hints give a field, by its type's and its own names as the decompiler writes them.
    private string? FieldComment(TypeNode record, string generated) =>
        _typeKeys.TryGetValue(record.Find(), out string? type) ? Comment(_options.Comments, $"{type}.{generated}") : null;

    // The comment the hints give a type, by the decompiler's name for it.
    private string? TypeComment(TypeNode type) =>
        _typeKeys.TryGetValue(type.Find(), out string? key) ? Comment(_options.Comments, key) : null;

    // Whether a record's fields are written a line each, with their comments: where the hints name or comment one.
    private bool Spread(TypeNode record) =>
        _typeKeys.TryGetValue(record.Find(), out string? key) && _hintedRecords.Contains(key);

    // A field's declaration, with its comment after a marker that Fields turns into a comment where the record is
    // spread over lines, and drops where it is not.
    private string Field(TypeNode record, string generated, string type)
    {
        string declaration = $"{HintedField(record, generated)}: {type}";
        return FieldComment(record, generated) is { } comment ? $"{declaration}{CommentMarker}{comment}" : declaration;
    }

    private const char CommentMarker = '\u0001';

    // A record's fields, one line each with its comment where the record is spread, or on one line.
    private string Fields(TypeNode record, List<string> parts, string indent)
    {
        if (!Spread(record)) { return string.Join("; ", parts.Select(part => part.Split(CommentMarker)[0])); }

        IEnumerable<string> lines = parts.Select((part, index) =>
        {
            string[] pieces = part.Split(CommentMarker);
            string end = index < parts.Count - 1 ? ";" : "";
            return pieces.Length > 1 ? $"{pieces[0]}{end}  {CommentText(pieces[1])}" : $"{pieces[0]}{end}";
        });

        return string.Join($"\n{indent}", lines);
    }

    // A comment as Pascal writes one, which cannot hold its own end.
    private static string CommentText(string text) => $"(* {text.Replace("*)", "* )", StringComparison.Ordinal)} *)";

    // The names the library's units give their procedures, types' values and themselves.
    private IEnumerable<string> UnitNames() =>
        _unitOrder.Select(segment => _library?.Unit(segment)).OfType<PascalUnit>().SelectMany(unit =>
            unit.Procedures.Select(procedure => procedure.Name)
                .Concat(unit.Enumerations.Keys)
                .Concat(unit.Enumerations.Values.SelectMany(values => values))
                .Append(unit.Name));

    // A field's hint key: a type's name as the decompiler gives it, a dot, and the field's.
    [GeneratedRegex("^(?<type>T[0-9]+)\\.(?<field>[A-Za-z][A-Za-z0-9]*)$")]
    private static partial Regex FieldHint();

    // The decompiler's own names for fields: F0, T2F6V1, X8V1, F0B12, X12N, B9N, and a word's views I, P, B, P2.
    [GeneratedRegex("^((T[0-9]+)?[FXB][0-9]+(V[0-9]+|B[0-9]+|N)?|I|P|B|P[0-9]+)$", RegexOptions.IgnoreCase)]
    private static partial Regex GeneratedField();
}
