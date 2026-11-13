// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Basic;

/// <summary>
///  Finds the reserved words, line references, variables and functions in one tokenized line, with the columns of
///  the text they came from.
/// </summary>
internal sealed class BasicLineScanner
{
    private readonly BasicDialect _dialect;
    private readonly int _line;
    private readonly string _text;
    private readonly byte[] _bytes;
    private readonly IReadOnlyList<int> _positions;
    private readonly int[] _columns;
    private readonly HashSet<string> _foreign;
    private readonly IReadOnlyList<(int Start, int End)> _skip;

    /// <summary>
    ///  Creates the scanner.
    /// </summary>
    /// <param name="dialect">The dialect.</param>
    /// <param name="line">The zero-based line of the text.</param>
    /// <param name="text">The line's text.</param>
    /// <param name="bytes">The line's statements, tokenized.</param>
    /// <param name="positions">The text unit each byte came from.</param>
    /// <param name="columns">The column each text unit starts at.</param>
    /// <param name="foreign">Other dialects' reserved words, which this one reads as names.</param>
    /// <param name="skip">The columns of label names, which are not BASIC's.</param>
    internal BasicLineScanner(
        BasicDialect dialect,
        int line,
        string text,
        byte[] bytes,
        IReadOnlyList<int> positions,
        int[] columns,
        HashSet<string> foreign,
        IReadOnlyList<(int Start, int End)>? skip = null)
    {
        _skip = skip ?? [];
        _dialect = dialect;
        _line = line;
        _text = text;
        _bytes = bytes;
        _positions = positions;
        _columns = columns;
        _foreign = foreign;
    }

    /// <summary>
    ///  Scans the line.
    /// </summary>
    /// <param name="sites">Receives what is found.</param>
    /// <param name="diagnostics">Receives warnings about names BASIC reads differently than they look.</param>
    internal void Run(List<BasicSite> sites, List<BasicDiagnostic> diagnostics)
    {
        BasicJump jump = BasicJump.None;
        bool afterNumber = false;
        bool afterFunction = false;
        bool afterExternal = false;
        bool inString = false;
        bool inData = false;
        string? previous = null;
        string? beforeGoto = null;
        string? via = null;
        BasicSite? name = null;
        BasicSite? split = null;
        for (int index = 0; index < _bytes.Length; index++)
        {
            byte value = _bytes[index];
            if (inString)
            {
                inString = value != '"';
                continue;
            }

            if (inData)
            {
                inString = value == '"';
                inData = value != ':';
                continue;
            }

            if (value == ' ') { continue; }
            if (_skip.Count != 0 && _skip.Any(range => Column(index) >= range.Start && Column(index) < range.End))
            {
                name = null;
                continue;
            }

            // A placeholder token, which Business BASIC's lists keep empty, is no word.
            if (_dialect.KeywordAt(_bytes, index, out int length) is { Length: > 0 } word)
            {
                // Level II stores ELSE as :ELSE and ' as :REM': the site is the last byte from the same text. A
                // function stored as a prefix and a token is both.
                int last = Last(index);
                int token = length == 2 ? (_bytes[index] << 8) | _bytes[index + 1] : _bytes[last];
                word = _dialect.Word(token) ?? word;
                BasicSite site = Site(BasicSiteKind.Keyword, index, End(last)) with { Token = token, Word = word };
                sites.Add(site);

                // Color BASIC's GOTO and GOSUB are GO, then TO or SUB.
                if (previous == "GO" && word is "TO" or "SUB") { word = "GO" + word; }

                // Business BASIC takes a word only with a separator before it, so a name never runs into one.
                if (!Business
                    && name is { Text.Length: >= 2 } before
                    && before.End == site.Start
                    && char.IsAsciiLetter(word[0]))
                {
                    split = site;
                }

                name = null;
                if (length == 1 && _dialect.IsRemark(value)) { break; }
                bool range = jump == BasicJump.Range && afterNumber && word == "-";
                jump = range ? BasicJump.Range : JumpAfter(word);
                via = range ? via : word;
                afterNumber = false;
                afterFunction = word == "FN";
                afterExternal = word is "EXFN." or "EXFN%.";
                inData = word == "DATA";
                if (word == "GOTO") { beforeGoto = previous; }
                previous = word;
                index = last;
                continue;
            }

            if (value == '"')
            {
                inString = true;
                jump = BasicJump.None;
                name = null;
                continue;
            }

            if (char.IsAsciiDigit((char)value) || value == '.')
            {
                if (jump != BasicJump.None && value != '.' && !afterNumber)
                {
                    index = Reference(index, sites, via, zero: previous == "RESUME" || beforeGoto is "ERROR" or "ONERR" or "ERR");
                    afterNumber = true;
                    if (jump == BasicJump.Single) { jump = BasicJump.None; }
                }
                else
                {
                    index = SkipNumber(index);
                    jump = BasicJump.None;
                }

                name = null;
                continue;
            }

            // EXFN. names a function in a module INVOKE loaded, not one of the program's variables or DEF FNs.
            if (afterExternal && char.IsAsciiLetter((char)value))
            {
                while (index + 1 < _bytes.Length && (char.IsAsciiLetterOrDigit((char)_bytes[index + 1]) || _bytes[index + 1] == '.'))
                {
                    index++;
                }

                afterExternal = false;
                jump = BasicJump.None;
                continue;
            }

            afterExternal = false;
            if (char.IsAsciiLetter((char)value))
            {
                index = Name(index, afterFunction, sites, diagnostics, split, out name);
                split = null;
                afterFunction = false;
                jump = BasicJump.None;
                continue;
            }

            // A comma continues a list of lines, and Integer BASIC's LIST 10,20; anything else ends it.
            bool commaRange = jump == BasicJump.Range && _dialect == BasicDialect.Integer;
            bool next = value == ',' && afterNumber && (jump == BasicJump.List || commaRange);
            if (!next) { jump = BasicJump.None; }
            afterNumber = false;
            name = null;
        }
    }

    /// <summary>
    ///  Finds where each statement starts: the line's first byte, and the byte after each colon outside strings,
    ///  DATA and REM. A statement's column is its first character after any spaces.
    /// </summary>
    /// <returns>The statements, in order.</returns>
    internal List<BasicStatement> Statements()
    {
        List<BasicStatement> statements = [new(0, _bytes.Length == 0 ? _text.Length : FirstColumn(0))];
        bool inString = false;
        for (int index = 0; index < _bytes.Length; index++)
        {
            byte value = _bytes[index];
            if (inString)
            {
                inString = value != '"';
                continue;
            }

            if (value == '"')
            {
                inString = true;
                continue;
            }

            // A function's token after its prefix is read with it: ABS is $FF $82, and $82 alone is REM.
            if (value == _dialect.FunctionPrefix && index + 1 < _bytes.Length)
            {
                index++;
                continue;
            }

            if (_dialect.IsRemark(value)) { break; }
            if (value != ':') { continue; }
            statements.Add(new(index + 1, index + 1 < _bytes.Length ? FirstColumn(index + 1) : _text.Length));
        }

        return statements;
    }

    // The column of the first byte at or after an index that is not a space.
    private int FirstColumn(int index)
    {
        int at = index;
        while (at + 1 < _bytes.Length && _bytes[at] == ' ') { at++; }
        return Column(at);
    }

    private static BasicJump JumpAfter(string word) => word switch
    {
        "GOTO" or "GOSUB" => BasicJump.List,
        "THEN" or "ELSE" or "RUN" or "RESUME" or "EDIT" => BasicJump.Single,
        "LIST" or "LLIST" or "DEL" or "DELETE" => BasicJump.Range,
        _ => BasicJump.None
    };

    // A line number after GOTO and the like; zero is not a line after ON ERROR GOTO or RESUME. Spaces between
    // digits are skipped, as BASIC skips them.
    private int Reference(int index, List<BasicSite> sites, string? via, bool zero)
    {
        int end = index;
        long number = 0;
        int last = index;
        while (end < _bytes.Length && (char.IsAsciiDigit((char)_bytes[end]) || _bytes[end] == ' '))
        {
            if (_bytes[end] != ' ')
            {
                number = Math.Min(number * 10 + (_bytes[end] - '0'), int.MaxValue);
                last = end;
            }

            end++;
        }

        if (!(zero && number == 0) && !Computed(last))
        {
            sites.Add(Site(BasicSiteKind.LineReference, index, End(last)) with { Number = (int)number, Via = via });
        }

        return last;
    }

    // Whether a number is only the start of an expression, as in Integer BASIC's GOTO 1000+K*10, which has no
    // ON GOTO: a line is a number that ends the statement or comes before a comma.
    private bool Computed(int last)
    {
        if (_dialect != BasicDialect.Integer) { return false; }
        int next = last + 1;
        while (next < _bytes.Length && _bytes[next] == ' ') { next++; }
        return next < _bytes.Length && _bytes[next] is not ((byte)':' or (byte)',');
    }

    // A number that is not a line: digits, a point and an exponent, with its sign token.
    private int SkipNumber(int index)
    {
        int at = index;
        while (at + 1 < _bytes.Length && (char.IsAsciiDigit((char)_bytes[at + 1]) || _bytes[at + 1] == '.')) { at++; }
        if (at + 2 < _bytes.Length && _bytes[at + 1] is (byte)'E' or (byte)'D')
        {
            bool signed = _bytes[at + 2] is (byte)'+' or (byte)'-' || _dialect.Keyword(_bytes[at + 2]) is "+" or "-";
            int sign = signed ? at + 3 : at + 2;
            if (sign < _bytes.Length && char.IsAsciiDigit((char)_bytes[sign]))
            {
                at = sign;
                while (at + 1 < _bytes.Length && char.IsAsciiDigit((char)_bytes[at + 1])) { at++; }
            }
        }

        return at;
    }

    // A variable or function name: letters and digits, a type suffix, and a parenthesis for an array.
    private int Name(
        int index,
        bool function,
        List<BasicSite> sites,
        List<BasicDiagnostic> diagnostics,
        BasicSite? split,
        out BasicSite? site)
    {
        int last = index;
        while (last + 1 < _bytes.Length && (char.IsAsciiLetterOrDigit((char)_bytes[last + 1]) || (Business && _bytes[last + 1] == '.')))
        {
            last++;
        }

        string letters = new([.. _bytes[index..(last + 1)].Select(value => char.ToUpperInvariant((char)value))]);
        string suffix = "";
        if (last + 1 < _bytes.Length && IsSuffix(_bytes[last + 1]))
        {
            last++;
            suffix = ((char)_bytes[last]).ToString();
        }

        int next = last + 1;
        while (next < _bytes.Length && _bytes[next] == ' ') { next++; }
        bool array = !function && next < _bytes.Length && _bytes[next] == '(';
        // The Microsoft BASICs keep a name's first two characters; Integer BASIC and Business BASIC keep all of it.
        string significant = letters.Length > 2 && _dialect != BasicDialect.Integer && !Business ? letters[..2] : letters;
        BasicSite found = Site(function ? BasicSiteKind.Function : BasicSiteKind.Variable, index, End(last)) with
        {
            Key = $"{significant}{suffix}{(array && _dialect != BasicDialect.Integer ? "(" : "")}",
            Name = letters + suffix,
            Subscripted = array
        };

        sites.Add(found);
        site = found;
        if (split is { } keyword && keyword.End == found.Start && sites.Count >= 3)
        {
            BasicSite before = sites[^3];
            string whole = _text[before.Start..found.End];
            diagnostics.Add(new(
                _line,
                BasicSeverity.Warning,
                $"BASIC reads {whole} as {before.Text} {keyword.Text} {found.Text}: it finds {keyword.Text.ToUpperInvariant()} inside the name.",
                before.Start,
                found.End));
        }
        else if (_foreign.Contains(letters) && suffix.Length == 0)
        {
            diagnostics.Add(new(
                _line,
                BasicSeverity.Warning,
                $"{_dialect.DisplayName} has no {letters}; it reads it as the variable {significant}.",
                found.Start,
                found.End));
        }

        return last;
    }

    // A type suffix: $ and %, on Level II ! and # for single and double precision, and in Business BASIC & for a
    // long integer.
    private bool IsSuffix(byte value) => value is (byte)'$' or (byte)'%'
        || (_dialect == BasicDialect.Level2 && value is (byte)'!' or (byte)'#')
        || (Business && value == '&');

    private bool Business => _dialect == BasicDialect.BusinessBasic;

    // The last byte that came from the same text as this one.
    private int Last(int index)
    {
        int last = index;
        while (last + 1 < _bytes.Length && _positions[last + 1] == _positions[index]) { last++; }
        return last;
    }

    private int Column(int index) => _positions[index] < _columns.Length ? _columns[_positions[index]] : _text.Length;

    // The column past a byte's text: where the next byte's starts, less spaces BASIC dropped.
    private int End(int index)
    {
        int next = Last(index) + 1;
        int end = next < _bytes.Length ? Column(next) : _text.Length;
        int start = Column(index);
        while (end > start + 1 && _text[end - 1] == ' ') { end--; }
        return end;
    }

    private BasicSite Site(BasicSiteKind kind, int index, int end)
    {
        int start = Column(index);
        return new(kind, _line, start, end, _text[start..end]);
    }
}
