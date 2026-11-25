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
///   Numbers are Atari BASIC's: ten significant digits, results rounded to them. Rev. C's precedence holds: NOT, like
///   a sign, takes the operand after it (NOT A=B is (NOT A)=B), and AND is above OR. A comparison is 1 or 0.
///   <c>A(i)</c> and <c>A(i,j)</c> are array elements, counting from 0; <c>A$(i)</c> is the string from character i
///   and <c>A$(i,j)</c> characters i to j, counting from 1. Functions that read the machine's devices or change its
///   state, <c>RND</c>, <c>USR</c>, <c>FRE</c>, <c>PADDLE</c>, <c>STICK</c>, <c>PTRIG</c> and <c>STRIG</c>, are
///   refused.
///  </para>
/// </remarks>
internal sealed class AtariBasicExpression
{
    private const int MaximumDepth = 32;

    private static readonly string[] s_operators = ["<>", ">=", "<=", "=", "<", ">", "+", "-", "*", "/", "^", "(", ")", ","];
    private static readonly HashSet<string> s_refused = ["RND", "USR", "FRE", "PADDLE", "STICK", "PTRIG", "STRIG"];

    private readonly BasicVariables _variables;
    private readonly IBasicMemory _memory;
    private readonly List<string> _tokens = [];
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
        if (value.Text is not { } text) { return AtariNumbers.Format(AtariNumbers.FromDouble(value.Number)); }
        System.Text.StringBuilder builder = new("\"");
        foreach (byte character in text) { BasicText.AppendCharacter(builder, character); }
        return builder.Append('"').ToString();
    }

    private BasicValue Or()
    {
        BasicValue left = And();
        while (Take("OR")) { left = Truth(Number(left) != 0 | Number(And()) != 0); }
        return left;
    }

    private BasicValue And()
    {
        BasicValue left = Relation();
        while (Take("AND")) { left = Truth(Number(left) != 0 & Number(Relation()) != 0); }
        return left;
    }

    private BasicValue Relation()
    {
        BasicValue left = Additive();
        while (Peek() is "=" or "<>" or "<" or ">" or "<=" or ">=")
        {
            string relation = _tokens[_at++];
            BasicValue right = Additive();
            if (left.IsString != right.IsString)
            {
                throw new FormatException("ERROR- 8: a string compares only with a string.");
            }

            int order = left.IsString
                ? string.CompareOrdinal(Text(left), Text(right))
                : Number(left).CompareTo(Number(right));

            left = Truth(relation switch
            {
                "=" => order == 0,
                "<>" => order != 0,
                "<" => order < 0,
                ">" => order > 0,
                "<=" => order <= 0,
                _ => order >= 0
            });
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
        while (Take("^")) { left = Rounded(Math.Pow(Number(left), Number(Unary()))); }
        return left;
    }

    private BasicValue Unary()
    {
        if (Take("-")) { return Rounded(-Number(Unary())); }
        if (Take("+")) { return Rounded(Number(Unary())); }
        if (Take("NOT")) { return Truth(Number(Unary()) == 0); }
        return Primary();
    }

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
            if (char.IsAsciiDigit(token[0]) || token[0] == '.')
            {
                int at = 0;
                byte[] text = [.. token.Select(character => (byte)character), AtariNumbers.EndOfLine];
                return AtariNumbers.Parse(text, ref at) is { } number
                    ? new(AtariNumbers.ToDouble(number))
                    : throw Syntax($"'{token}' is not a number");
            }

            if (!char.IsAsciiLetter(token[0])) { throw Syntax($"'{token}' does not start an expression"); }
            if (s_refused.Contains(token)) { throw Syntax($"{token} needs the running machine"); }
            return token switch
            {
                "ABS" => Rounded(Math.Abs(Number(Argument()))),
                "INT" => Rounded(Math.Floor(Number(Argument()))),
                "SGN" => new(Math.Sign(Number(Argument()))),
                "SQR" => Rounded(Math.Sqrt(Number(Argument()))),
                "EXP" => Rounded(Math.Exp(Number(Argument()))),
                "LOG" => Rounded(Math.Log(Number(Argument()))),
                "CLOG" => Rounded(Math.Log10(Number(Argument()))),
                "SIN" => Rounded(Math.Sin(Number(Argument()))),
                "COS" => Rounded(Math.Cos(Number(Argument()))),
                "ATN" => Rounded(Math.Atan(Number(Argument()))),
                "PEEK" => new(_memory.Read((int)Number(Argument()) & 0xFFFF)),
                "LEN" => new(Text(StringArgument()).Length),
                "ASC" => Ascii(StringArgument()),
                "VAL" => Value(StringArgument()),
                "STR$" => BasicValue.Of([.. Format(new(Number(Argument()))).Select(character => (byte)character)]),
                "CHR$" => BasicValue.Of([(byte)Number(Argument())]),
                _ => Variable(token)
            };
        }
        finally
        {
            _depth--;
        }
    }

    private static BasicValue Ascii(BasicValue text)
    {
        byte[] characters = text.Text ?? [];
        return characters.Length == 0 ? throw new FormatException("ERROR- 3: ASC of an empty string.") : new(characters[0]);
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
            if (_variables.Find(name) is not { } variable) { return text ? BasicValue.Of([]) : new(0); }
            return _variables.Read(variable.Kind, variable.ValueAddress);
        }

        int first = (int)Number(Or());
        int? second = Take(",") ? (int)Number(Or()) : null;
        Expect(")");
        if (text)
        {
            byte[] value = _variables.Find(name) is { } variable
                ? _variables.Read(variable.Kind, variable.ValueAddress).Text ?? []
                : [];

            int last = second ?? value.Length;
            if (first < 1 || last > value.Length || first > last + 1)
            {
                throw new FormatException("ERROR- 5: the range is outside the string.");
            }

            return BasicValue.Of(value[(first - 1)..last]);
        }

        if (_variables.FindArray(name) is not { } array)
        {
            throw new FormatException($"ERROR- 9: {name} is not DIMensioned.");
        }

        int[] subscripts = second is { } column ? [first, column] : [first];
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
        int at = 0;
        while (at < expression.Length)
        {
            char character = expression[at];
            if (character == ' ')
            {
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

        return new(AtariNumbers.ToDouble(AtariNumbers.FromDouble(value)));
    }

    private static double Number(BasicValue value) =>
        value.IsString ? throw new FormatException("ERROR- 8: a number is needed, not a string.") : value.Number;

    private static string Text(BasicValue value) =>
        value.Text is { } text ? System.Text.Encoding.Latin1.GetString(text) : throw new FormatException("ERROR- 8: a string is needed, not a number.");

    private static FormatException Syntax(string why) => new(string.Create(CultureInfo.InvariantCulture, $"ERROR- : {why}."));
}
