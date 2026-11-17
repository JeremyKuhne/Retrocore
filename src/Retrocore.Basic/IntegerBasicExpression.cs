// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Globalization;

namespace Retrocore.Basic;

/// <summary>
///  Evaluates an Integer BASIC expression against a machine's variables, as the debugger's watches, conditions and
///  Debug Console take them.
/// </summary>
/// <remarks>
///  <para>
///   Integer BASIC works in 16-bit integers from -32767 to 32767: <c>/</c> truncates, <c>MOD</c> is the remainder of
///   the two sizes, negative when the two signs differ (<c>5 MOD -3</c> is -2, <c>-5 MOD -3</c> is 2), a comparison
///   is 1 or 0, and <c>#</c> is the same as <c>&lt;&gt;</c>. <c>A(n)</c> is element n of an array, counting from 0
///   (from 1 in Apple-1 BASIC), and a simple variable is its own first element. <c>A$(i)</c> is the string from character i
///   and <c>A$(i,j)</c> characters i to j, counting from 1. Functions that read the machine's state or change it,
///   <c>RND</c>, <c>PDL</c> and <c>SCRN(</c>, are refused.
///  </para>
/// </remarks>
internal sealed class IntegerBasicExpression
{
    private const int Largest = 32767;
    private const int MaximumDepth = 32;

    private static readonly string[] s_operators = ["<>", ">=", "<=", "=", "#", "<", ">", "+", "-", "*", "/", "^", "(", ")", ","];
    private static readonly HashSet<string> s_refused = ["RND", "PDL", "SCRN"];

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
    internal IntegerBasicExpression(BasicVariables variables, IBasicMemory memory)
    {
        _variables = variables;
        _memory = memory;
    }

    /// <summary>
    ///  Evaluates an expression.
    /// </summary>
    /// <param name="expression">The expression.</param>
    /// <returns>The result.</returns>
    /// <exception cref="FormatException">The expression is not Integer BASIC, or is refused.</exception>
    internal BasicResult Evaluate(string expression)
    {
        Scan(expression);
        _at = 0;
        BasicValue value = Or();
        if (_at < _tokens.Count) { throw Syntax($"'{string.Join(' ', _tokens.Skip(_at))}' is left over"); }
        return new(value);
    }

    /// <summary>
    ///  Writes a result as Integer BASIC prints it; a string is quoted.
    /// </summary>
    /// <param name="value">The value.</param>
    /// <returns>The text.</returns>
    internal static string Format(BasicValue value)
    {
        if (value.Text is not { } text) { return ((int)value.Number).ToString(CultureInfo.InvariantCulture); }
        return string.Concat("\"", System.Text.Encoding.ASCII.GetString(text), "\"");
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
        while (Peek() is "=" or "#" or "<>" or "<" or ">" or "<=" or ">=")
        {
            string relation = _tokens[_at++];
            BasicValue right = Additive();
            if (left.IsString != right.IsString) { throw Syntax("a string compares only with a string"); }
            int order = left.IsString
                ? string.CompareOrdinal(Text(left), Text(right))
                : Number(left).CompareTo(Number(right));

            if (left.IsString && relation is not ("=" or "#" or "<>"))
            {
                throw Syntax("strings compare only with = and #");
            }

            left = Truth(relation switch
            {
                "=" => order == 0,
                "#" or "<>" => order != 0,
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
            int right = Number(Term());
            left = Checked(add ? Number(left) + right : Number(left) - right);
        }

        return left;
    }

    private BasicValue Term()
    {
        BasicValue left = Power();
        while (Peek() is "*" or "/" or "MOD")
        {
            string operation = _tokens[_at++];
            int right = Number(Power());
            int value = Number(left);
            if (operation != "*" && right == 0) { throw Syntax("division by zero"); }
            left = Checked(operation switch
            {
                "*" => (long)value * right,
                "/" => value / right,
                // The remainder of the sizes, negative when one of the two is: -5 MOD 3 and 5 MOD -3 are -2.
                _ => (value < 0) != (right < 0) ? -(Math.Abs(value) % Math.Abs(right)) : Math.Abs(value) % Math.Abs(right)
            });
        }

        return left;
    }

    private BasicValue Power()
    {
        BasicValue left = Unary();
        while (Take("^"))
        {
            int exponent = Number(Unary());
            if (exponent < 0) { throw Syntax("a negative power"); }
            long result = 1;
            for (int count = 0; count < exponent; count++)
            {
                result *= Number(left);
                if (Math.Abs(result) > Largest)
                {
                    throw new FormatException("*** >32767 ERR: the result is above 32767.");
                }

            }

            left = Checked(result);
        }

        return left;
    }

    private BasicValue Unary()
    {
        if (Take("-")) { return Checked(-Number(Unary())); }
        if (Take("+")) { return Checked(Number(Unary())); }
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
            if (char.IsAsciiDigit(token[0]))
            {
                return int.TryParse(token, NumberStyles.None, CultureInfo.InvariantCulture, out int number) && number <= Largest
                    ? new(number)
                    : throw new FormatException("*** >32767 ERR: a number is above 32767.");
            }

            if (!char.IsAsciiLetter(token[0])) { throw Syntax($"'{token}' does not start an expression"); }
            if (s_refused.Contains(token)) { throw Syntax($"{token} needs the running machine"); }
            return token switch
            {
                "ABS" => Checked(Math.Abs(Number(Argument()))),
                "SGN" => new(Math.Sign(Number(Argument()))),
                "PEEK" => new(_memory.Read(Number(Argument()) & 0xFFFF)),
                "LEN" => new(Text(StringArgument()).Length),
                "ASC" => Ascii(StringArgument()),
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
        string characters = Text(text);
        if (characters.Length == 0) { throw Syntax("ASC of an empty string"); }
        return new(characters[0] | 0x80);
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

        int first = Number(Or());
        int? second = Take(",") ? Number(Or()) : null;
        Expect(")");
        if (text)
        {
            string value = _variables.Find(name) is { } variable
                ? Text(_variables.Read(variable.Kind, variable.ValueAddress))
                : "";

            int last = second ?? value.Length;
            if (first < 1 || last > value.Length || first > last + 1)
            {
                throw new FormatException("*** STRING ERR: the range is outside the string.");
            }

            return BasicValue.Of([.. value[(first - 1)..last].Select(character => (byte)character)]);
        }

        if (second is not null) { throw Syntax("an array has one subscript"); }
        if (_variables.FindArray(name) is { } array)
        {
            if (first < array.LowerBound || first >= array.LowerBound + array.Count)
            {
                throw new FormatException("*** RANGE ERR: the subscript is outside the array.");
            }

            return _variables.Read(array.Kind, array.ElementAddress([first]));
        }

        if (_variables.Find(name) is { } simple && first == _variables.ArrayBase)
        {
            return _variables.Read(simple.Kind, simple.ValueAddress);
        }

        throw new FormatException($"*** RANGE ERR: {name} has no element {first}.");
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

    // Splits the expression into numbers, names, strings, words and operators, as Integer BASIC reads them.
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
                if (close < 0) { throw Syntax("a string has no closing quote"); }
                _tokens.Add(expression[at..(close + 1)]);
                at = close + 1;
                continue;
            }

            if (char.IsAsciiDigit(character))
            {
                int start = at;
                while (at < expression.Length && char.IsAsciiDigit(expression[at])) { at++; }
                _tokens.Add(expression[start..at]);
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
            if (symbol is null) { throw Syntax($"'{character}' is not Integer BASIC"); }
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

    private static BasicValue Checked(long value) =>
        Math.Abs(value) <= Largest ? new(value) : throw new FormatException("*** >32767 ERR: the result is above 32767.");

    private static int Number(BasicValue value) =>
        value.IsString ? throw Syntax("a number is needed, not a string") : (int)value.Number;

    private static string Text(BasicValue value) =>
        value.Text is { } text ? System.Text.Encoding.ASCII.GetString(text) : throw Syntax("a string is needed, not a number");

    private static FormatException Syntax(string why) => new($"*** SYNTAX ERR: {why}.");
}
