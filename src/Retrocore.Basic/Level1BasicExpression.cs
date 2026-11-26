// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Globalization;

namespace Retrocore.Basic;

/// <summary>
///  Evaluates a Level I BASIC expression against a machine's variables, as the debugger's watches, conditions and
///  Debug Console take them.
/// </summary>
/// <remarks>
///  <para>
///   As Level I's <c>EXPR</c>: one comparison at most, 1 when it holds and 0 when not, of sums of products of
///   factors, each a number, one of A to Z, an element <c>A(n)</c>, ABS or INT of an expression in parentheses, or
///   an expression in parentheses. A$ and B$ read as their text, and compare with <c>=</c> and <c>&lt;&gt;</c>.
///   RND, MEM and POINT, which read the machine's state, are refused.
///  </para>
/// </remarks>
internal sealed class Level1BasicExpression
{
    private const int MaximumDepth = 32;

    private static readonly string[] s_symbols = ["<>", "><", ">=", "=>", "<=", "=<", "=", "<", ">", "+", "-", "*", "/", "(", ")"];
    private static readonly HashSet<string> s_refused = ["RND", "MEM", "POINT"];

    private readonly BasicVariables _variables;
    private readonly List<string> _tokens = [];
    private int _at;
    private int _depth;

    /// <summary>
    ///  Creates an evaluator.
    /// </summary>
    /// <param name="variables">The machine's variables.</param>
    internal Level1BasicExpression(BasicVariables variables) => _variables = variables;

    /// <summary>
    ///  Evaluates an expression.
    /// </summary>
    /// <param name="expression">The expression.</param>
    /// <returns>The result.</returns>
    /// <exception cref="FormatException">The expression is not Level I's, or is refused.</exception>
    internal BasicResult Evaluate(string expression)
    {
        Scan(expression);
        _at = 0;
        BasicValue value = Relation();
        if (_at < _tokens.Count) { throw Syntax($"'{string.Join(' ', _tokens.Skip(_at))}' is left over"); }
        return new(value);
    }

    /// <summary>
    ///  Writes a result as Level I prints it, without a positive number's leading space; a string is quoted.
    /// </summary>
    /// <param name="value">The value.</param>
    /// <returns>The text.</returns>
    internal static string Format(BasicValue value) => value.Text is { } text
        ? string.Concat("\"", System.Text.Encoding.ASCII.GetString(text), "\"")
        : Level1Numbers.Format(value.Number);

    private BasicValue Relation()
    {
        BasicValue left = Sum();
        if (Peek() is not ("=" or "<>" or "><" or "<" or ">" or "<=" or "=<" or ">=" or "=>")) { return left; }
        string relation = _tokens[_at++];
        BasicValue right = Sum();
        if (left.IsString != right.IsString) { throw Syntax("a string compares only with a string"); }
        int order = left.IsString
            ? left.Text.AsSpan().SequenceCompareTo(right.Text.AsSpan())
            : left.Number.CompareTo(right.Number);

        if (left.IsString && relation is not ("=" or "<>" or "><"))
        {
            throw Syntax("strings compare only with = and <>");
        }

        bool holds = relation switch
        {
            "=" => order == 0,
            "<>" or "><" => order != 0,
            "<" => order < 0,
            ">" => order > 0,
            "<=" or "=<" => order <= 0,
            _ => order >= 0
        };

        return new(holds ? 1 : 0);
    }

    private BasicValue Sum()
    {
        // EXPR2 takes a sign before its first term.
        BasicValue left;
        if (Peek() is "+" or "-")
        {
            bool negative = _tokens[_at++] == "-";
            double first = Number(Product());
            left = new(negative ? -first : first);
        }
        else
        {
            left = Product();
        }

        while (Peek() is "+" or "-")
        {
            bool add = _tokens[_at++] == "+";
            double right = Number(Product());
            left = new(add ? Number(left) + right : Number(left) - right);
        }

        return left;
    }

    private BasicValue Product()
    {
        BasicValue left = Factor();
        while (Peek() is "*" or "/")
        {
            bool multiply = _tokens[_at++] == "*";
            double right = Number(Factor());
            if (!multiply && right == 0) { throw Syntax("division by zero (HOW?)"); }
            left = new(multiply ? Number(left) * right : Number(left) / right);
        }

        return left;
    }

    private BasicValue Factor()
    {
        if (++_depth > MaximumDepth) { throw Syntax("the expression is nested too deeply"); }
        try
        {
            string token = Next() ?? throw Syntax("an expression is missing");
            if (token == "(")
            {
                BasicValue inner = Relation();
                Expect(")");
                return inner;
            }

            if (char.IsAsciiDigit(token[0]) || token[0] == '.')
            {
                return double.TryParse(token, NumberStyles.Float, CultureInfo.InvariantCulture, out double number)
                    ? new(number)
                    : throw Syntax($"'{token}' is not a number");
            }

            if (s_refused.Contains(token)) { throw Syntax($"{token} reads the machine, so it is not evaluated here"); }
            if (token is "ABS" or "INT")
            {
                Expect("(");
                double argument = Number(Relation());
                Expect(")");
                return new(token == "ABS" ? Math.Abs(argument) : Math.Floor(argument));
            }

            if (token == "A" && Peek() == "(")
            {
                _at++;
                double subscript = Math.Floor(Number(Relation()));
                Expect(")");
                if (subscript < 0) { throw Syntax("a subscript is not negative (HOW?)"); }
                if (_variables.FindArray("A") is not { } array || subscript >= array.Count)
                {
                    throw Syntax($"A({subscript}) reaches the program (SORRY)");
                }

                return _variables.Read(array.Kind, array.ElementAddress([(int)subscript]));
            }

            return _variables.Find(token) is { } variable
                ? _variables.Read(variable.Kind, variable.ValueAddress)
                : throw Syntax($"'{token}' is not a Level I variable or function");
        }
        finally
        {
            _depth--;
        }
    }

    private void Scan(string expression)
    {
        _tokens.Clear();
        string text = expression.ToUpperInvariant();
        int at = 0;
        while (at < text.Length)
        {
            char character = text[at];
            if (character == ' ')
            {
                at++;
                continue;
            }

            if (char.IsAsciiDigit(character) || character == '.')
            {
                int start = at;
                while (at < text.Length && (char.IsAsciiDigit(text[at]) || text[at] == '.')) { at++; }
                if (at < text.Length && text[at] == 'E')
                {
                    int exponent = at + 1;
                    if (exponent < text.Length && text[exponent] is '+' or '-') { exponent++; }
                    if (exponent < text.Length && char.IsAsciiDigit(text[exponent]))
                    {
                        at = exponent;
                        while (at < text.Length && char.IsAsciiDigit(text[at])) { at++; }
                    }
                }

                _tokens.Add(text[start..at]);
                continue;
            }

            if (char.IsAsciiLetter(character))
            {
                string? word = s_refused.Concat(["ABS", "INT"]).FirstOrDefault(name => text.AsSpan(at).StartsWith(name));
                if (word is not null)
                {
                    _tokens.Add(word);
                    at += word.Length;
                    continue;
                }

                // A$ and B$, or a single letter.
                int length = at + 1 < text.Length && text[at + 1] == '$' ? 2 : 1;
                _tokens.Add(text.Substring(at, length));
                at += length;
                continue;
            }

            string? symbol = s_symbols.FirstOrDefault(candidate => text.AsSpan(at).StartsWith(candidate));
            if (symbol is null) { throw Syntax($"'{character}' is not part of a Level I expression"); }
            _tokens.Add(symbol);
            at += symbol.Length;
        }
    }

    private static double Number(BasicValue value) =>
        value.IsString ? throw Syntax("a string is not a number") : value.Number;

    private string? Peek() => _at < _tokens.Count ? _tokens[_at] : null;

    private string? Next() => _at < _tokens.Count ? _tokens[_at++] : null;

    private void Expect(string token)
    {
        if (Next() != token) { throw Syntax($"'{token}' is missing"); }
    }

    private static FormatException Syntax(string message) => new($"WHAT? {message}.");
}
