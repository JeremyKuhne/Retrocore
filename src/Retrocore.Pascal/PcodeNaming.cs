// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Globalization;
using Retrocore.Media;

namespace Retrocore.Pascal;

/// <summary>
///  The names a code file's source gives its parts: segments' and procedures' scopes, labels, calls and variables,
///  from <see cref="PcodeSourceOptions"/>.
/// </summary>
internal sealed class PcodeNaming
{
    private static readonly HashSet<string> s_reserved = new(StringComparer.OrdinalIgnoreCase)
    {
        "CSP",
        "PASCALSY",
        "PASCALIO"
    };

    // The system segment's procedures a program calls, as Pcode.asm's PASCALSY scope names them.
    private static readonly Dictionary<int, string> s_system = new()
    {
        [3] = "FINIT", [4] = "FRESET", [5] = "FOPEN", [6] = "FCLOSE", [7] = "FGET", [8] = "FPUT", [10] = "FEOF",
        [11] = "FEOLN", [12] = "FREADINT", [13] = "FWRITEINT", [16] = "FREADCHAR", [17] = "FWRITECHAR",
        [18] = "FREADSTRING", [19] = "FWRITESTRING", [20] = "FWRITEBYTES", [21] = "FREADLN", [22] = "FWRITELN",
        [23] = "SCONCAT", [24] = "SINSERT", [25] = "SCOPY", [26] = "SDELETE", [27] = "SPOS", [28] = "FBLOCKIO",
        [29] = "FGOTOXY"
    };

    private static readonly Dictionary<int, string> s_pascalIo = new()
    {
        [2] = "FSEEK",
        [3] = "FREADREAL",
        [4] = "FWRITEREAL"
    };

    // The system's outer block's variables a program reaches, its standard files.
    private static readonly Dictionary<int, string> s_systemVariables = new()
    {
        [2] = "INPUT",
        [3] = "OUTPUT",
        [4] = "KEYBOARD"
    };

    private readonly PcodeSourceOptions _options;
    private readonly PascalCodeFile _file;
    private readonly Dictionary<PascalSegment, string> _segments = [];
    private readonly Dictionary<(PascalSegment Segment, int Procedure), string> _procedures = [];
    private readonly SortedDictionary<int, PascalUnit> _units = [];

    /// <summary>
    ///  Names a code file's segments and procedures.
    /// </summary>
    /// <param name="options">Where names come from.</param>
    /// <param name="file">The code file.</param>
    public PcodeNaming(PcodeSourceOptions options, PascalCodeFile file)
    {
        _options = options;
        _file = file;
        HashSet<string> scopes = new(s_reserved, StringComparer.OrdinalIgnoreCase);
        foreach (PascalSegment segment in file.Segments)
        {
            string name = Identifier(Name(segment.Name) ?? _options.Listing?.SegmentName(segment.Number) ?? segment.Name, $"Seg{segment.Slot}");
            if (!scopes.Add(name)) { name = Unique(scopes, $"{name}{segment.Slot}"); }
            _segments[segment] = name;

            HashSet<string> procedures = new(StringComparer.OrdinalIgnoreCase) { "Entry", "Exit", "Attributes" };
            foreach (PascalProcedure procedure in segment.Procedures)
            {
                int number = procedure.Index;
                string? given = Name($"{segment.Name}.{number}") ?? _options.Listing?.ProcedureName(segment.Number, number);
                string scope = Identifier(given ?? $"P{number}", $"P{number}");
                if (!procedures.Add(scope)) { scope = Unique(procedures, $"{scope}{number}"); }
                _procedures[(segment, number)] = scope;
            }
        }
    }

    /// <summary>
    ///  Gets the units the source's calls named, by segment number, whose scopes it defines.
    /// </summary>
    public IReadOnlyDictionary<int, PascalUnit> Units => _units;

    /// <summary>
    ///  Gets a segment's scope.
    /// </summary>
    /// <param name="segment">The segment.</param>
    /// <returns>Its name.</returns>
    public string Segment(PascalSegment segment) => _segments[segment];

    /// <summary>
    ///  Gets a procedure's scope.
    /// </summary>
    /// <param name="segment">Its segment.</param>
    /// <param name="number">Its number.</param>
    /// <returns>Its name: given, from the listing, or <c>P</c> and its number.</returns>
    public string Procedure(PascalSegment segment, int number) =>
        _procedures.TryGetValue((segment, number), out string? name) ? name : $"P{number}";

    /// <summary>
    ///  Gets the comment given for a segment or procedure, by key.
    /// </summary>
    /// <param name="key">The key, such as <c>FORMATTE.2</c>.</param>
    /// <returns>The comment, or null.</returns>
    public string? Comment(string key) => Lookup(_options.Comments, key);

    /// <summary>
    ///  Gets the names and comments given for places in a procedure, by offset from its entry.
    /// </summary>
    /// <param name="segment">Its segment.</param>
    /// <param name="number">Its number.</param>
    /// <returns>Names and comments by offset.</returns>
    public (Dictionary<int, string> Names, Dictionary<int, string> Comments) Places(PascalSegment segment, int number)
    {
        string prefix = $"{segment.Name}.{number}+";
        return (Offsets(_options.Names, prefix, identifiers: true), Offsets(_options.Comments, prefix, identifiers: false));
    }

    /// <summary>
    ///  Gets a CXP's operands as names: the system's procedures, PASCALIO's, and a unit's from the library.
    /// </summary>
    /// <param name="segment">The segment number it calls.</param>
    /// <param name="number">The procedure number.</param>
    /// <returns>The operands, or null to write them as numbers.</returns>
    public string? External(int segment, int number)
    {
        if (segment == 0)
        {
            return s_system.TryGetValue(number, out string? system) ? $"0, PASCALSY::{system}" : null;
        }

        if (segment == 31)
        {
            return s_pascalIo.TryGetValue(number, out string? io) ? $"PASCALIO::Segment, PASCALIO::{io}" : null;
        }

        if (_options.Library?.Unit(segment) is not { } unit || _file.Segments.Any(own => own.Number == segment && own.Code.Length > 0))
        {
            return null;
        }

        string scope = UnitScope(unit);
        string? procedure = number == 1 ? "Initialize" : unit.Procedure(number)?.Name;
        if (procedure is null) { return null; }

        _units[segment] = unit;
        return $"{scope}::Segment, {scope}::{procedure}";
    }

    /// <summary>
    ///  Gets the comment for a call of a procedure in the code file: its scope.
    /// </summary>
    /// <param name="segment">The segment number, or the calling segment's for CLP and the others.</param>
    /// <param name="number">The procedure number.</param>
    /// <returns>The procedure's qualified scope, or null.</returns>
    public string? Callee(int segment, int number)
    {
        PascalSegment? target = _file.Segments.FirstOrDefault(own => own.Number == segment && own.Code.Length > 0 && own.Procedure(number) is not null);
        return target is null ? null : $"{_segments[target]}::{Procedure(target, number)}";
    }

    /// <summary>
    ///  Gets a unit's scope.
    /// </summary>
    /// <param name="unit">The unit.</param>
    /// <returns>Its name.</returns>
    public static string UnitScope(PascalUnit unit) => Identifier(unit.Name, $"Unit{unit.Segment}");

    /// <summary>
    ///  Gets the source lines the listing places at a procedure's offsets from its entry.
    /// </summary>
    /// <param name="segment">Its segment.</param>
    /// <param name="number">Its number.</param>
    /// <returns>Each offset's lines, as comments.</returns>
    public Dictionary<int, List<string>> SourceLines(PascalSegment segment, int number)
    {
        Dictionary<int, List<string>> lines = [];
        if (_options.Listing is not { } listing) { return lines; }

        foreach (PascalListingLine line in listing.Lines.Where(line => !line.IsDeclaration && line.Segment == segment.Number && line.Procedure == number))
        {
            if (!lines.TryGetValue(line.Offset, out List<string>? at)) { lines[line.Offset] = at = []; }
            at.Add($"; {line.Line,4}: {line.Text.Trim()}");
        }

        return lines;
    }

    /// <summary>
    ///  Gets the name of the variable at a word of a procedure: given as <c>SEGMENT.N@WORD</c>, or from the listing.
    /// </summary>
    /// <param name="segment">The segment's number.</param>
    /// <param name="number">The procedure's number.</param>
    /// <param name="word">The word, as LDL numbers it.</param>
    /// <returns>The name, with the word's place in it after a plus where it is not the first; or null.</returns>
    public string? Variable(int segment, int number, int word)
    {
        if (_file.Segments.FirstOrDefault(own => own.Number == segment && own.Code.Length > 0) is { } named
            && Words(_options.Names, $"{named.Name}.{number}@").TryGetValue(word, out string? given))
        {
            return given;
        }

        if (_options.Listing is not { } listing) { return null; }

        foreach (PascalVariable variable in listing.Variables(segment, number))
        {
            if (word >= variable.Word && word < variable.Word + Math.Max(1, variable.Words))
            {
                return word == variable.Word ? variable.Name : $"{variable.Name}+{word - variable.Word}";
            }
        }

        return null;
    }

    /// <summary>
    ///  Gets the name of a global variable, the program's outer block's, from the listing.
    /// </summary>
    /// <param name="word">The word, as LDO numbers it.</param>
    /// <returns>The name, or null.</returns>
    public string? Global(int word)
    {
        PascalSegment? program = _file.Segments.FirstOrDefault(IsProgram);
        return program is null ? null : Variable(program.Number, 1, word);
    }

    /// <summary>
    ///  Gets the name of an intermediate variable, one LOD, STR and LDA reach in an enclosing procedure: the
    ///  program's globals, and the system's standard files.
    /// </summary>
    /// <param name="segment">The segment of the procedure that reaches it.</param>
    /// <param name="number">The procedure's number.</param>
    /// <param name="levels">How many levels out the variable is.</param>
    /// <param name="word">The word, in the enclosing procedure's frame.</param>
    /// <returns>The name, or null where the enclosing procedure is not known without the source's nesting.</returns>
    public string? Intermediate(PascalSegment segment, int number, int levels, int word) =>
        (segment.Procedure(number)?.LexicalLevel - levels) switch
        {
            -1 => s_systemVariables.GetValueOrDefault(word),
            0 => Global(word),
            _ => null
        };

    // The program's segment: its procedure 1 is p-code at lexical level 0 (or -1, the system's).
    private static bool IsProgram(PascalSegment segment) =>
        segment.Procedure(1) is PascalProcedure main && main.LexicalLevel <= 0 && !main.IsNative;

    private string? Name(string key) => Lookup(_options.Names, key);

    private static string? Lookup(IReadOnlyDictionary<string, string> values, string key) =>
        values.FirstOrDefault(pair => string.Equals(pair.Key, key, StringComparison.OrdinalIgnoreCase)).Value;

    // The words given names, keyed as a prefix and a word: FORMATTE.1@1038, or @$40E.
    private static Dictionary<int, string> Words(IReadOnlyDictionary<string, string> values, string prefix) =>
        Offsets(values, prefix, identifiers: false);

    private static Dictionary<int, string> Offsets(IReadOnlyDictionary<string, string> values, string prefix, bool identifiers)
    {
        Dictionary<int, string> offsets = [];
        foreach ((string key, string value) in values)
        {
            if (!key.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)) { continue; }

            string text = key[prefix.Length..];
            bool parsed = text.StartsWith('$')
                ? int.TryParse(text[1..], NumberStyles.HexNumber, CultureInfo.InvariantCulture, out int offset)
                : int.TryParse(text, NumberStyles.Integer, CultureInfo.InvariantCulture, out offset);

            if (parsed) { offsets[offset] = identifiers ? Identifier(value, $"L{offset:X4}") : value; }
        }

        return offsets;
    }

    // A name the assembler takes as a symbol: letters, digits and underscores, not starting with a digit.
    private static string Identifier(string name, string fallback)
    {
        string identifier = new([.. name.Trim().Select(character => char.IsAsciiLetterOrDigit(character) ? character : '_')]);
        return identifier.Length == 0 || char.IsAsciiDigit(identifier[0]) || identifier.All(character => character == '_') ? fallback : identifier;
    }

    private static string Unique(HashSet<string> names, string name)
    {
        string unique = name;
        for (int suffix = 2; !names.Add(unique); suffix++) { unique = $"{name}_{suffix}"; }
        return unique;
    }
}
