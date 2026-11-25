// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Basic;

/// <summary>
///  Atari BASIC's tokenizer: its syntax tables, matched against a typed line exactly as the line editor's syntax
///  checker (rev. C's <c>EDIT_LINE</c> and <c>CHECK_SYNTAX</c>) matches them.
/// </summary>
/// <remarks>
///  <para>
///   Atari BASIC checks a line's syntax as it tokenizes it: each statement's rule in the syntax tables, a grammar in the
///   checker's codes, says what may follow its name, and the tokens are written as the rule matches, so an operator's
///   token depends on where it is (<c>=</c> is a comparison, a numeric assignment or a string's). This is the ROM's
///   backtracking checker step for step, over the ROM's own table bytes ($A49F-$A879: the statement names, the grammar
///   and the operator names), with its syntax routines for names, numbers and strings. A test compares the tables
///   with the SDK's build of the ROM, and the tokens with the ROM's own tokenizing.
///  </para>
///  <para>
///   Three things are added for the editor: letters outside strings and remarks are matched as capitals, a line too
///   long for the token buffer is refused rather than wrapped, and each token records the character it was made from.
///  </para>
/// </remarks>
internal sealed class AtariBasicSyntax
{
    /// <summary>
    ///  Where the tables start: the statement name table.
    /// </summary>
    internal const int TablesStart = 0xA49F;

    /// <summary>
    ///  The operator name table, whose entries are the tokens from $10.
    /// </summary>
    internal const int OperatorNames = 0xA7DE;

    /// <summary>
    ///  The expression's rule, which the expression codes call.
    /// </summary>
    internal const int RuleExpression = 0xA605;

    /// <summary>
    ///  The statements' token for a line's statement that has no name: an assignment.
    /// </summary>
    internal const byte ImpliedLet = 0x36;

    /// <summary>
    ///  The token of a line kept as typed because it has a syntax error.
    /// </summary>
    internal const byte ErrorToken = 0x37;

    // The syntax routines the rules call, by their addresses less 1, as a rule's ROUTINE code holds them.
    private const int NumericVariable = 0xA31F;
    private const int StringVariable = 0xA323;
    private const int NumericConstant = 0xA3F4;
    private const int StringConstant = 0xA41B;
    private const int EndStatement = 0xA2CE;
    private const int RestOfLine = 0xA2DA;

    // The checker's codes.
    private const int SyntaxCall = 0x00;
    private const int SyntaxRoutine = 0x01;
    private const int SyntaxOr = 0x02;
    private const int SyntaxReturn = 0x03;
    private const int ExpressionCode = 0x05;
    private const int SyntaxToken = 0x0D;
    private const int SyntaxReplace = 0x0F;
    private const int SyntaxBias = 0xC0;
    private const int StatementNameOffset = 2;
    private const int OperatorNamesFirst = 0x10;
    private const int FunctionAtn = 0x44;
    private const int TokenNumber = 0x0E;
    private const int TokenString = 0x0F;
    private const int MaximumVariables = 128;
    private const int StackEntries = 64;
    private const int BufferSize = 256;
    private const byte EndOfLine = AtariNumbers.EndOfLine;
    private const byte NameEnd = 0x80;
    private const byte ValueString = 0x80;
    private const byte ValueArray = 0x40;

    // The line as typed after "0 ", which stands for its number, so the statements start where a typed line's do.
    private const int Prefix = 2;

    /// <summary>
    ///  Atari BASIC rev. C's syntax tables, $A49F-$A879, from the ROM.
    /// </summary>
    internal static byte[] Tables { get; } = Convert.FromHexString("""
        C2A75245CDC5A7444154C1EEA6494E5055D4B7A6434F4C4FD22CA74C4953D41DA7454E5445D2BAA64C45D48EA749C6CC
        A6464FD2E4A64E4558D4B7A6474F54CFB7A6474F2054CFB7A6474F5355C2B7A6545241D0B8A64259C5B8A6434F4ED459
        A7434FCD1AA7434C4F53C5B8A6434CD2B8A64445C759A74449CDB8A6454EC4B8A64E45D713A74F5045CE1DA74C4F41C4
        1DA7534156C53AA75354415455D343A74E4F54C543A7504F494ED411A75849CF5CA74FCE56A7504F4BC5F6A65052494E
        D4B8A65241C4EFA6524541C4E9A6524553544F52C5B8A65245545552CE20A75255CEB8A653544FD0B8A6504FD0F6A6BF
        E2A64745D4B4A65055D4B7A647524150484943D356A7504C4FD456A7504F534954494FCEB8A6444FD356A74452415754
        CF54A7534554434F4C4FD2DCA64C4F434154C552A7534F554EC4FAA64C5052494ED4B8A643534156C5B8A6434C4F41C4
        BAA60080002A4552524F522D20A053544F50504544A0CDC402C2032BBA2CDB02CDD803250F3502260F36022803FE02E8
        0201F4A3020078A603C49C0203230225022602240227021D021F021E022002210222022A022903011FA3C2030D2B0F38
        0EC42C0203120F3C0E020344D20200C8A7D302C2033F2B0F3A00D4A72C032B0F3A0E2C032B0F3AC72C03C4E3C203C802
        CB02011BA40300D0A7A5030123A3C2032B0F370EC42C0203120F3C0E02031D0F2F021E0F30021F0F3102200F3202210F
        3302220F34031C0E120EFA030045A6220F2D0EF10286220F2E007CA6E803011FA3220F2D0E190EC3DC031A0E02030E12
        0E12C403DD12011FA3CB030EC802C603F7DBC20314021603C9BB02EC009AA7B5031C0E03011FA3020123A303B8C20312
        BC02030E12AC12F912F39A03A59703ED9403EA91028F039A120297150203DE8502DB12C402C20300BAA7F403C3F10382
        120045A603BA120045A6E403007CA6030E120E030E120E12B8D503EDD2030EC4C7CD03170218030EC20312BC02031402
        1603011FA30D2B0F390E0053A62C020123A32B0F3B0E2C03AAC3020312BB02030E1BC39B0301F4A30201CEA2C902D4C3
        0203C30203C3C8030E02007CA603C4B30203C6C203BD0203120215030EC30203120E020301DAA201DAA2400241024302
        42033D023E030EC203120F3CBA02038280ACA4BABB9B474F54CF474F5355C254CF535445D0544845CEA33CBD3CBE3EBD
        BCBEBDDEAAABADAF4E4FD44FD2414EC4A8A9BDBD3CBD3CBE3EBDBCBEBDABADA88080A8A8AC535452A4434852A45553D2
        4153C35641CC4C45CE4144D24154CE434FD3504545CB5349CE524EC44652C54558D04C4FC7434C4FC75351D25347CE41
        42D3494ED4504144444CC553544943CB50545249C753545249C700
        """.ReplaceLineEndings(string.Empty));

    private readonly byte[] _raw;
    private readonly byte[] _folded;
    private readonly List<string> _names;
    private readonly byte[] _tokens = new byte[BufferSize];
    private readonly int[] _sources = new int[BufferSize];
    private readonly (int Input, int Output, int Rule)[] _stack = new (int, int, int)[StackEntries];
    private int _cix;
    private int _tokenIndex;
    private int _errorIndex;
    private int _pointer;
    private int _operatorSearched;
    private int _operatorFound;
    private int _operatorEnd;
    private int _nextStatement;
    private byte _valueType;

    private AtariBasicSyntax(ReadOnlySpan<byte> statements, List<string> names)
    {
        _raw = new byte[statements.Length + Prefix + 1];
        _raw[0] = (byte)'0';
        _raw[1] = (byte)' ';
        statements.CopyTo(_raw.AsSpan(Prefix));
        _raw[^1] = EndOfLine;
        _folded = [.. _raw.Select(value => value is >= (byte)'a' and <= (byte)'z' ? (byte)(value & 0x5F) : value)];
        _names = names;
    }


    /// <summary>
    ///  Tokenizes a line's statements as the line editor does after a line number, adding the variables it names.
    /// </summary>
    /// <param name="statements">The statements, in ATASCII, without the line number or an end of line.</param>
    /// <param name="names">
    ///  The variable name table's names, in order: a numeric variable's (<c>A</c>), a string's (<c>A$</c>) or an
    ///  array's (<c>A(</c>). The line's new variables are added at the end; when the line is refused, they are taken
    ///  out again, as the line editor takes them out after a syntax error (after error 4 or 14 it keeps them).
    /// </param>
    /// <returns>The line's tokens after its number and length, or the error the ROM reports.</returns>
    internal static AtariSyntaxResult Tokenize(ReadOnlySpan<byte> statements, List<string> names)
    {
        int count = names.Count;
        AtariSyntaxResult result = new AtariBasicSyntax(statements, names).Run(statements.Length);
        if (result.Error is not null) { names.RemoveRange(count, names.Count - count); }
        return result;
    }

    private static byte Table(int address) =>
        address >= TablesStart && address - TablesStart < Tables.Length ? Tables[address - TablesStart] : (byte)0;

    private byte At(int index) => index < _folded.Length ? _folded[index] : EndOfLine;

    private byte RawAt(int index) => index < _raw.Length ? _raw[index] : EndOfLine;

    private AtariSyntaxResult Run(int length)
    {
        try
        {
            // The line number's two bytes and the line's length come first; the statements start after "0 ".
            _tokenIndex = 3;
            _cix = 1;
            SkipSpaces();
            if (At(_cix) == EndOfLine) { return Done(length); }
            while (true)
            {
                _nextStatement = _tokenIndex;
                Write(0, -1);
                SkipSpaces();
                int start = _cix;
                (_, int entry, int after, int pointer, _) = SearchNames(TablesStart, StatementNameOffset);
                _cix = after;
                Write((byte)entry, start);
                SkipSpaces();
                int rule = Table(pointer) | (Table(pointer + 1) << 8);
                AtariSyntaxOutcome outcome = CheckSyntax(rule);
                if (outcome == AtariSyntaxOutcome.EndStatement)
                {
                    _tokens[_nextStatement] = (byte)_tokenIndex;
                    continue;
                }

                if (outcome == AtariSyntaxOutcome.RestOfLine)
                {
                    while (true)
                    {
                        byte character = RawAt(_cix);
                        int source = _cix++;
                        Write(character, source);
                        if (character == EndOfLine) { break; }
                    }
                }
                else if (outcome == AtariSyntaxOutcome.Failed)
                {
                    return Error("ERROR- : Atari BASIC refuses this statement, and would keep the line as an ERROR- line.", _errorIndex, length);
                }

                _tokens[_nextStatement] = (byte)_tokenIndex;
                if (At(_cix - 1) == EndOfLine) { return Done(length); }
            }
        }
        catch (BasicSyntaxException exception)
        {
            return Error(exception.Message, _cix, length);
        }
    }

    private AtariSyntaxResult Done(int length)
    {
        int end = length;
        return new(
            _tokens[3.._tokenIndex],
            [.. _sources[3.._tokenIndex].Select(source => source < 0 ? -1 : Math.Clamp(source - Prefix, 0, end))],
            Error: null,
            Column: 0);
    }

    private static AtariSyntaxResult Error(string message, int index, int length) =>
        new([], [], message, Math.Clamp(index - Prefix, 0, length));

    // CHECK_SYNTAX: the statement's rule, from its address less 1.
    private AtariSyntaxOutcome CheckSyntax(int rule)
    {
        int depth = 0;
        _stack[0] = (_cix, _tokenIndex, rule);
        _pointer = rule;
        bool failed = false;
        while (true)
        {
            int code = ReadCode();
            if (failed)
            {
                // CHECK_SYNTAX_FAIL: on to the rule's next alternative, or its end, which fails it in its caller.
                if (code >= 0x80 || code > SyntaxReturn) { continue; }
                if (code < SyntaxOr)
                {
                    _pointer += 2;
                    continue;
                }

                if (code == SyntaxReturn)
                {
                    if (depth == 0) { return AtariSyntaxOutcome.Failed; }
                    _pointer = _stack[depth--].Rule;
                    continue;
                }

                if (_cix >= _errorIndex) { _errorIndex = _cix; }
                (_cix, _tokenIndex, _) = _stack[depth];
                failed = false;
                continue;
            }

            if (code >= 0x80)
            {
                // Relative: the code less the bias, less 1 for the pointer's step before each read.
                Push(_pointer + code - (SyntaxBias + 1), ref depth);
            }
            else if (code == SyntaxCall)
            {
                int low = ReadCode();
                Push(low | (ReadCode() << 8), ref depth);
            }
            else if (code == SyntaxRoutine)
            {
                int low = ReadCode();
                AtariSyntaxOutcome outcome = Routine(low | (ReadCode() << 8));
                if (outcome is AtariSyntaxOutcome.EndStatement or AtariSyntaxOutcome.RestOfLine) { return outcome; }
                failed = outcome == AtariSyntaxOutcome.Failed;
            }
            else if (code < ExpressionCode)
            {
                // SYNTAX_OR or SYNTAX_RETURN: the alternative matched, and so the rule.
                if (depth == 0) { return AtariSyntaxOutcome.Matched; }
                _pointer = _stack[depth--].Rule;
            }
            else if (code == SyntaxReplace)
            {
                _tokens[_tokenIndex - 1] = (byte)ReadCode();
            }
            else if (code > SyntaxReplace)
            {
                SkipSpaces();
                failed = !MatchOperator();
            }
            else if (code == SyntaxToken)
            {
                _pointer++;
                failed = !MatchOperator();
            }
            else
            {
                Push(RuleExpression - 1, ref depth);
            }
        }
    }

    // CHECK_SYNTAX_PUSH: an entry for a rule as it starts.
    private void Push(int rule, ref int depth)
    {
        // CHECK_SYNTAX_TOO_LONG: a full syntax stack is error 14 too, as a long PRINT list or deep brackets fill it.
        if (++depth == StackEntries)
        {
            throw new BasicSyntaxException("ERROR- 14: the line nests too deeply for Atari BASIC's syntax stack.");
        }

        _stack[depth] = (_cix, _tokenIndex, _pointer);
        _pointer = rule;
    }

    private int ReadCode() => Table(++_pointer);

    private AtariSyntaxOutcome Routine(int address) => address switch
    {
        NumericVariable => Variable(isString: false) ? AtariSyntaxOutcome.Matched : AtariSyntaxOutcome.Failed,
        StringVariable => Variable(isString: true) ? AtariSyntaxOutcome.Matched : AtariSyntaxOutcome.Failed,
        NumericConstant => Number() ? AtariSyntaxOutcome.Matched : AtariSyntaxOutcome.Failed,
        StringConstant => StringConstantRoutine() ? AtariSyntaxOutcome.Matched : AtariSyntaxOutcome.Failed,
        EndStatement => AtariSyntaxOutcome.EndStatement,
        RestOfLine => AtariSyntaxOutcome.RestOfLine,
        _ => AtariSyntaxOutcome.Failed
    };

    // MATCH_OPERATOR_HERE: the operator the code at the pointer wants, at CIX; the search is kept for the place.
    private bool MatchOperator()
    {
        if (_cix != _operatorSearched)
        {
            _operatorSearched = _cix;
            (bool found, int entry, int after, _, _) = SearchNames(OperatorNames, 0);
            if (!found)
            {
                _operatorFound = 0;
                return false;
            }

            _operatorEnd = after;
            _operatorFound = entry + OperatorNamesFirst;
        }

        int wanted = Table(_pointer);
        if (wanted != _operatorFound && (wanted != FunctionAtn || _operatorFound < FunctionAtn)) { return false; }
        Write((byte)_operatorFound, _cix);
        _cix = _operatorEnd;
        return true;
    }

    // SYNTAX_NUMERIC_VARIABLE and SYNTAX_STRING_VARIABLE: a variable's name, made a variable when it is new.
    private bool Variable(bool isString)
    {
        _valueType = isString ? ValueString : (byte)0;
        SkipSpaces();
        int start = _cix;
        if (!IsLetter(At(_cix))) { return false; }

        // A name that starts with an operator's (NOT, AND, TO...) is one only when a letter or digit follows that name.
        MatchOperator();
        if (_operatorFound != 0 && At(_operatorEnd) < '0') { return false; }
        do { _cix++; } while (IsLetter(At(_cix)) || IsDigit(At(_cix)));
        int end = _cix;
        if (At(end) == '$')
        {
            if ((_valueType & ValueString) == 0) { return false; }
            end++;
        }
        else
        {
            if ((_valueType & ValueString) != 0) { return false; }
            if (At(end) == '(')
            {
                end++;
                _valueType |= ValueArray;
            }
        }

        string name = System.Text.Encoding.Latin1.GetString(_folded, start, end - start);
        int number = _names.IndexOf(name);
        if (number < 0)
        {
            number = _names.Count;
            _names.Add(name);
        }

        if ((_valueType & ValueArray) != 0) { end--; }
        _cix = end;
        if (number >= MaximumVariables)
        {
            throw new BasicSyntaxException("ERROR- 4: Atari BASIC has room for 128 variables.");
        }

        Write((byte)(0x80 | number), start);
        return true;
    }

    // SYNTAX_NUMERIC_CONSTANT: a number, as AFP reads it, and its six bytes.
    private bool Number()
    {
        SkipSpaces();
        int start = _cix;
        int at = _cix;
        byte[]? number = AtariNumbers.Parse(_folded, ref at);
        if (number is null)
        {
            _cix = start;
            return false;
        }

        _cix = at;
        // SYNTAX_NUMERIC_CONSTANT writes the six bytes past WRITE_TOKEN's check, so on the machine a constant that
        // runs past the buffer's end wraps into the line's start; here it is error 14, as the token before it would be.
        Write(TokenNumber, start);
        foreach (byte value in number) { Write(value, start); }
        return true;
    }

    // SYNTAX_STRING_CONSTANT: a string, its length and its characters; the closing quote may be missing.
    private bool StringConstantRoutine()
    {
        SkipSpaces();
        if (At(_cix) != '"') { return false; }
        Write(TokenString, _cix);
        int lengthAt = _tokenIndex;
        Write(0, _cix);
        while (true)
        {
            byte character = RawAt(++_cix);
            if (character == EndOfLine) { break; }
            if (character == '"')
            {
                _cix++;
                break;
            }

            Write(character, _cix);
        }

        _tokens[lengthAt] = (byte)(_tokenIndex - lengthAt - 1);
        return true;
    }

    // SEARCH_NAMES: the first entry whose whole name the line starts with at CIX; in the statement table, a "." ends a
    // name early, and elsewhere it is compared as $02.
    private (bool Found, int Entry, int After, int Pointer, int Offset) SearchNames(int table, int nameOffset)
    {
        int entry = -1;
        int pointer = table;
        while (true)
        {
            entry++;
            int x = _cix;
            int y = nameOffset;
            if (Table(pointer + y) == 0) { return (false, entry, _cix, pointer, y); }
            bool differs = false;
            bool last;
            do
            {
                int character = At(x) & 0x7F;
                if (character == '.' && nameOffset == StatementNameOffset)
                {
                    while ((Table(pointer + y) & NameEnd) == 0) { y++; }
                    last = true;
                }
                else
                {
                    if (character == '.') { character = 0x02; }
                    int difference = character ^ Table(pointer + y);
                    last = (difference & 0x80) != 0;
                    if ((difference & 0x7F) != 0) { differs = true; }
                }

                y++;
                x++;
            }
            while (!last);

            if (!differs) { return (true, entry, x, pointer, y); }
            pointer += y;
        }
    }

    private void SkipSpaces()
    {
        while (At(_cix) == ' ') { _cix++; }
    }

    private void Write(byte token, int source)
    {
        // WRITE_TOKEN stores the token, then refuses the line when TOKEN_INDEX wraps to 0: the last byte is never kept.
        _sources[_tokenIndex] = source;
        _tokens[_tokenIndex++] = token;
        if (_tokenIndex >= BufferSize) { throw TooLong(); }
    }

    private static bool IsLetter(byte value) => value is >= (byte)'A' and <= (byte)'Z';

    private static bool IsDigit(byte value) => value is >= (byte)'0' and <= (byte)'9';

    private static BasicSyntaxException TooLong() => new("ERROR- 14: the line is too long for Atari BASIC's token buffer.");
}
