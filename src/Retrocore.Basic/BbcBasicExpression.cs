// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text;

namespace Retrocore.Basic;

/// <summary>
///  Evaluates a BBC BASIC expression against a machine's variables, as the debugger's watches, conditions and Debug
///  Console take them.
/// </summary>
/// <remarks>
///  <para>
///   The levels are BASIC II's, loosest first: <c>OR</c> and <c>EOR</c>; <c>AND</c>; one relation; <c>+</c> and
///   <c>-</c>; <c>*</c>, <c>/</c>, <c>MOD</c> and <c>DIV</c>; <c>^</c>, from left to right; then a factor, which takes
///   unary <c>-</c>, <c>+</c> and <c>NOT</c> before another factor, so <c>NOT 1+1</c> is -1 and <c>-2^2</c> is 4.
///   <c>AND</c>, <c>OR</c>, <c>EOR</c>, <c>NOT</c>, <c>DIV</c> and <c>MOD</c> work on 32-bit integers; true is -1.
///  </para>
///  <para>
///   A function whose word has no bracket takes a factor, so <c>LEN "abc"</c> and <c>ABS -5</c> work as in BASIC;
///   <c>LEFT$(</c>, <c>RIGHT$(</c>, <c>MID$(</c>, <c>STRING$(</c> and <c>INSTR(</c> take a bracketed list. <c>TRUE</c>,
///   <c>FALSE</c> and <c>PI</c> are constants, and <c>PAGE</c>, <c>TOP</c>, <c>LOMEM</c>, <c>HIMEM</c>,
///   <c>COUNT</c> and <c>ERL</c> are read from BASIC's zero page. Numbers can be hexadecimal, <c>&amp;FF</c>. What
///   needs BASIC or the MOS running, such as <c>RND</c>, <c>TIME</c>, <c>GET</c> and <c>EVAL</c>, is refused.
///  </para>
/// </remarks>
internal sealed class BbcBasicExpression
{
    private const int MaximumDepth = 32;
    private const int MaximumString = 255;

    // BASIC II's zero page: LOMEM, HIMEM, ERL and TOP are words; PAGE is its high byte; COUNT a byte.
    private const int Lomem = 0x00;
    private const int Himem = 0x06;
    private const int ErrorLine = 0x08;
    private const int Top = 0x12;
    private const int PageHigh = 0x18;
    private const int Count = 0x1E;

    private static readonly HashSet<string> s_unary =
    [
        "ABS", "ACS", "ASN", "ATN", "COS", "DEG", "EXP", "INT", "LEN", "LN", "LOG", "RAD", "SGN", "SIN", "SQR", "TAN",
        "ASC", "VAL", "CHR$", "STR$"
    ];

    private readonly BasicVariables _variables;
    private readonly IBasicMemory _memory;
    private readonly Func<string, (string Parameter, string Body)?>? _functions;
    private readonly Dictionary<string, BasicValue> _bound = [with(StringComparer.Ordinal)];
    private byte[] _bytes = [];
    private int _at;
    private int _depth;

    /// <summary>
    ///  Creates an evaluator.
    /// </summary>
    /// <param name="variables">The machine's variables.</param>
    /// <param name="memory">The memory, for the pseudo-variables.</param>
    /// <param name="functions">Finds a one-line DEF FN's parameter and body by name; null for none.</param>
    internal BbcBasicExpression(
        BasicVariables variables,
        IBasicMemory memory,
        Func<string, (string Parameter, string Body)?>? functions)
    {
        _variables = variables;
        _memory = memory;
        _functions = functions;
    }

    /// <summary>
    ///  Evaluates an expression.
    /// </summary>
    /// <param name="expression">The expression.</param>
    /// <returns>The result.</returns>
    /// <exception cref="FormatException">The expression is not BBC BASIC, or is refused.</exception>
    internal BasicResult Evaluate(string expression)
    {
        byte[] saved = _bytes;
        int savedAt = _at;
        try
        {
            _bytes = BbcBasicDialect.TokenizeExpression(expression);
            _at = 0;
            BasicValue value = Expression();
            Skip();
            if (_at < _bytes.Length) { throw Syntax($"'{Rest()}' is left over"); }
            return new(value);
        }
        finally
        {
            _bytes = saved;
            _at = savedAt;
        }
    }

    private BasicValue Expression()
    {
        BasicValue left = And();
        while (true)
        {
            if (TakeWord("OR")) { left = Integer(Int(left) | Int(And())); }
            else if (TakeWord("EOR")) { left = Integer(Int(left) ^ Int(And())); }
            else { return left; }
        }
    }

    private BasicValue And()
    {
        BasicValue left = Relation();
        while (TakeWord("AND")) { left = Integer(Int(left) & Int(Relation())); }
        return left;
    }

    // One relation only, as BASIC takes it: A=B=C is a "Syntax error" left over.
    private BasicValue Relation()
    {
        BasicValue left = Sum();
        Skip();
        if (_at >= _bytes.Length) { return left; }
        Func<int, bool>? holds = _bytes[_at] switch
        {
            (byte)'=' => order => order == 0,
            (byte)'<' when Next('=') => order => order <= 0,
            (byte)'<' when Next('>') => order => order != 0,
            (byte)'<' => order => order < 0,
            (byte)'>' when Next('=') => order => order >= 0,
            (byte)'>' => order => order > 0,
            _ => null
        };

        if (holds is null) { return left; }
        bool pair = _bytes[_at] == '<' ? Next('=') || Next('>') : _bytes[_at] == '>' && Next('=');
        _at += pair ? 2 : 1;
        BasicValue right = Sum();
        if (left.IsString != right.IsString) { throw new FormatException("Type mismatch."); }
        int compared = left.IsString
            ? left.Text.AsSpan().SequenceCompareTo(right.Text)
            : left.Number.CompareTo(right.Number);

        return Truth(holds(compared));
    }

    private BasicValue Sum()
    {
        BasicValue left = Term();
        while (true)
        {
            if (TakeCharacter('+'))
            {
                BasicValue right = Term();
                if (left.IsString || right.IsString)
                {
                    byte[] joined = [.. Text(left), .. Text(right)];
                    left = joined.Length > MaximumString ? throw new FormatException("String too long.") : BasicValue.Of(joined);
                }
                else
                {
                    left = new(left.Number + right.Number);
                }
            }
            else if (TakeCharacter('-'))
            {
                left = new(Number(left) - Number(Term()));
            }
            else
            {
                return left;
            }
        }
    }

    private BasicValue Term()
    {
        BasicValue left = Power();
        while (true)
        {
            if (TakeCharacter('*'))
            {
                left = new(Number(left) * Number(Power()));
            }
            else if (TakeCharacter('/'))
            {
                double divisor = Number(Power());
                left = divisor == 0 ? throw DivisionByZero() : new(Number(left) / divisor);
            }
            else if (TakeWord("DIV"))
            {
                int divisor = Int(Power());
                left = divisor == 0 ? throw DivisionByZero() : Integer((int)((long)Int(left) / divisor));
            }
            else if (TakeWord("MOD"))
            {
                int divisor = Int(Power());
                left = divisor == 0 ? throw DivisionByZero() : Integer((int)((long)Int(left) % divisor));
            }
            else
            {
                return left;
            }
        }
    }

    // ^ works from left to right: 2^3^2 is 64.
    private BasicValue Power()
    {
        BasicValue left = Factor();
        while (TakeCharacter('^')) { left = new(Math.Pow(Number(left), Number(Factor()))); }
        return left;
    }

    private BasicValue Factor()
    {
        if (++_depth > MaximumDepth) { throw new FormatException("The expression is too complex."); }
        try
        {
            return FactorCore();
        }
        finally
        {
            _depth--;
        }
    }

    private BasicValue FactorCore()
    {
        Skip();
        if (_at >= _bytes.Length) { throw Syntax("the expression ends early"); }
        byte value = _bytes[_at];
        switch (value)
        {
            case (byte)'-':
                _at++;
                return new(-Number(Factor()));
            case (byte)'+':
                _at++;
                return new(Number(Factor()));
            case (byte)'(':
                _at++;
                BasicValue inner = Expression();
                Expect(')');
                return inner;
            case (byte)'"':
                return StringLiteral();
            case (byte)'&':
                return HexLiteral();
        }

        if (char.IsAsciiDigit((char)value) || value == '.') { return NumberLiteral(); }
        if (value >= 0x80)
        {
            if (BbcBasicDialect.Instance.KeywordAt(_bytes, _at, out int length) is not { } word)
            {
                throw Syntax($"'{Rest()}' is not a value");
            }

            _at += length;
            return Keyword(word);
        }

        if (IsNameStart(value)) { return Name(); }
        throw Syntax($"'{Rest()}' is not a value");
    }

    private BasicValue Keyword(string word)
    {
        switch (word)
        {
            case "NOT":
                return Integer(~Int(Factor()));
            case "TRUE":
                return Truth(value: true);
            case "FALSE":
                return Truth(value: false);
            case "PI":
                return new(Math.PI);
            case "PAGE":
                return new(_memory.Read(PageHigh) << 8);
            case "TOP":
                return new(Word(Top));
            case "LOMEM":
                return new(Word(Lomem));
            case "HIMEM":
                return new(Word(Himem));
            case "ERL":
                return new(Word(ErrorLine));
            case "COUNT":
                return new(_memory.Read(Count));
            case "FN":
                return Function();
            case "LEFT$(" or "RIGHT$(" or "MID$(" or "STRING$(" or "INSTR(":
                return Bracketed(word.TrimEnd('('));
        }

        if (!s_unary.Contains(word))
        {
            throw new FormatException($"{word.TrimEnd('(')} cannot be evaluated without running BASIC.");
        }

        if (word == "STR$") { return StringOf(); }
        BasicValue argument = Factor();
        return word switch
        {
            "ABS" => new(Math.Abs(Number(argument))),
            "ACS" => new(Math.Acos(Number(argument))),
            "ASN" => new(Math.Asin(Number(argument))),
            "ATN" => new(Math.Atan(Number(argument))),
            "COS" => new(Math.Cos(Number(argument))),
            "DEG" => new(Number(argument) * 180 / Math.PI),
            "EXP" => new(Math.Exp(Number(argument))),
            "INT" => new(Math.Floor(Number(argument))),
            "LN" => new(Logarithm(Number(argument), Math.Log)),
            "LOG" => new(Logarithm(Number(argument), Math.Log10)),
            "RAD" => new(Number(argument) * Math.PI / 180),
            "SGN" => new(Math.Sign(Number(argument))),
            "SIN" => new(Math.Sin(Number(argument))),
            "SQR" => Number(argument) < 0 ? throw new FormatException("-ve root.") : new(Math.Sqrt(Number(argument))),
            "TAN" => new(Math.Tan(Number(argument))),
            "LEN" => new(Text(argument).Length),
            "ASC" => new(Text(argument) is { Length: > 0 } text ? text[0] : -1),
            "VAL" => new(Value(Text(argument))),
            _ => BasicValue.Of([(byte)Int(argument)])     // CHR$
        };
    }

    // STR$ n, or STR$~ n for hexadecimal: the number as PRINT shows it, without the field width.
    private BasicValue StringOf()
    {
        bool hex = TakeCharacter('~');
        BasicValue argument = Factor();
        string text = hex
            ? Int(argument).ToString("X", System.Globalization.CultureInfo.InvariantCulture)
            : BasicNumbers.Format(Number(argument), 9);

        return BasicValue.Of(Encoding.ASCII.GetBytes(text));
    }

    private BasicValue Bracketed(string word)
    {
        List<BasicValue> arguments = [Expression()];
        while (TakeCharacter(',')) { arguments.Add(Expression()); }
        Expect(')');
        int Whole(int index) => Int(arguments[index]);
        void Needs(int least, int most)
        {
            if (arguments.Count < least || arguments.Count > most)
            {
                throw Syntax($"{word} takes {least} to {most} arguments");
            }
        }

        switch (word)
        {
            case "LEFT$":
                Needs(2, 2);
                return BasicValue.Of([.. Text(arguments[0]).Take(Math.Max(0, Whole(1)))]);
            case "RIGHT$":
                Needs(2, 2);
                byte[] whole = Text(arguments[0]);
                return BasicValue.Of([.. whole.Skip(Math.Max(0, whole.Length - Math.Max(0, Whole(1))))]);
            case "MID$":
                Needs(2, 3);
                int count = arguments.Count > 2 ? Whole(2) : MaximumString;
                return BasicValue.Of([.. Text(arguments[0]).Skip(Math.Max(0, Whole(1) - 1)).Take(Math.Max(0, count))]);
            case "STRING$":
                Needs(2, 2);
                byte[] part = Text(arguments[1]);
                int times = Math.Max(0, Whole(0));
                if ((long)times * part.Length > MaximumString) { throw new FormatException("String too long."); }
                return BasicValue.Of([.. Enumerable.Repeat(part, times).SelectMany(bytes => bytes)]);
            default:
                // INSTR(string, search [, start]): the position from 1, or 0.
                Needs(2, 3);
                byte[] text = Text(arguments[0]);
                byte[] find = Text(arguments[1]);
                int start = Math.Max(1, arguments.Count > 2 ? Whole(2) : 1);
                if (start > text.Length + 1) { return new(0); }
                int found = text.AsSpan(start - 1).IndexOf(find);
                return new(found < 0 ? 0 : found + start);
        }
    }

    // FNname or FNname(argument): a one-line DEF FN's body, with its parameter bound to the argument.
    private BasicValue Function()
    {
        string name = Letters();
        BasicValue? argument = null;
        if (TakeCharacter('('))
        {
            argument = Expression();
            Expect(')');
        }

        if (_functions?.Invoke(name) is not { } function)
        {
            throw new FormatException($"FN{name} cannot be evaluated without running BASIC.");
        }

        if (argument is null) { return Evaluate(function.Body).Value; }
        string parameter = function.Parameter;
        bool had = _bound.TryGetValue(parameter, out BasicValue previous);
        _bound[parameter] = argument.Value;
        try
        {
            return Evaluate(function.Body).Value;
        }
        finally
        {
            if (had) { _bound[parameter] = previous; }
            else { _bound.Remove(parameter); }
        }
    }

    // A variable or an array element: a name, a suffix, and subscripts in brackets.
    private BasicValue Name()
    {
        string name = Letters();
        if (_at < _bytes.Length && _bytes[_at] is (byte)'%' or (byte)'$') { name += (char)_bytes[_at++]; }
        if (_at < _bytes.Length && _bytes[_at] == '(')
        {
            _at++;
            List<int> subscripts = [Int(Expression())];
            while (TakeCharacter(',')) { subscripts.Add(Int(Expression())); }
            Expect(')');
            if (_variables.FindArray(name) is not { } array) { throw new FormatException($"Array {name}( not found."); }
            try
            {
                return _variables.Read(array.Kind, array.ElementAddress(subscripts));
            }
            catch (ArgumentOutOfRangeException exception)
            {
                throw new FormatException(exception.Message.Split(" (")[0], exception);
            }
        }

        if (_bound.TryGetValue(name, out BasicValue bound)) { return bound; }
        return _variables.Find(name) is { } variable
            ? _variables.Read(variable.Kind, variable.ValueAddress)
            : name.EndsWith('$') ? BasicValue.Of([]) : new(0);
    }

    private string Letters()
    {
        int start = _at;
        if (_at < _bytes.Length && _bytes[_at] == '@') { _at++; }
        while (_at < _bytes.Length && BbcBasicDialect.IsNameCharacter(_bytes[_at])) { _at++; }
        return Encoding.ASCII.GetString(_bytes, start, _at - start);
    }

    // A name starts with a letter, _ or £, or is @%.
    private bool IsNameStart(byte value) =>
        (BbcBasicDialect.IsNameCharacter(value) && !char.IsAsciiDigit((char)value))
            || (value == '@' && _at + 1 < _bytes.Length && _bytes[_at + 1] == '%');

    private BasicValue StringLiteral()
    {
        // Two quotes inside a string stand for one.
        List<byte> text = [];
        _at++;
        while (_at < _bytes.Length)
        {
            byte character = _bytes[_at++];
            if (character != '"') { text.Add(character); }
            else if (_at < _bytes.Length && _bytes[_at] == '"') { text.Add(character); _at++; }
            else { return BasicValue.Of([.. text]); }
        }

        throw new FormatException("Missing \".");
    }

    private BasicValue HexLiteral()
    {
        _at++;
        long value = 0;
        int start = _at;
        while (_at < _bytes.Length && char.IsAsciiHexDigitUpper((char)_bytes[_at]))
        {
            int digit = _bytes[_at] <= '9' ? _bytes[_at] - '0' : _bytes[_at] - 'A' + 10;
            value = ((value << 4) | (uint)digit) & 0xFFFFFFFF;
            _at++;
        }

        return _at == start ? throw new FormatException("Bad HEX.") : Integer(unchecked((int)value));
    }

    private BasicValue NumberLiteral()
    {
        int start = _at;
        while (_at < _bytes.Length && (char.IsAsciiDigit((char)_bytes[_at]) || _bytes[_at] == '.')) { _at++; }
        if (_at < _bytes.Length && _bytes[_at] == 'E')
        {
            int at = _at + 1;
            if (at < _bytes.Length && _bytes[at] is (byte)'+' or (byte)'-') { at++; }
            if (at < _bytes.Length && char.IsAsciiDigit((char)_bytes[at]))
            {
                _at = at;
                while (_at < _bytes.Length && char.IsAsciiDigit((char)_bytes[_at])) { _at++; }
            }
        }

        string text = Encoding.ASCII.GetString(_bytes, start, _at - start);
        return BasicNumbers.TryParse(text, out double number) ? new(number) : throw Syntax($"'{text}' is not a number");
    }

    // VAL: the number at the start of the string, or 0.
    private static double Value(byte[] text)
    {
        string trimmed = Encoding.ASCII.GetString(text).TrimStart(' ');
        int end = 0;
        if (end < trimmed.Length && trimmed[end] is '+' or '-') { end++; }
        while (end < trimmed.Length && (char.IsAsciiDigit(trimmed[end]) || trimmed[end] == '.')) { end++; }
        if (end < trimmed.Length && trimmed[end] == 'E')
        {
            int at = end + 1;
            if (at < trimmed.Length && trimmed[at] is '+' or '-') { at++; }
            if (at < trimmed.Length && char.IsAsciiDigit(trimmed[at]))
            {
                end = at;
                while (end < trimmed.Length && char.IsAsciiDigit(trimmed[end])) { end++; }
            }
        }

        return BasicNumbers.TryParse(trimmed[..end], out double number) ? number : 0;
    }

    private static double Logarithm(double value, Func<double, double> logarithm) =>
        value <= 0 ? throw new FormatException("Log range.") : logarithm(value);

    private static BasicValue Truth(bool value) => new(value ? -1 : 0);

    private static BasicValue Integer(int value) => new(value);

    private static double Number(BasicValue value) =>
        value.IsString ? throw new FormatException("Type mismatch: a string where a number is needed.") : value.Number;

    private static byte[] Text(BasicValue value) =>
        value.Text ?? throw new FormatException("Type mismatch: a number where a string is needed.");

    // A number as a 32-bit integer, truncated, as BASIC's integer operators take it.
    private static int Int(BasicValue value)
    {
        double truncated = Math.Truncate(Number(value));
        return truncated is < int.MinValue or > int.MaxValue ? throw new FormatException("Too big.") : (int)truncated;
    }

    private static FormatException DivisionByZero() => new("Division by zero.");

    private int Word(int address) => _memory.Read(address) | (_memory.Read(address + 1) << 8);

    private bool Next(char character) => _at + 1 < _bytes.Length && _bytes[_at + 1] == character;

    private bool TakeCharacter(char character)
    {
        Skip();
        if (_at >= _bytes.Length || _bytes[_at] != character) { return false; }
        _at++;
        return true;
    }

    private bool TakeWord(string word)
    {
        Skip();
        if (_at >= _bytes.Length || _bytes[_at] < 0x80) { return false; }
        if (BbcBasicDialect.Instance.KeywordAt(_bytes, _at, out int length) != word) { return false; }
        _at += length;
        return true;
    }

    private void Expect(char character)
    {
        if (!TakeCharacter(character)) { throw Syntax($"'{character}' is missing"); }
    }

    private void Skip()
    {
        while (_at < _bytes.Length && _bytes[_at] == ' ') { _at++; }
    }

    private string Rest() => BbcBasicDialect.Instance.Detokenize(_bytes.AsSpan(_at));

    private static FormatException Syntax(string why) => new($"Syntax error: {why}.");
}
