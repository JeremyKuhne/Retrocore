// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Globalization;
using System.Text;

namespace Retrocore.Basic;

/// <summary>
///  Evaluates a Business BASIC expression against a machine's variables, as the debugger's watches, conditions and
///  Debug Console take them.
/// </summary>
/// <remarks>
///  <para>
///   Names are any length, with <c>%</c> for an integer, <c>&amp;</c> for a long integer and <c>$</c> for a string;
///   a name BASIC has not made yet is zero or empty. Reals and integers work as reals and long integers as exact
///   64-bit integers; a real mixed with a long integer is a type mismatch, as in BASIC, but a whole number written
///   in the expression works as either. The operators, tightest first, are <c>^</c>; <c>*</c>, <c>/</c>, <c>DIV</c>
///   and <c>MOD</c>; <c>+</c> and <c>-</c>; the comparisons; <c>AND</c>; and <c>OR</c>. <c>NOT</c> and a sign take
///   one value, so <c>NOT A=B</c> is <c>(NOT A)=B</c>. A comparison is 1 or 0. Functions that read the machine or
///   SOS, such as <c>RND(</c>, <c>TIME$</c> and <c>EOF</c>, are refused, as are user functions.
///  </para>
/// </remarks>
internal sealed class BusinessBasicExpression
{
    private const int MaximumDepth = 32;
    private const int Digits = 6;

    private static readonly string[] s_operators =
        ["<>", "><", ">=", "=>", "<=", "=<", "=", "<", ">", "+", "-", "*", "/", "^", "(", ")", ","];
    private static readonly HashSet<string> s_words = ["AND", "OR", "NOT", "MOD", "DIV"];
    private static readonly HashSet<string> s_refused =
    [
        "RND(", "FRE", "PDL(", "BUTTON(", "TYP(", "REC(", "EOF", "ERR", "ERRLIN", "KBD", "TIME$", "DATE$", "PREFIX$",
        "HPOS", "VPOS", "EXFN.", "EXFN%.", "FN", "SPC(", "TAB("
    ];

    private readonly BasicVariables _variables;
    private readonly List<string> _tokens = [];
    private int _at;
    private int _depth;

    /// <summary>
    ///  Creates an evaluator.
    /// </summary>
    /// <param name="variables">The machine's variables.</param>
    internal BusinessBasicExpression(BasicVariables variables) => _variables = variables;

    /// <summary>
    ///  Evaluates an expression.
    /// </summary>
    /// <param name="expression">The expression.</param>
    /// <returns>The result.</returns>
    /// <exception cref="FormatException">The expression is not Business BASIC, or is refused.</exception>
    internal BasicResult Evaluate(string expression)
    {
        Scan(expression);
        _at = 0;
        BasicValue value = Or();
        if (_at < _tokens.Count) { throw Syntax($"'{string.Join(' ', _tokens.Skip(_at))}' is left over"); }
        return new(value);
    }

    /// <summary>
    ///  Writes a value as Business BASIC prints it, without a positive number's leading space; a string is quoted.
    /// </summary>
    /// <param name="value">The value.</param>
    /// <returns>The text.</returns>
    internal static string Format(BasicValue value)
    {
        if (value.Long is long whole) { return whole.ToString(CultureInfo.InvariantCulture); }
        if (value.Text is not { } text) { return BasicNumbers.Format(value.Number, Digits); }
        StringBuilder builder = new("\"");
        foreach (byte character in text) { BasicText.AppendCharacter(builder, character); }
        return builder.Append('"').ToString();
    }

    private BasicValue Or()
    {
        BasicValue left = And();
        while (Take("OR")) { left = Truth(IsTrue(left) | IsTrue(And())); }
        return left;
    }

    private BasicValue And()
    {
        BasicValue left = Relation();
        while (Take("AND")) { left = Truth(IsTrue(left) & IsTrue(Relation())); }
        return left;
    }

    private BasicValue Relation()
    {
        BasicValue left = Additive();
        while (Peek() is "=" or "<>" or "><" or "<" or ">" or "<=" or "=<" or ">=" or "=>")
        {
            string relation = _tokens[_at++];
            BasicValue right = Additive();
            if (left.IsString != right.IsString) { throw Mismatch(); }
            int order = left.IsString ? Compare(Text(left), Text(right)) : CompareNumbers(left, right);
            left = Truth(relation switch
            {
                "=" => order == 0,
                "<>" or "><" => order != 0,
                "<" => order < 0,
                ">" => order > 0,
                "<=" or "=<" => order <= 0,
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
            BasicValue right = Term();
            if (left.IsString || right.IsString)
            {
                if (!add || !left.IsString || !right.IsString) { throw Mismatch(); }
                byte[] joined = [.. Text(left), .. Text(right)];
                if (joined.Length > 255) { throw new FormatException("?STRING TOO LONG ERROR."); }
                left = BasicValue.Of(joined);
                continue;
            }

            left = add
                ? Arithmetic(left, right, (a, b) => checked(a + b), (a, b) => a + b)
                : Arithmetic(left, right, (a, b) => checked(a - b), (a, b) => a - b);
        }

        return left;
    }

    private BasicValue Term()
    {
        BasicValue left = Power();
        while (Peek() is "*" or "/" or "DIV" or "MOD")
        {
            string operation = _tokens[_at++];
            BasicValue right = Power();
            if (left.IsString || right.IsString) { throw Mismatch(); }
            bool zero = right.Long is long divisor ? divisor == 0 : right.Number == 0;
            if (operation != "*" && zero) { throw new FormatException("?DIVISION BY ZERO ERROR."); }
            left = operation switch
            {
                "*" => Arithmetic(left, right, (a, b) => checked(a * b), (a, b) => a * b),
                "/" => new(Real(left) / Real(right)),
                "DIV" => Arithmetic(left, right, (a, b) => a / b, (a, b) => Math.Truncate(a / b)),
                _ => Arithmetic(left, right, (a, b) => a % b, (a, b) => a - (b * Math.Truncate(a / b)))
            };
        }

        return left;
    }

    private BasicValue Power()
    {
        BasicValue left = Unary();
        while (Take("^"))
        {
            BasicValue right = Unary();
            if (left.IsString || right.IsString) { throw Mismatch(); }
            left = new(Math.Pow(Real(left), Real(right)));
        }

        return left;
    }

    private BasicValue Unary()
    {
        if (Take("-"))
        {
            BasicValue value = Unary();
            if (value.IsString) { throw Mismatch(); }
            return value.Long is long whole ? BasicValue.OfLong(checked(-whole)) : new(-value.Number);
        }

        if (Take("+")) { return Unary(); }
        if (Take("NOT")) { return Truth(!IsTrue(Unary())); }
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
            if (char.IsAsciiDigit(token[0]) || token[0] == '.') { return Literal(token); }
            if (!char.IsAsciiLetter(token[0])) { throw Syntax($"'{token}' does not start an expression"); }
            if (s_refused.Contains(token)) { throw Syntax($"{token.TrimEnd('(')} needs the running machine"); }
            return token switch
            {
                "ABS(" => Numeric(Close(Or()), Absolute),
                "INT(" => Numeric(Close(Or()), value => value.Long is null ? new(Math.Floor(value.Number)) : value),
                "SGN(" => Numeric(Close(Or()), value => new(Math.Sign(value.Long ?? value.Number))),
                "SQR(" => Function(value => Math.Sqrt(value)),
                "LOG(" => Function(value => Math.Log(value)),
                "EXP(" => Function(value => Math.Exp(value)),
                "SIN(" => Function(value => Math.Sin(value)),
                "COS(" => Function(value => Math.Cos(value)),
                "TAN(" => Function(value => Math.Tan(value)),
                "ATN(" => Function(value => Math.Atan(value)),
                "LEN(" => new(Text(Close(Or())).Length),
                "ASC(" => Ascii(Text(Close(Or()))),
                "VAL(" => Value(Text(Close(Or()))),
                "STR$(" => BasicValue.Of(Encoding.ASCII.GetBytes(Format(Numeric(Close(Or()), value => value)))),
                "CHR$(" => BasicValue.Of([(byte)Whole(Close(Or()), 0, 255)]),
                "LEFT$(" => Substring(left: true),
                "RIGHT$(" => Substring(left: false),
                "MID$(" => Middle(),
                "INSTR(" => Instr(),
                "CONV(" => Numeric(Close(Or()), value => new(Real(value))),
                "CONV&(" => Numeric(Close(Or()), value => BasicValue.OfLong(Long(value))),
                "CONV%(" => Numeric(Close(Or()), value => new(Whole(value, short.MinValue, short.MaxValue))),
                _ when token.EndsWith('(') => throw Syntax($"{token.TrimEnd('(')} is not supported in the debugger"),
                _ => Variable(token)
            };
        }
        finally
        {
            _depth--;
        }
    }

    // A variable or an array element; a variable BASIC has not made is zero or empty.
    private BasicValue Variable(string name)
    {
        bool text = name.EndsWith('$');
        if (!Take("("))
        {
            if (_variables.Find(name) is not { } variable) { return text ? BasicValue.Of([]) : Zero(name); }
            return _variables.Read(variable.Kind, variable.ValueAddress);
        }

        List<int> subscripts = [Whole(Or(), 0, 32767)];
        while (Take(",")) { subscripts.Add(Whole(Or(), 0, 32767)); }
        Expect(")");
        if (_variables.FindArray(name) is not { } array)
        {
            return text ? BasicValue.Of([]) : Zero(name);
        }

        bool outside = subscripts.Where((index, at) => index >= array.Dimensions[at]).Any();
        if (subscripts.Count != array.Dimensions.Count || outside)
        {
            throw new FormatException("?BAD SUBSCRIPT ERROR.");
        }

        return _variables.Read(array.Kind, array.ElementAddress(subscripts));
    }

    // A number written in the expression: a real, which works as a long integer too when it is whole.
    private static BasicValue Literal(string token) =>
        double.TryParse(token, NumberStyles.Float, CultureInfo.InvariantCulture, out double number)
            ? new(number)
            : throw Syntax($"'{token}' is not a number");

    // Long arithmetic when either side is a long integer, the other a long or a whole number; otherwise reals.
    private static BasicValue Arithmetic(
        BasicValue left,
        BasicValue right,
        Func<long, long, long> exact,
        Func<double, double, double> real)
    {
        if (left.Long is null && right.Long is null) { return new(real(left.Number, right.Number)); }
        try
        {
            return BasicValue.OfLong(exact(Long(left), Long(right)));
        }
        catch (OverflowException)
        {
            throw new FormatException("?OVERFLOW ERROR.");
        }
    }

    private static long Long(BasicValue value)
    {
        if (value.Long is long whole) { return whole; }
        bool integral = value.Number == Math.Truncate(value.Number) && Math.Abs(value.Number) < 9.2233720368547758E18;
        if (!integral) { throw Mismatch(); }

        return (long)value.Number;
    }

    private static double Real(BasicValue value) => value.Long ?? value.Number;

    private static int CompareNumbers(BasicValue left, BasicValue right) =>
        left.Long is long a && right.Long is long b ? a.CompareTo(b) : Real(left).CompareTo(Real(right));

    private static int Compare(byte[] left, byte[] right) => left.AsSpan().SequenceCompareTo(right);

    private static bool IsTrue(BasicValue value) =>
        value.Text is { } text ? text.Length > 0 : (value.Long ?? value.Number) != 0;

    private static BasicValue Absolute(BasicValue value) =>
        value.Long is long whole ? BasicValue.OfLong(checked(Math.Abs(whole))) : new(Math.Abs(value.Number));

    private static BasicValue Truth(bool value) => new(value ? 1 : 0);

    private static BasicValue Zero(string name) => name.EndsWith('&') ? BasicValue.OfLong(0) : new(0);

    private static BasicValue Numeric(BasicValue value, Func<BasicValue, BasicValue> function) =>
        value.IsString ? throw Mismatch() : function(value);

    private BasicValue Function(Func<double, double> function) =>
        new(function(Real(Numeric(Close(Or()), value => value))));

    private static int Whole(BasicValue value, int low, int high)
    {
        if (value.IsString) { throw Mismatch(); }
        double number = Math.Floor(Real(value));
        if (number < low || number > high) { throw new FormatException("?ILLEGAL QUANTITY ERROR."); }
        return (int)number;
    }

    private static byte[] Text(BasicValue value) => value.Text ?? throw Mismatch();

    private static BasicValue Ascii(byte[] text) =>
        text.Length == 0
            ? throw new FormatException("?ILLEGAL QUANTITY ERROR: ASC of an empty string.")
            : new(text[0]);

    private static BasicValue Value(byte[] text)
    {
        string number = Encoding.ASCII.GetString(text).Replace(" ", "", StringComparison.Ordinal).ToUpperInvariant();
        int end = 0;
        while (end < number.Length && (char.IsAsciiDigit(number[end]) || number[end] is '.' or '-' or '+' or 'E'))
        {
            end++;
        }

        bool read = double.TryParse(number[..end], NumberStyles.Float, CultureInfo.InvariantCulture, out double value);
        return new(read ? value : 0);
    }

    private BasicValue Substring(bool left)
    {
        byte[] text = Text(Or());
        Expect(",");
        int count = Whole(Or(), 0, 255);
        Expect(")");
        count = Math.Min(count, text.Length);
        return BasicValue.Of(left ? text[..count] : text[^count..]);
    }

    private BasicValue Middle()
    {
        byte[] text = Text(Or());
        Expect(",");
        int start = Whole(Or(), 1, 255);
        int count = Take(",") ? Whole(Or(), 0, 255) : 255;
        Expect(")");
        if (start > text.Length) { return BasicValue.Of([]); }
        return BasicValue.Of(text[(start - 1)..Math.Min(text.Length, start - 1 + count)]);
    }

    private BasicValue Instr()
    {
        byte[] text = Text(Or());
        Expect(",");
        byte[] find = Text(Or());
        int start = Take(",") ? Whole(Or(), 1, 255) : 1;
        Expect(")");
        if (start > text.Length) { return new(0); }
        int found = text.AsSpan(start - 1).IndexOf(find);
        return new(found < 0 ? 0 : start + found);
    }

    private BasicValue Close(BasicValue value)
    {
        Expect(")");
        return value;
    }

    // Splits the expression into numbers, names (with their type character, and a function's parenthesis), strings,
    // words and operators, as Business BASIC reads them.
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

            bool fraction = character == '.' && at + 1 < expression.Length && char.IsAsciiDigit(expression[at + 1]);
            if (char.IsAsciiDigit(character) || fraction)
            {
                int start = at;
                while (at < expression.Length && (char.IsAsciiDigit(expression[at]) || expression[at] == '.'))
                {
                    at++;
                }

                if (at < expression.Length && expression[at] is 'E' or 'e')
                {
                    int exponent = at + 1;
                    if (exponent < expression.Length && expression[exponent] is '+' or '-') { exponent++; }
                    if (exponent < expression.Length && char.IsAsciiDigit(expression[exponent]))
                    {
                        at = exponent;
                        while (at < expression.Length && char.IsAsciiDigit(expression[at])) { at++; }
                    }
                }

                _tokens.Add(expression[start..at]);
                continue;
            }

            if (char.IsAsciiLetter(character))
            {
                int start = at;
                while (at < expression.Length && (char.IsAsciiLetterOrDigit(expression[at]) || expression[at] == '.'))
                {
                    at++;
                }

                string word = expression[start..at].ToUpperInvariant();
                if (s_words.Contains(word))
                {
                    _tokens.Add(word);
                    continue;
                }

                if (at < expression.Length && expression[at] is '%' or '&' or '$') { word += expression[at++]; }
                if (at < expression.Length && expression[at] == '(' && IsFunction(word + "("))
                {
                    word += "(";
                    at++;
                }

                _tokens.Add(word);
                continue;
            }

            string? symbol = s_operators.FirstOrDefault(
                candidate => string.CompareOrdinal(expression, at, candidate, 0, candidate.Length) == 0);

            if (symbol is null) { throw Syntax($"'{character}' is not Business BASIC"); }
            _tokens.Add(symbol);
            at += symbol.Length;
        }
    }

    // A reserved word that is a function with its parenthesis, from either of Business BASIC's lists.
    private static bool IsFunction(string word) =>
        BusinessBasicDialect.Instance.Functions.Contains(word) || BasicDialect.BusinessBasic.Keywords.Contains(word);

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

    private static FormatException Mismatch() => new("?TYPE MISMATCH ERROR.");

    private static FormatException Syntax(string why) => new($"?SYNTAX ERROR: {why}.");
}
