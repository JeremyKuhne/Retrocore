// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Globalization;

namespace Retrocore.Basic;

/// <summary>
///  Evaluates an Atari BASIC expression against a machine's variables, as the debugger's watches, conditions and
///  Debug Console take them.
/// </summary>
/// <remarks>
///  <para>
///   Numbers are Atari BASIC's ten significant digits. Results are .NET's, kept to ten digits as
///   <see cref="AtariNumbers.FromDouble"/> keeps them, where the FP package drops the digits it shifts out and works
///   out its functions by series, so a last digit can differ: ATN(1) in degrees is 45 here and 45.0000003 on the
///   machine. Rev. C's precedence holds: a string comparison binds above everything (NOT A$=B$ is NOT (A$=B$)); NOT,
///   like a sign, takes the operand after it (NOT A=B is (NOT A)=B), and only one of them, though a sign right before
///   a number is the constant's (- -1 is 1, and - - 1 is refused); AND is above OR. A comparison is 1 or 0. AND, as
///   OPERATOR_AND, ANDs the exponent bytes, so 1 AND 0.5 is 0. A name that starts with NOT, AND or OR where that
///   operator can go is the operator and a name, as MATCH_OPERATOR reads it: NOTE1 is NOT E1, and NOTA$="X" is
///   NOT (A$="X"), though NOTA$ alone is the string, as the grammar falls back to it when NOT's operand fails, and
///   NOTSIN+1 is the name NOTSIN plus 1, SIN having no (, as NOTAND+1 is NOTAND plus 1. A function's name or an
///   operator word is a variable only before a character from '0' up, the end among them, as SYNTAX_VARIABLE takes
///   it: SIN alone is a variable, NOTSIN alone NOT SIN and NOTAND=1 NOT AND=1, where OR+1 and TO$ are refused. A
///   string that no DIM has given room is error 9, and its substring error 5, its length being 0.
///   <c>A(i)</c> and <c>A(i,j)</c> are array elements, counting from 0, <c>A(i)</c> being <c>A(i,0)</c>;
///   <c>A$(i)</c> is the string from character i and <c>A$(i,j)</c> characters i to j, counting from 1, never empty.
///   Subscripts, indexes and the arguments of PEEK and CHR$ round to an integer from 0 to 65535, or are error 3; a
///   subscript of 32768 up is error 9. SIN, COS and ATN work in degrees after DEG, as DEGFLG says. ASC of an empty
///   string is refused, where the ROM returns the byte the first character would be.
///  </para>
///  <para>
///   Functions that read the machine's devices, its memory's layout or change its state, <c>RND</c>, <c>USR</c>,
///   <c>FRE</c>, <c>ADR</c>, <c>PADDLE</c>, <c>STICK</c>, <c>PTRIG</c> and <c>STRIG</c>, are refused.
///  </para>
/// </remarks>
internal sealed class AtariBasicExpression
{
    private const int MaximumDepth = 32;

    private static readonly string[] s_operators = ["<>", ">=", "<=", "=", "<", ">", "+", "-", "*", "/", "^", "(", ")", ","];
    private static readonly HashSet<string> s_refused = ["RND", "USR", "FRE", "ADR", "PADDLE", "STICK", "PTRIG", "STRIG"];

    // The functions' names, from the operator name table.
    private static readonly HashSet<string> s_functions =
    [
        "STR$", "CHR$", "USR", "ASC", "VAL", "LEN", "ADR", "ATN", "COS", "PEEK", "SIN", "RND", "FRE", "EXP", "LOG",
        "CLOG", "SQR", "SGN", "ABS", "INT", "PADDLE", "STICK", "PTRIG", "STRIG"
    ];

    // The operator name table's words that aren't functions, which no name is here.
    private static readonly HashSet<string> s_words = ["GOTO", "GOSUB", "TO", "STEP", "THEN", "NOT", "OR", "AND"];

    // DEGFLG, the OS's flag that DEG sets for SIN, COS and ATN: 0 for radians.
    private const int DegreesFlag = 0xFB;

    private readonly BasicVariables _variables;
    private readonly IBasicMemory _memory;
    private readonly List<string> _tokens = [];

    // The tokens with a space before them, by index.
    private readonly HashSet<int> _spaced = [];
    private int _at;
    private int _depth;

    /// <summary>
    ///  Creates an evaluator.
    /// </summary>
    /// <param name="variables">The machine's variables.</param>
    /// <param name="memory">The memory, for PEEK.</param>
    internal AtariBasicExpression(BasicVariables variables, IBasicMemory memory)
    {
        _variables = variables;
        _memory = memory;
    }

    /// <summary>
    ///  Evaluates an expression.
    /// </summary>
    /// <param name="expression">The expression.</param>
    /// <returns>The result.</returns>
    /// <exception cref="FormatException">The expression is not Atari BASIC, or is refused.</exception>
    internal BasicResult Evaluate(string expression)
    {
        Scan(expression);
        _at = 0;
        BasicValue value = Or();
        if (_at < _tokens.Count) { throw Syntax($"'{string.Join(' ', _tokens.Skip(_at))}' is left over"); }
        return new(value);
    }

    /// <summary>
    ///  Writes a result as Atari BASIC prints it; a string is quoted.
    /// </summary>
    /// <param name="value">The value.</param>
    /// <returns>The text.</returns>
    internal static string Format(BasicValue value)
    {
        if (value.Text is not { } text) { return AtariNumbers.Format(Atari(value.Number)); }
        System.Text.StringBuilder builder = new("\"");
        foreach (byte character in text) { BasicText.AppendCharacter(builder, character); }
        return builder.Append('"').ToString();
    }

    private BasicValue Or()
    {
        BasicValue left = And();
        while (TakeWord("OR")) { left = Truth(Number(left) != 0 | Number(And()) != 0); }
        return left;
    }

    private BasicValue And()
    {
        BasicValue left = Relation();
        // OPERATOR_AND ANDs the exponent bytes, so 1 AND 0.01 is 0 ($40 and $3F).
        while (TakeWord("AND")) { left = Truth((Atari(Number(left))[0] & Atari(Number(Relation()))[0]) != 0); }
        return left;
    }

    private BasicValue Relation()
    {
        BasicValue left = Additive();
        while (Peek() is "=" or "<>" or "<" or ">" or "<=" or ">=")
        {
            string relation = _tokens[_at++];
            BasicValue right = Additive();
            // A string's comparisons are Operand's, so a string here is compared with a number.
            if (right.IsString)
            {
                throw Syntax("a string compares only with a string");
            }

            left = Truth(Compare(relation, Number(left).CompareTo(Number(right))));
        }

        return left;
    }

    private BasicValue Additive()
    {
        BasicValue left = Term();
        while (Peek() is "+" or "-")
        {
            bool add = _tokens[_at++] == "+";
            double right = Number(Term());
            left = Rounded(add ? Number(left) + right : Number(left) - right);
        }

        return left;
    }

    private BasicValue Term()
    {
        BasicValue left = Power();
        while (Peek() is "*" or "/")
        {
            bool multiply = _tokens[_at++] == "*";
            double right = Number(Power());
            if (!multiply && right == 0) { throw new FormatException("ERROR- 11: division by zero."); }
            left = Rounded(multiply ? Number(left) * right : Number(left) / right);
        }

        return left;
    }

    private BasicValue Power()
    {
        BasicValue left = Unary();
        while (Take("^"))
        {
            double number = Number(left);
            double power = Number(Unary());

            // OPERATOR_POWER: error 3 for 0 to a negative power and a negative number to a fraction; 11 for overflow.
            if ((number == 0 && power < 0) || (number < 0 && power != Math.Floor(power)))
            {
                throw new FormatException("ERROR- 3: the power has no value.");
            }

            left = Rounded(Math.Pow(number, power));
        }

        return left;
    }

    // From rev. B the grammar takes one sign or NOT before an operand, not two; a sign before a number is the
    // constant's own, so - -1 is 1.
    private BasicValue Unary()
    {
        if (Take("-")) { return Rounded(-Number(Operand())); }
        if (Take("+")) { return Rounded(Number(Operand())); }
        int at = _at;
        string? whole = Peek();
        if (TakeWord("NOT") && whole is { Length: > 3 })
        {
            // NOT$ is no name, as SYNTAX_VARIABLE refuses an operator's name with a character below '0' after it.
            if (whole == "NOT$") { throw Syntax("NOT$ is not a name"); }

            // The rest of the name is NOT's operand where the grammar takes it as one; otherwise RULE_EXPRESSION's
            // NOT fails, and the grammar takes the whole name. The rest is an operand as a function with its (, or as
            // a name where SYNTAX_VARIABLE takes one (NOTAND=1 is NOT AND=1, NOTAND+1 the name NOTAND plus 1); a
            // string, as NOTA$, only with a relation after it and its indexes. It decides by the grammar, not the
            // values.
            string rest = _tokens[at];
            bool bracketed = at + 1 < _tokens.Count && _tokens[at + 1] == "(";
            bool operand = (bracketed && s_functions.Contains(rest)) || Nameable(at);
            if (operand && (!whole.EndsWith('$') || ComparisonFollows(at))) { return Truth(Number(Operand()) == 0); }
            _tokens[at] = whole;
            return Operand();
        }

        if (whole == "NOT") { return Truth(Number(Operand()) == 0); }

        return Operand();
    }

    // SYNTAX_VARIABLE: whether the token at an index can be a name. MATCH_OPERATOR finds any operator's name the
    // text starts with, and a function's name or an operator word is a name only with a character from '0' up after
    // it, the line's end among them: SIN at the end is a variable, SIN+1 or TO$ none.
    private bool Nameable(int index)
    {
        string token = _tokens[index];
        if (token.Length > 1 && token.EndsWith('$') && !s_functions.Contains(token) && IsTableName(token[..^1]))
        {
            return false;
        }

        if (!IsTableName(token)) { return true; }
        int next = index + 1;
        if (next >= _tokens.Count) { return true; }
        return !_spaced.Contains(next) && _tokens[next][0] >= '0';
    }

    private static bool IsTableName(string token) => s_words.Contains(token) || s_functions.Contains(token);

    // Whether a relation follows the name at an index and the bracketed indexes after it.
    private bool ComparisonFollows(int name)
    {
        int at = name + 1;
        if (at < _tokens.Count && _tokens[at] == "(")
        {
            int depth = 0;
            for (; at < _tokens.Count; at++)
            {
                if (_tokens[at] == "(") { depth++; }
                else if (_tokens[at] == ")" && --depth == 0) { at++; break; }
            }
        }

        return at < _tokens.Count && _tokens[at] is "=" or "<>" or "<" or ">" or "<=" or ">=";
    }

    // An operand, and the string comparisons, which bind above every other operator.
    private BasicValue Operand()
    {
        BasicValue left = Primary();
        while (left.IsString && Peek() is "=" or "<>" or "<" or ">" or "<=" or ">=")
        {
            string relation = _tokens[_at++];
            BasicValue right = Primary();
            if (!right.IsString) { throw Syntax("a string compares only with a string"); }
            left = Truth(Compare(relation, string.CompareOrdinal(Text(left), Text(right))));
        }

        return left;
    }

    private static bool Compare(string relation, int order) => relation switch
    {
        "=" => order == 0,
        "<>" => order != 0,
        "<" => order < 0,
        ">" => order > 0,
        "<=" => order <= 0,
        _ => order >= 0
    };

    private BasicValue Primary()
    {
        if (++_depth > MaximumDepth) { throw Syntax("the expression is too deep"); }
        try
        {
            string token = Peek() ?? throw Syntax("an expression is missing");
            _at++;
            if (token == "(")
            {
                BasicValue inner = Or();
                Expect(")");
                return inner;
            }

            if (token[0] == '"') { return BasicValue.Of([.. token[1..^1].Select(character => (byte)character)]); }
            if (IsNumber(token)) { return new(Constant(token)); }

            // SYNTAX_NUMERIC_CONSTANT reads with AFP, which takes a sign with the number right after it.
            if (token is "-" or "+" && Peek() is { } digits && IsNumber(digits) && !_spaced.Contains(_at))
            {
                _at++;
                double constant = Constant(digits);
                return new(token == "-" ? -constant : constant);
            }

            if (!char.IsAsciiLetter(token[0])) { throw Syntax($"'{token}' does not start an expression"); }

            // RULE_OPERAND tries a function, with its (, before a name.
            if (!(s_functions.Contains(token) && Peek() == "("))
            {
                return Nameable(_at - 1) ? Variable(token) : throw Syntax($"{token} is not a name here");
            }

            if (s_refused.Contains(token)) { throw Syntax($"{token} needs the running machine"); }
            return token switch
            {
                "ABS" => Rounded(Math.Abs(Number(Argument()))),
                "INT" => Rounded(Math.Floor(Number(Argument()))),
                "SGN" => new(Math.Sign(Number(Argument()))),
                "SQR" => Function(Math.Sqrt(Number(Argument()))),
                "EXP" => Function(Math.Exp(Number(Argument()))),
                "LOG" => Function(Math.Log(Number(Argument()))),
                "CLOG" => Function(Math.Log10(Number(Argument()))),
                "SIN" => Function(Math.Sin(Number(Argument()) * Radians)),
                "COS" => Function(Math.Cos(Number(Argument()) * Radians)),
                "ATN" => Function(Math.Atan(Number(Argument())) / Radians),
                "PEEK" => new(_memory.Read(Unsigned(Argument()))),
                "LEN" => new(Text(StringArgument()).Length),
                "ASC" => Ascii(StringArgument()),
                "VAL" => Value(StringArgument()),
                "STR$" => BasicValue.Of([.. Format(new(Number(Argument()))).Select(character => (byte)character)]),
                "CHR$" => BasicValue.Of([(byte)Unsigned(Argument())]),
                _ => Variable(token)
            };
        }
        finally
        {
            _depth--;
        }
    }

    private static bool IsNumber(string token) => char.IsAsciiDigit(token[0]) || token[0] == '.';

    private static double Constant(string token)
    {
        int at = 0;
        byte[] text = [.. token.Select(character => (byte)character), AtariNumbers.EndOfLine];
        // AFP stops where the number does; what follows it, as in 1.2.3, continues no expression.
        return AtariNumbers.Parse(text, ref at) is { } number && at == token.Length
            ? AtariNumbers.ToDouble(number)
            : throw Syntax($"'{token}' is not a number");
    }

    private static BasicValue Ascii(BasicValue text)
    {
        byte[] characters = text.Text ?? [];
        return characters.Length == 0
            ? throw Syntax("ASC of an empty string reads past it, which BASIC allows but this refuses")
            : new(characters[0]);
    }

    private static BasicValue Value(BasicValue text)
    {
        int at = 0;
        byte[] characters = [.. text.Text ?? [], AtariNumbers.EndOfLine];
        return AtariNumbers.Parse(characters, ref at) is { } number
            ? new(AtariNumbers.ToDouble(number))
            : throw new FormatException("ERROR- 18: VAL of a string that is not a number.");
    }

    // A variable, an array element, or a substring.
    private BasicValue Variable(string name)
    {
        bool text = name.EndsWith('$');
        if (!Take("("))
        {
            if (_variables.Find(name) is not { } variable) { return text ? throw NotDimensioned(name) : new(0); }
            if (text && !Dimensioned(variable)) { throw NotDimensioned(name); }
            return _variables.Read(variable.Kind, variable.ValueAddress);
        }

        int first = Unsigned(Or());
        int? second = Take(",") ? Unsigned(Or()) : null;
        Expect(")");
        if (text)
        {
            // OPERATOR_STRING_PAREN reads no DIM: a string without one has length 0, so any range is error 5.
            byte[] value = _variables.Find(name) is { } variable && Dimensioned(variable)
                ? _variables.Read(variable.Kind, variable.ValueAddress).Text ?? []
                : [];

            // OPERATOR_STRING_PAREN: error 5 for an index of 0, a last beyond the length, or nothing between them.
            int last = second ?? value.Length;
            if (first < 1 || last > value.Length || first > last)
            {
                throw new FormatException("ERROR- 5: the range is outside the string.");
            }

            return BasicValue.Of(value[(first - 1)..last]);
        }

        if (_variables.FindArray(name) is not { } array)
        {
            throw NotDimensioned(name);
        }

        // Every array has two sizes, a single one's second being 1 (the variables list it as one), and a missing
        // second subscript is 0: A(I) is A(I,0) whichever way the array was DIMensioned.
        int column = second ?? 0;
        if (array.Dimensions.Count == 1 && column != 0)
        {
            throw new FormatException($"ERROR- 9: {name}({first},{column}) is outside the array.");
        }

        int[] subscripts = array.Dimensions.Count == 2 ? [first, column] : [first];
        try
        {
            return _variables.Read(array.Kind, array.ElementAddress(subscripts));
        }
        catch (ArgumentOutOfRangeException)
        {
            throw new FormatException($"ERROR- 9: {name}({string.Join(',', subscripts)}) is outside the array.");
        }
    }

    private BasicValue Argument()
    {
        Expect("(");
        BasicValue value = Or();
        Expect(")");
        return value;
    }

    private BasicValue StringArgument()
    {
        BasicValue value = Argument();
        return value.IsString ? value : throw Syntax("the function takes a string");
    }

    // Splits the expression into numbers, names, strings, words and operators, as Atari BASIC reads them.
    private void Scan(string expression)
    {
        _tokens.Clear();
        _spaced.Clear();
        int at = 0;
        while (at < expression.Length)
        {
            char character = expression[at];
            if (character == ' ')
            {
                _spaced.Add(_tokens.Count);
                at++;
                continue;
            }

            if (character == '"')
            {
                int close = expression.IndexOf('"', at + 1);
                if (close < 0) { close = expression.Length; }
                _tokens.Add(expression[at..Math.Min(close + 1, expression.Length)] + (close == expression.Length ? "\"" : ""));
                at = close + 1;
                continue;
            }

            if (char.IsAsciiDigit(character) || character == '.')
            {
                int start = at;
                while (at < expression.Length && (char.IsAsciiDigit(expression[at]) || expression[at] == '.')) { at++; }
                if (at < expression.Length && char.ToUpperInvariant(expression[at]) == 'E')
                {
                    int exponent = at + 1;
                    if (exponent < expression.Length && expression[exponent] is '+' or '-') { exponent++; }
                    if (exponent < expression.Length && char.IsAsciiDigit(expression[exponent]))
                    {
                        at = exponent;
                        while (at < expression.Length && char.IsAsciiDigit(expression[at])) { at++; }
                    }
                }

                _tokens.Add(expression[start..at].ToUpperInvariant());
                continue;
            }

            if (char.IsAsciiLetter(character))
            {
                int start = at;
                while (at < expression.Length && char.IsAsciiLetterOrDigit(expression[at])) { at++; }
                if (at < expression.Length && expression[at] == '$') { at++; }
                _tokens.Add(expression[start..at].ToUpperInvariant());
                continue;
            }

            int from = at;
            string? symbol = s_operators.FirstOrDefault(candidate => Matches(expression, from, candidate));
            if (symbol is null) { throw Syntax($"'{character}' is not Atari BASIC"); }
            _tokens.Add(symbol);
            at += symbol.Length;
        }
    }

    private static bool Matches(string text, int at, string candidate) =>
        at + candidate.Length <= text.Length && text.AsSpan(at, candidate.Length).SequenceEqual(candidate);

    // A string that DIM has given room; one without is error 9 where POP_ABSOLUTE_VALUE reads it.
    private bool Dimensioned(BasicVariable variable) => (_memory.Read((variable.ValueAddress - 2) & 0xFFFF) & 0x01) != 0;

    private static FormatException NotDimensioned(string name) => new($"ERROR- 9: {name} is not DIMensioned.");

    // A number's six bytes, or error 11 for one of 1E98 up, beyond FromDouble's exponents, which only bytes written
    // into a variable can hold (AtariNumbers.Format would print them).
    private static byte[] Atari(double value)
    {
        try
        {
            return AtariNumbers.FromDouble(value);
        }
        catch (OverflowException)
        {
            throw new FormatException("ERROR- 11: the number is out of range.");
        }
    }

    // NOT, AND or OR, also at the start of a name: MATCH_OPERATOR takes the first operator name the text starts with,
    // so NOTE1 after an operator is NOT E1, and A ANDB is A AND B.
    private bool TakeWord(string word)
    {
        if (Take(word)) { return true; }
        if (Peek() is not { } token || token.Length <= word.Length || !token.StartsWith(word, StringComparison.Ordinal))
        {
            return false;
        }

        // AFP reads the number after the word whole: AND1.5 is AND and 1.5, where the scan split it at the point.
        string rest = token[word.Length..];
        int next = _at + 1;
        if (rest.All(char.IsAsciiDigit) && next < _tokens.Count && _tokens[next][0] == '.' && !_spaced.Contains(next))
        {
            rest += _tokens[next];
            _tokens.RemoveAt(next);
            int[] later = [.. _spaced.Where(index => index > next)];
            foreach (int index in later) { _spaced.Remove(index); }
            foreach (int index in later) { _spaced.Add(index - 1); }
        }

        _tokens[_at] = rest;
        return true;
    }

    private string? Peek() => _at < _tokens.Count ? _tokens[_at] : null;

    private bool Take(string token)
    {
        if (Peek() != token) { return false; }
        _at++;
        return true;
    }

    private void Expect(string token)
    {
        if (!Take(token)) { throw Syntax($"'{token}' is missing"); }
    }

    private static BasicValue Truth(bool value) => new(value ? 1 : 0);

    // A result as Atari BASIC keeps it: ten digits, an error from 1E98.
    private static BasicValue Rounded(double value)
    {
        if (double.IsNaN(value) || double.IsInfinity(value))
        {
            throw new FormatException("ERROR- 11: the result is out of range.");
        }

        try
        {
            return new(AtariNumbers.ToDouble(AtariNumbers.FromDouble(value)));
        }
        catch (OverflowException)
        {
            throw new FormatException("ERROR- 11: the result is out of range.");
        }
    }

    // A function's result: the FP package's failure, as for SQR(-1), LOG(0) or EXP(300), is error 3.
    private static BasicValue Function(double value)
    {
        if (double.IsNaN(value) || double.IsInfinity(value) || Math.Abs(value) >= 1E98)
        {
            throw new FormatException("ERROR- 3: the function's argument is out of its range.");
        }

        return Rounded(value);
    }

    // SIN, COS and ATN's unit: a degree after DEG, else a radian.
    private double Radians => _memory.Read(DegreesFlag) == 0 ? 1 : Math.PI / 180;

    // POP_UNSIGNED: a number rounded to an integer from 0 to 65535 as FPI rounds it, or error 3.
    private static int Unsigned(BasicValue value)
    {
        double number = Number(value);
        if (!double.IsNaN(number))
        {
            try
            {
                if (AtariNumbers.ToInteger(AtariNumbers.FromDouble(number)) is { } integer) { return integer; }
            }
            catch (OverflowException)
            {
                // A number of 1E98 up, which only bytes written into a variable can hold.
            }
        }

        throw new FormatException("ERROR- 3: the value is not an integer from 0 to 65535.");
    }

    private static double Number(BasicValue value) =>
        value.IsString ? throw Syntax("a number is needed, not a string") : value.Number;

    private static string Text(BasicValue value) =>
        value.Text is { } text ? System.Text.Encoding.Latin1.GetString(text) : throw Syntax("a string is needed, not a number");

    private static FormatException Syntax(string why) => new(string.Create(CultureInfo.InvariantCulture, $"ERROR- : {why}."));
}
