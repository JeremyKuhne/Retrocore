// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.RegularExpressions;

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    // The identifiers a program cannot take for its own without changing what it compiles to: reserved words, and the
    // names Apple Pascal predeclares that the decompiled code may call or name.
    private static readonly HashSet<string> s_predeclared = new(StringComparer.OrdinalIgnoreCase)
    {
        "AND", "ARRAY", "BEGIN", "CASE", "CONST", "DIV", "DO", "DOWNTO", "ELSE", "END", "EXTERNAL", "FILE", "FOR",
        "FORWARD", "FUNCTION", "GOTO", "IF", "IMPLEMEN", "IN", "INTERFAC", "LABEL", "MOD", "NIL", "NOT", "OF", "OR",
        "PACKED", "PROCEDUR", "PROGRAM", "RECORD", "REPEAT", "SEGMENT", "SET", "THEN", "TO", "TYPE", "UNIT", "UNTIL",
        "USES", "VAR", "WHILE", "WITH",
        "BOOLEAN", "CHAR", "INTEGER", "REAL", "STRING", "TEXT", "INTERACT", "MAXINT", "TRUE", "FALSE",
        "INPUT", "OUTPUT", "KEYBOARD",
        "ABS", "ATAN", "BLOCKREA", "BLOCKWRI", "CHR", "CLOSE", "CONCAT", "COPY", "COS", "DELETE", "EOF", "EOLN",
        "EXIT", "EXP", "FILLCHAR", "GET", "GOTOXY", "HALT", "INSERT", "IORESULT", "LENGTH", "LN", "LOG", "MARK",
        "MEMAVAIL", "MOVELEFT", "MOVERIGH", "NEW", "ODD", "ORD", "PAGE", "POS", "PRED", "PUT", "PWROFTEN", "READ",
        "READLN", "RELEASE", "RESET", "REWRITE", "ROUND", "SCAN", "SEEK", "SIN", "SIZEOF", "SQR", "SQRT", "STR",
        "SUCC", "TIME", "TREESEAR", "TRUNC", "UNITBUSY", "UNITCLEA", "UNITREAD", "UNITSTAT", "UNITWAIT", "UNITWRIT",
        "WRITE", "WRITELN"
    };

    // Gives procedures and variables the names the hints and the listing give them, where they are safe.
    private void Rename()
    {
        foreach (Procedure procedure in _procedures.OrderBy(procedure => procedure.Level))
        {
            string key = $"{procedure.Segment.Name}.{procedure.Number}";
            string? given = Given(key) ?? _options.Listing?.ProcedureName(procedure.Segment.Number, procedure.Number);
            if (given is not null && Safe(given, key, procedure.Parent ?? procedure, procedure, out string? name))
            {
                // The program's and a segment procedure's names are their segments' names, which the code file keeps.
                if ((procedure == _program || procedure.IsSegmentProcedure) && !Keeps(name, procedure.Segment.Name))
                {
                    Warn($"The name {name} for {key} is not its segment's name, {procedure.Segment.Name}; it is {procedure.Name}.");
                }
                else
                {
                    procedure.Name = name;
                }
            }
        }

        foreach (Procedure procedure in _procedures.OrderBy(procedure => procedure.Level))
        {
            IReadOnlyList<PascalVariable> listed = _options.Listing?.Variables(procedure.Segment.Number, procedure.Number) ?? [];
            foreach (Variable variable in _parameters[procedure].Concat(_declared[procedure.Frame]))
            {
                string key = $"{procedure.Segment.Name}.{procedure.Number}@{variable.Offset}";
                string? given = Given(key) ?? listed.FirstOrDefault(entry => entry.Word == variable.Offset)?.Name;
                if (given is not null && Safe(given, key, procedure, variable, out string? name))
                {
                    variable.Name = name;
                }
            }
        }
    }

    // A name the hints give, by key, its word in hexadecimal too: SEGMENT.N@1038, or @$40E.
    private string? Given(string key)
    {
        foreach ((string hinted, string name) in _options.Names)
        {
            if (string.Equals(hinted, key, StringComparison.OrdinalIgnoreCase) || string.Equals(Decimal(hinted), key, StringComparison.OrdinalIgnoreCase))
            {
                return name;
            }
        }

        return null;
    }

    // A key with its word in hexadecimal written in decimal.
    private static string Decimal(string key)
    {
        int at = key.IndexOf("@$", StringComparison.Ordinal);
        return at >= 0 && int.TryParse(key.AsSpan(at + 2), System.Globalization.NumberStyles.HexNumber, provider: null, out int word)
            ? $"{key[..at]}@{word}"
            : key;
    }

    // Whether a name can be given: an identifier, and not the same in its first eight letters, the ones the Compiler
    // reads, as a reserved or predeclared word, a library unit's names, the names the decompiler makes for types and
    // constants, or another procedure's or variable's that the scope reaches or that reaches into it.
    private bool Safe(string given, string key, Procedure scope, object self, out string name)
    {
        name = new string([.. given.Where(char.IsAsciiLetterOrDigit)]);
        string? clash = name.Length == 0 || !char.IsAsciiLetter(name[0]) ? "no identifier" : Clash(Key(name), scope, self);
        if (clash is null) { return true; }

        Warn($"The name {given} for {key} would clash with {clash}; it is left as the decompiler names it.");
        return false;
    }

    private string? Clash(string name, Procedure scope, object self)
    {
        if (s_predeclared.Contains(name)) { return name; }
        if (DecompilerName().IsMatch(name)) { return "the decompiler's names for types and constants"; }

        foreach (PascalUnit unit in _unitOrder.Select(segment => _library?.Unit(segment)).OfType<PascalUnit>())
        {
            IEnumerable<string> names = unit.Procedures.Select(procedure => procedure.Name)
                .Concat(unit.Enumerations.Keys)
                .Concat(unit.Enumerations.Values.SelectMany(values => values))
                .Append(unit.Name);

            if (names.FirstOrDefault(other => Key(other) == name) is { } used) { return $"{unit.Name}'s {used}"; }
        }

        // The scope, the ones it is in, and the ones in it.
        HashSet<Procedure> reach = [scope];
        for (Procedure? outer = scope.Parent; outer is not null; outer = outer.Parent) { reach.Add(outer); }
        Stack<Procedure> inner = new([scope]);
        while (inner.TryPop(out Procedure? next))
        {
            foreach (Procedure child in next.Children) { if (reach.Add(child)) { inner.Push(child); } }
        }

        foreach (Procedure procedure in reach.Append(Program))
        {
            if (procedure != self && Key(procedure.Name) == name) { return procedure.Name; }

            foreach (Variable variable in _parameters[procedure].Concat(_declared[procedure.Frame]))
            {
                if (variable != self && Key(variable.Name) == name) { return variable.Name; }
            }
        }

        return null;
    }

    // The letters the Compiler reads of an identifier.
    private static string Key(string name)
    {
        string upper = name.ToUpperInvariant();
        return upper.Length > 8 ? upper[..8] : upper;
    }

    // Whether a name is a segment's, whose first eight letters the segment dictionary holds.
    private static bool Keeps(string name, string segment) => Key(name) == Key(segment.Trim());

    // A comment given for a procedure, as Pascal writes one.
    private string? Comment(Procedure procedure)
    {
        string? text = _options.Comments
            .FirstOrDefault(pair => string.Equals(pair.Key, $"{procedure.Segment.Name}.{procedure.Number}", StringComparison.OrdinalIgnoreCase))
            .Value;

        return text is null ? null : $"(* {text.Replace("*)", "* )", StringComparison.Ordinal)} *)";
    }

    // The program's assembled procedures as source for the Assembler, by the names the source declares them EXTERNAL
    // by, with the hints' names and comments for their places.
    private string? Assembly()
    {
        List<Procedure> assembled = [.. _procedures.Where(procedure => procedure.Code.IsNative)];
        if (assembled.Count == 0) { return null; }

        List<string> sources = [];
        foreach (IGrouping<Media.PascalSegment, Procedure> segment in assembled.GroupBy(procedure => procedure.Segment))
        {
            List<PascalAssembledProcedure> written = [];
            foreach (Procedure procedure in segment)
            {
                if (!procedure.Signed)
                {
                    Warn($"{procedure} is never called, so its parameters are not known; it is written with none.");
                }


                string prefix = $"{procedure.Segment.Name}.{procedure.Number}+";
                written.Add(new PascalAssembledProcedure(
                    procedure.Name,
                    procedure.Number,
                    procedure.IsFunction,
                    procedure.Signed ? procedure.Frame.ParameterWords - (procedure.IsFunction ? 2 : 0) : 0)
                {
                    Comment = Comment(_options.Comments, prefix[..^1]),
                    Names = Places(_options.Names, prefix),
                    Comments = Places(_options.Comments, prefix)
                });
            }

            PascalAssemblySource source = PascalAssemblyWriter.Write(segment.Key, written, Global);
            foreach (string note in source.Notes) { Warn(note); }
            sources.Add(source.Text);
        }

        return string.Concat(sources);
    }

    private static string? Comment(IReadOnlyDictionary<string, string> comments, string key) =>
        comments.FirstOrDefault(pair => string.Equals(pair.Key, key, StringComparison.OrdinalIgnoreCase)).Value;

    // The program's global a base-relative word's value names, and the bytes into it: BASE points 10 bytes below
    // the program's word 1, so word W is at 10 + 2W.
    private (string Name, int Bytes)? Global(int value)
    {
        if (value < 12) { return null; }

        int word = (value - 10) / 2;
        Variable? global = _declared[Program.Frame].FirstOrDefault(variable => variable.Offset <= word && word < variable.Offset + Math.Max(1, variable.Words));
        return global is null ? null : (global.Name, ((word - global.Offset) * 2) + ((value - 10) % 2));
    }

    // The hints for places in a procedure, by offset from its entry: SEGMENT.N+$3E, or +62.
    private static Dictionary<int, string> Places(IReadOnlyDictionary<string, string> values, string prefix)
    {
        Dictionary<int, string> places = [];
        foreach ((string key, string value) in values)
        {
            if (!key.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)) { continue; }

            string offset = key[prefix.Length..];
            bool parsed = offset.StartsWith('$')
                ? int.TryParse(offset.AsSpan(1), System.Globalization.NumberStyles.HexNumber, provider: null, out int at)
                : int.TryParse(offset, System.Globalization.NumberStyles.Integer, provider: null, out at);

            if (parsed) { places[at] = value; }
        }

        return places;
    }

    // The decompiler's own names for types and declared constants: T1, NEG1.
    [GeneratedRegex("^(T|NEG)[0-9]+$")]
    private static partial Regex DecompilerName();
}
