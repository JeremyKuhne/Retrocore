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

    private BbcAssemblyPart _assembly;

    /// <summary>
    ///  Gets or sets whether the line starts, and then ends, inside BBC BASIC's assembler: between a <c>[</c> where a
    ///  statement starts and a <c>]</c> where one of the assembler's statements starts, which can be lines later.
    /// </summary>
    internal bool Assembling { get; set; }

    /// <summary>
    ///  Scans the line.
    /// </summary>
    /// <param name="sites">Receives what is found.</param>
    /// <param name="diagnostics">Receives warnings about names BASIC reads differently than they look.</param>
    internal void Run(List<BasicSite> sites, List<BasicDiagnostic> diagnostics)
    {
        _assembly = BbcAssemblyPart.Statement;
        BasicJump jump = BasicJump.None;
        bool afterNumber = false;
        bool afterFunction = false;
        string routine = "";
        bool afterExternal = false;
        bool inString = false;
        bool inData = false;

        // BBC BASIC's AUTO and RENUMBER take a new first line and a step, kept as line numbers but naming no line.
        bool newLines = false;
        string? previous = null;
        string? beforeGoto = null;
        string? via = null;
        BasicSite? name = null;
        BasicSite? split = null;
        bool statementStart = true;
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

            // BBC BASIC's assembler reads its mnemonics, registers and comments itself; its operands' names are
            // BASIC's, and a . label is a variable set to P%. After its ] a statement starts.
            if (Bbc && Assembling)
            {
                if (Assemble(ref index, value, sites, diagnostics))
                {
                    statementStart = !Assembling;
                    name = null;
                    continue;
                }
            }
            else if (Bbc && statementStart && value == '[')
            {
                Assembling = true;
                _assembly = BbcAssemblyPart.Statement;
                statementStart = false;
                name = null;
                continue;
            }

            // A BBC * command is the MOS's to read, to the end of the line: nothing in it is BASIC's.
            if (Bbc && statementStart && value == '*') { break; }
            bool wasStart = statementStart;
            statementStart = value == ':';
            if (value == ':') { newLines = false; }
            if (_skip.Count != 0 && _skip.Any(range => Column(index) >= range.Start && Column(index) < range.End))
            {
                name = null;
                continue;
            }

            // BBC BASIC keeps a line number after GOTO and the like as a token and three bytes.
            if (Bbc && value == BbcBasicDialect.LineNumberToken && index + 3 < _bytes.Length)
            {
                int number = BbcBasicDialect.UnpackLineNumber(_bytes[index + 1], _bytes[index + 2], _bytes[index + 3]);
                if (!newLines)
                {
                    sites.Add(Site(BasicSiteKind.LineReference, index, End(index + 3)) with
                    {
                        Number = number,
                        Via = via
                    });
                }

                index += 3;
                name = null;
                continue;
            }

            // MBASIC crunches numbers into constants, a type byte and its value, read whole. CRUNCH makes a line
            // number constant only after the words that take lines (LINRES: GOTO, RESTORE, ERL and the others), as
            // RENUM finds them, so each is a reference.
            if (Mbasic && MbasicDialect.ConstantLength(value) is >= 0 and var payload)
            {
                int end = Math.Min(index + payload, _bytes.Length - 1);
                if (MbasicDialect.IsLineConstant(value) && end == index + 2)
                {
                    int number = _bytes[index + 1] | (_bytes[index + 2] << 8);
                    bool zero = previous == "RESUME" || beforeGoto is "ERROR" or "ONERR" or "ERR";
                    if (!(zero && number == 0))
                    {
                        BasicSite reference = Site(BasicSiteKind.LineReference, index, End(index));
                        sites.Add(reference with { Number = number, Via = via });
                    }

                    afterNumber = true;
                    if (jump == BasicJump.Single) { jump = BasicJump.None; }
                }
                else
                {
                    jump = BasicJump.None;
                }

                name = null;
                index = end;
                continue;
            }

            // A placeholder token, which Business BASIC's lists keep empty, is no word.
            if (_dialect.KeywordAt(_bytes, index, out int length) is { Length: > 0 } word)
            {
                // Level II stores ELSE as :ELSE and ' as :REM': the site is the last byte from the same text. A
                // function stored as a prefix and a token is both.
                int first = index;
                int last = Last(index);
                int token = length == 2 ? (_bytes[index] << 8) | _bytes[index + 1] : _bytes[last];

                // MBASIC stores WHILE with a + after it from the same text: the site is WHILE.
                if (length == 1 && last > index && _dialect.Word(_bytes[index]) == "WHILE") { token = _bytes[index]; }
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
                afterFunction = word == "FN" || (Bbc && word == "PROC");
                routine = Bbc && afterFunction ? word : "";
                afterExternal = word is "EXFN." or "EXFN%.";
                inData = word == "DATA";
                if (Bbc && word is "AUTO" or "RENUMBER") { newLines = true; }

                // BBC BASIC's tokeniser decides by each word's flags: ERROR and LET start a statement as THEN and ELSE
                // do, and REPEAT leaves one starting, so ON ERROR *KEY 1 FOO and REPEAT *KEY 1 FOO are commands.
                statementStart = Bbc
                    ? BbcBasicDialect.StatementStartsAfter(word, wasStart)
                    : word is "THEN" or "ELSE";

                if (word == "GOTO") { beforeGoto = previous; }
                previous = word;
                index = last;

                // TOP has no token of its own: BBC BASIC's tokeniser makes it TO, then P, which is no variable. Only
                // where an operand starts, though: after one, as in FOR I%=1 TOP%, the TO is FOR's and P% a variable.
                if (Bbc && word == "TO" && index + 1 < _bytes.Length && _bytes[index + 1] == 'P' && OperandStarts(first))
                {
                    index++;
                }

                continue;
            }

            if (value == '"')
            {
                inString = true;
                jump = BasicJump.None;
                name = null;
                continue;
            }

            // A BBC PROC or FN name may start with a digit, as in PROC1, or an @, as in PROC@foo: SCAN_VARIABLE_NAME
            // takes digits and @ anywhere in a routine's name. It is a name, not a number or the resident @%.
            if (Bbc && afterFunction && (char.IsAsciiDigit((char)value) || value == '@'))
            {
                index = Name(index, afterFunction, routine, sites, diagnostics, split, statement: false, out name);
                split = null;
                afterFunction = false;
                jump = BasicJump.None;
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

            // A BBC hexadecimal number, such as &BEEF, is a constant, not a name.
            if (Bbc && value == '&')
            {
                while (index + 1 < _bytes.Length && char.IsAsciiHexDigitUpper((char)_bytes[index + 1])) { index++; }
                jump = BasicJump.None;
                name = null;
                continue;
            }

            // A BBC name starts with a letter, _ or £, or is the resident @%.
            bool bbcLetter = BbcBasicDialect.IsNameCharacter(value) && !char.IsAsciiDigit((char)value);
            bool atPercent = value == '@' && index + 1 < _bytes.Length && _bytes[index + 1] == '%';
            if (char.IsAsciiLetter((char)value) || (Bbc && (bbcLetter || atPercent)))
            {
                index = Name(index, afterFunction, routine, sites, diagnostics, split, wasStart, out name);
                split = null;
                afterFunction = false;
                jump = BasicJump.None;
                continue;
            }

            // A comma continues a list of lines, and Integer BASIC's LIST 10,20; anything else ends it.
            bool commaRange = jump == BasicJump.Range && _dialect is IntegerBasicDialect;
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
        bool statementStart = true;
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
                statementStart = false;
                continue;
            }

            // A BBC * command is the MOS's to read, to the end of the line, colons and all, as OSCLI takes it; a word
            // decides by its flags whether a statement starts after it, as THEN does.
            if (Bbc && value != ' ')
            {
                if (statementStart && value == '*') { break; }
                if (value == BbcBasicDialect.LineNumberToken && index + 3 < _bytes.Length)
                {
                    index += 3;
                    statementStart = false;
                    continue;
                }

                bool wasStart = statementStart;
                string? word = value >= 0x80 ? BbcBasicDialect.Instance.Word(value) : null;
                statementStart = value == ':' || (word is not null && BbcBasicDialect.StatementStartsAfter(word, wasStart));
            }

            // A function's token after its prefix is read with it: ABS is $FF $82, and $82 alone is REM.
            if (value == _dialect.FunctionPrefix && index + 1 < _bytes.Length)
            {
                index++;
                continue;
            }

            // MBASIC's constants hold binary values, which may look like a colon or REM.
            if (Mbasic && MbasicDialect.ConstantLength(value) is > 0 and var payload)
            {
                index += payload;
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

    // Whether an operand starts at a place, rather than following one: the byte before it, past spaces, is no part
    // of a name, number, string or bracketed expression. A token before it, such as PRINT, leaves an operand to come,
    // but not one that is a whole value itself, such as FALSE or PAGE.
    private bool OperandStarts(int index)
    {
        int before = index - 1;
        while (before >= 0 && _bytes[before] == ' ') { before--; }
        if (before < 0) { return true; }
        byte value = _bytes[before];
        if (value >= 0x80) { return _dialect.Word(value) is not { } word || !s_bbcValues.Contains(word); }
        return !char.IsAsciiLetterOrDigit((char)value) && !"%$)\"._`".Contains((char)value);
    }

    // BBC BASIC's words that are a value with nothing after them.
    private static readonly HashSet<string> s_bbcValues =
        ["FALSE", "TRUE", "PI", "PAGE", "TIME", "LOMEM", "HIMEM", "TOP", "COUNT", "ERL", "ERR", "POS", "VPOS", "RND", "GET", "GET$"];

    // Whether a number is only the start of an expression, as in Integer BASIC's GOTO 1000+K*10, which has no
    // ON GOTO: a line is a number that ends the statement or comes before a comma.
    private bool Computed(int last)
    {
        if (_dialect is not IntegerBasicDialect) { return false; }
        int next = last + 1;
        while (next < _bytes.Length && _bytes[next] == ' ') { next++; }
        return next < _bytes.Length && _bytes[next] is not ((byte)':' or (byte)',');
    }

    // A number that is not a line: digits, a point and an exponent, with its sign token.
    private int SkipNumber(int index)
    {
        int at = index;
        while (at + 1 < _bytes.Length && (char.IsAsciiDigit((char)_bytes[at + 1]) || _bytes[at + 1] == '.')) { at++; }

        // BBC BASIC's READ_EXPONENT takes an E (never D, which starts a name such as D5) and a sign whatever follows,
        // then up to two digits: 2E and 3E+ are numbers, not the variable E, and a third digit is left over.
        if (Bbc)
        {
            if (at + 1 < _bytes.Length && _bytes[at + 1] == 'E')
            {
                at++;
                if (at + 1 < _bytes.Length && _bytes[at + 1] is (byte)'+' or (byte)'-') { at++; }
                for (int digit = 0; digit < 2 && at + 1 < _bytes.Length && char.IsAsciiDigit((char)_bytes[at + 1]); digit++)
                {
                    at++;
                }
            }

            return at;
        }

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

    // A variable or function name: letters and digits, a type suffix, and a parenthesis for an array. BBC BASIC's
    // PROCfoo and FNfoo are different routines, so their keys keep the word.
    private int Name(
        int index,
        bool function,
        string routine,
        List<BasicSite> sites,
        List<BasicDiagnostic> diagnostics,
        BasicSite? split,
        bool statement,
        out BasicSite? site)
    {
        int last = index;
        while (last + 1 < _bytes.Length
            && (char.IsAsciiLetterOrDigit((char)_bytes[last + 1])
                || ((Business || Mbasic) && _bytes[last + 1] == '.')
                || (Bbc && BbcBasicDialect.IsNameCharacter(_bytes[last + 1]))
                || (Bbc && function && _bytes[last + 1] == '@')))
        {
            last++;
        }

        // BBC BASIC's names are case-sensitive.
        string letters = new([.. _bytes[index..(last + 1)].Select(value => Bbc ? (char)value : char.ToUpperInvariant((char)value))]);
        string suffix = "";
        if (last + 1 < _bytes.Length && IsSuffix(_bytes[last + 1]))
        {
            last++;
            suffix = ((char)_bytes[last]).ToString();
        }

        // An array's bracket follows its name; BBC BASIC takes only one straight after it, as FIND_VARIABLE reads the
        // next character, so A (1) is the variable A and then (1), where the other BASICs pass the spaces.
        int next = last + 1;
        while (!Bbc && next < _bytes.Length && _bytes[next] == ' ') { next++; }
        bool array = !function && next < _bytes.Length && _bytes[next] == '(';
        // The Microsoft BASICs keep a name's first two characters, MBASIC its first 40; Integer BASIC, Business BASIC
        // and BBC BASIC keep all of it.
        int kept = Mbasic ? MbasicSignificant : _dialect is IntegerBasicDialect || Business || Bbc ? letters.Length : 2;
        string significant = letters[..Math.Min(letters.Length, kept)];
        BasicSite found = Site(function ? BasicSiteKind.Function : BasicSiteKind.Variable, index, End(last)) with
        {
            Key = $"{(function ? routine : "")}{significant}{suffix}{(array && _dialect is not IntegerBasicDialect ? "(" : "")}",
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
        else if (Business && GluedWord(index, sites) is { } glued)
        {
            diagnostics.Add(new(
                _line,
                BasicSeverity.Warning,
                $"BASIC reads {found.Text} as the variable {letters}{suffix}: {glued.TrimEnd('(')} needs a separator, such as a space, before it.",
                found.Start,
                found.End));
        }
        else if (_foreign.Contains(letters) && suffix.Length == 0 && !Bbc)
        {
            diagnostics.Add(new(
                _line,
                BasicSeverity.Warning,
                $"{_dialect.DisplayName} has no {letters}; it reads it as the variable {significant}.",
                found.Start,
                found.End));
        }
        else if (_foreign.Contains(letters) && suffix.Length == 0 && statement && !Assigned(last + 1))
        {
            // BBC BASIC keeps names whole, so HOME is as good a variable as any; only as a statement of its own is it
            // likely meant as another BASIC's word, and there BASIC takes it for an assignment with no =.
            diagnostics.Add(new(
                _line,
                BasicSeverity.Warning,
                $"{_dialect.DisplayName} has no {letters} statement: it reads {letters} as a variable to assign, and stops with Mistake.",
                found.Start,
                found.End));
        }

        return last;
    }

    // Whether what follows a BBC name where a statement starts makes it an assignment's target: =, an array's
    // subscripts, or an indirection, as in A=1, A(1)=1 and A?1=1. FIND_VARIABLE reads the (, ? or ! straight after the
    // name, so only = may come after spaces: HOME ?0=1 stops with Mistake.
    private bool Assigned(int index)
    {
        if (index < _bytes.Length && _bytes[index] is (byte)'(' or (byte)'?' or (byte)'!') { return true; }
        while (index < _bytes.Length && _bytes[index] == ' ') { index++; }
        return index < _bytes.Length && _bytes[index] == '=';
    }

    // One character in BBC BASIC's assembler, as ASSEMBLER_NEXT_STATEMENT and ASSEMBLE_INSTRUCTION read it; false when
    // it is an operand's, which the caller reads as BASIC's.
    private bool Assemble(ref int index, byte value, List<BasicSite> sites, List<BasicDiagnostic> diagnostics)
    {
        switch (_assembly)
        {
            case BbcAssemblyPart.Skipped:
                // Up to the colon that ends the statement, quotes and all.
                if (value == ':') { _assembly = BbcAssemblyPart.Statement; }
                return true;
            case BbcAssemblyPart.Statement:
                if (value == ':') { return true; }
                if (value == ']')
                {
                    Assembling = false;
                    return true;
                }

                if (value == '\\')
                {
                    _assembly = BbcAssemblyPart.Skipped;
                    return true;
                }

                // A label: the variable after the . is set to P%; the statement goes on.
                if (value == '.')
                {
                    if (index + 1 < _bytes.Length && BbcBasicDialect.IsNameCharacter(_bytes[index + 1]) && !char.IsAsciiDigit((char)_bytes[index + 1]))
                    {
                        index = Name(index + 1, function: false, "", sites, diagnostics, split: null, statement: false, out _);
                    }

                    return true;
                }

                index = Mnemonic(index, out bool shift);
                _assembly = shift ? BbcAssemblyPart.ShiftOperand : BbcAssemblyPart.Operand;
                return true;
            default:
                if (value == ':')
                {
                    _assembly = BbcAssemblyPart.Statement;
                    return true;
                }

                // A comment after the operand: the assembler skips whatever follows it, so ; works as \ does.
                bool register = _assembly == BbcAssemblyPart.Register && value is (byte)'X' or (byte)'Y';
                bool accumulator = _assembly == BbcAssemblyPart.ShiftOperand && value == 'A';
                if (value is (byte)'\\' or (byte)';' || register || accumulator)
                {
                    _assembly = BbcAssemblyPart.Skipped;
                    return true;
                }

                _assembly = value == ',' ? BbcAssemblyPart.Register : BbcAssemblyPart.Operand;
                return value == ',';
        }
    }

    // A mnemonic: up to three characters, packed by their low five bits, so lda is LDA; EQU takes the letter after it,
    // as EQUB does. AND, EOR and OR are tokens, OR with the A after it. Returns the mnemonic's last byte.
    private int Mnemonic(int index, out bool shift)
    {
        shift = false;
        if (_bytes[index] >= 0x80)
        {
            bool or = _dialect.Word(_bytes[index]) == "OR";
            return or && index + 1 < _bytes.Length && _bytes[index + 1] == 'A' ? index + 1 : index;
        }

        int last = index;
        while (last - index < 2 && last + 1 < _bytes.Length && _bytes[last + 1] is not ((byte)' ' or (byte)':') and < 0x80)
        {
            last++;
        }

        string letters = new([.. _bytes[index..(last + 1)].Select(value => (char)('@' + (value & 0x1F)))]);
        shift = letters is "ASL" or "LSR" or "ROL" or "ROR";
        if (letters == "EQU" && last + 1 < _bytes.Length && char.IsAsciiLetter((char)_bytes[last + 1])) { last++; }
        return last;
    }

    // A type suffix: $ and %, on Level II ! and # for single and double precision, and in Business BASIC & for a
    // long integer.
    private bool IsSuffix(byte value) => value is (byte)'$' or (byte)'%'
        || ((_dialect == BasicDialect.Level2 || _dialect == BasicDialect.Mbasic) && value is (byte)'!' or (byte)'#')
        || (Business && value == '&');

    private bool Business => _dialect == BasicDialect.BusinessBasic;

    // The reserved word CRUNCH would take where a Business BASIC name starts, but for the number that runs into it, as
    // in IF A=1THEN 20: it takes a word only with a separator before it, and a digit is none, so the word is part of
    // the name. Null when the name follows something else or no word would be taken there. The line's number counts
    // as a separator, as in 10PRINT.
    private string? GluedWord(int index, List<BasicSite> sites)
    {
        int column = Column(index);
        if (column == 0 || !(char.IsAsciiDigit(_text[column - 1]) || _text[column - 1] == '.')) { return null; }
        bool afterLineNumber = sites.Any(site => site.Kind == BasicSiteKind.LineNumber && site.Line == _line && site.End == column);
        if (afterLineNumber) { return null; }

        // As CRUNCH searches: the first word of either list, in order, that the text spells, with a separator after
        // it unless it ends in one, as TAB( does, or is EXFN., EXFN%. or FN, which a name follows directly.
        return _dialect.AllKeywords.FirstOrDefault(word => word.Length > 0
            && char.IsAsciiLetter(word[0])
            && Spells(column, word, out int end)
            && (end >= _text.Length || Separates(_text[end]) || Separates(word[^1]) || word is "EXFN." or "EXFN%." or "FN"));
    }

    // Whether the line's text spells a word from a column, in either case, as CRUNCH matches it, passing spaces inside
    // it; end is the column past the word.
    private bool Spells(int column, string word, out int end)
    {
        end = column;
        foreach (char letter in word)
        {
            while (end < _text.Length && _text[end] == ' ') { end++; }
            if (end >= _text.Length || char.ToUpperInvariant(_text[end]) != letter) { return false; }
            end++;
        }

        return true;
    }

    // CKSEP: anything but a letter, a digit or a period separates Business BASIC's words.
    private static bool Separates(char character) => !(char.IsAsciiLetterOrDigit(character) || character == '.');

    private bool Bbc => _dialect is BbcBasicDialect;

    private bool Mbasic => _dialect == BasicDialect.Mbasic;

    // The characters of a name MBASIC tells apart.
    private const int MbasicSignificant = 40;

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
