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
///  <para>
///   Integers match BASIC II exactly, quirks included: <c>&amp;80000000 DIV</c> or <c>MOD</c> anything is 0. Reals are
///   held as BASIC II holds them, a 32-bit mantissa rounded as <c>ROUND_FP_A</c> rounds it, and addition, subtraction
///   and division come out as the ROM's do. Multiplication, and the whole powers <c>^</c> makes of it, follow
///   <c>MULTIPLY_FP_A</c> bit for bit, partial products truncated as the ROM's are. <c>SIN</c>, <c>COS</c>, <c>TAN</c>, <c>ATN</c>, <c>LN</c>, <c>LOG</c>, <c>EXP</c>, and
///   <c>^</c> with a fraction or a power of 64 or more, use the host's functions, not the ROM's series: their results
///   can differ in the last bits, more for a large angle, and a result at the edge of the range can be a value in one
///   and "Too big" or 0 in the other. A condition comparing such a real for equality with one the program computed
///   may therefore disagree with BASIC.
///  </para>
/// </remarks>
internal sealed class BbcBasicExpression
{
    private const int MaximumDepth = 32;
    private const int MaximumString = 255;

    // BASIC II's reals: an 8-bit exponent around 128 and a 32-bit mantissa, so from 2^-129 (exponent 0, the mantissa
    // a half) to just under 2^127.
    private const double LargestReal = 1.7014118346046923E38;
    private const double SmallestReal = 1.4693679385278594E-39;

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

            // No function may leave an infinity or NaN, which a breakpoint condition would take as true.
            if (!value.IsString && !double.IsFinite(value.Number)) { throw new FormatException("Too big."); }
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
                    left = IsInteger(left) && IsInteger(right)
                        ? Integer(unchecked(Int(left) + Int(right)))
                        : Real(left.Number + right.Number);
                }
            }
            else if (TakeCharacter('-'))
            {
                BasicValue right = Term();
                left = IsInteger(left) && IsInteger(right)
                    ? Integer(unchecked(Int(left) - Int(right)))
                    : Real(Number(left) - Number(right));
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
                BasicValue right = Power();

                // BASIC multiplies integers as integers only when both fit in 16 bits; otherwise in reals.
                bool small = IsShort(left) && IsShort(right);
                left = small ? Integer(Int(left) * Int(right)) : Real(MultiplyReals(Number(Real(Number(left))), Number(Real(Number(right)))));
            }
            else if (TakeCharacter('/'))
            {
                double divisor = Number(Power());
                left = divisor == 0 ? throw DivisionByZero() : Real(Number(left) / divisor);
            }
            else if (TakeWord("DIV"))
            {
                int divisor = Int(Power());
                left = divisor == 0 ? throw DivisionByZero() : Integer(Divide(Int(left), divisor, remainder: false));
            }
            else if (TakeWord("MOD"))
            {
                int divisor = Int(Power());
                left = divisor == 0 ? throw DivisionByZero() : Integer(Divide(Int(left), divisor, remainder: true));
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
        while (TakeCharacter('^'))
        {
            left = Raise(Number(left), Number(Factor()));
        }

        return left;
    }

    // An angle for SIN, COS and TAN, which REDUCE_ANGLE refuses from 2^23 up in size.
    private static double Angle(BasicValue argument) => Number(argument) is var angle && Math.Abs(angle) < 8388608
        ? angle
        : throw new FormatException("Accuracy lost.");

    /// <summary>
    ///  Multiplies two reals as BASIC II's <c>MULTIPLY_FP_A</c> does, bit for bit.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   For each of the multiplier's 32 mantissa bits from the top, the other mantissa, with a rounding byte below it,
    ///   is halved, losing what falls off, and added when the bit is set; the 40 bits are then normalised and rounded
    ///   as <c>ROUND_FP_A</c> rounds them. So a product can differ from the exact one in its last bit, as the ROM's
    ///   does.
    ///  </para>
    /// </remarks>
    /// <param name="shifted">The real whose mantissa is halved and added, already a BASIC II real.</param>
    /// <param name="multiplier">The real whose mantissa bits choose the additions, already a BASIC II real.</param>
    /// <returns>The product, before any range check.</returns>
    internal static double MultiplyReals(double shifted, double multiplier)
    {
        if (shifted == 0 || multiplier == 0 || !double.IsFinite(shifted) || !double.IsFinite(multiplier))
        {
            return shifted * multiplier;
        }

        int shiftedPower = Math.ILogB(shifted);
        int multiplierPower = Math.ILogB(multiplier);
        ulong b = (ulong)Math.ScaleB(Math.Abs(shifted), 31 - shiftedPower) << 8;
        ulong a = (ulong)Math.ScaleB(Math.Abs(multiplier), 31 - multiplierPower);
        ulong sum = 0;
        for (int bit = 31; bit >= 0; bit--)
        {
            b >>= 1;
            if (((a >> bit) & 1) != 0) { sum += b; }
        }

        // The 40 bits are the product times 2^-24 of the mantissas': normalised so the top is bit 39, then rounded.
        int power = shiftedPower + multiplierPower - 38;
        while (sum < (1UL << 39))
        {
            sum <<= 1;
            power--;
        }

        ulong mantissa = sum >> 8;
        ulong rounding = sum & 0xFF;
        if (rounding > 0x80)
        {
            mantissa++;
        }
        else if (rounding == 0x80)
        {
            mantissa |= 1;
        }

        double product = Math.ScaleB(mantissa, power + 8);
        return (shifted < 0) != (multiplier < 0) ? -product : product;
    }

    // DIV or MOD as DIVIDE_INTEGERS works them out: &80000000's one set bit is lost with its leading zeros, so it gives
    // 0 for both with any divisor, where everything else divides as two's complement.
    private static int Divide(int dividend, int divisor, bool remainder) => dividend == int.MinValue
        ? 0
        : (int)(remainder ? (long)dividend % divisor : (long)dividend / divisor);

    // x^y as POWER_OPERATOR works it out. A y of 64 or more in size is all fraction; any other is split into the whole
    // number nearest it, n, and what is left, f, of at most a half. x^n is repeated multiplication (by the reciprocal
    // for a negative n), and any fraction is EXP(LN x * f), so x must then be above zero or it is "Log range": 0^0.5
    // and (-1)^64 are, where 0^2 and (-2)^3 are not.
    private static BasicValue Raise(double x, double y)
    {
        double whole = Math.Abs(y) >= 64 ? 0 : Math.Round(y, MidpointRounding.AwayFromZero);
        double fraction = y - whole;
        double power = 1;
        if (whole < 0 && x == 0) { throw new FormatException("Division by zero."); }
        double factor = whole < 0 ? Real(1 / x).Number : x;
        // RAISE_TO_POWER multiplies its running result, FPA, by x each time: x is the one shifted.
        for (int step = 0; step < Math.Abs(whole); step++) { power = Real(MultiplyReals(factor, power)).Number; }

        if (fraction == 0) { return Real(power); }
        if (x <= 0) { throw new FormatException("Log range."); }
        double exponent = Math.Log(x) * fraction;
        if (exponent >= 89.5) { throw new FormatException("Exp range."); }
        return Real(MultiplyReals(power, Real(exponent <= -89.5 ? 0 : Math.Exp(exponent)).Number));
    }

    private static bool IsShort(BasicValue value) => IsInteger(value) && Int(value) is >= short.MinValue and <= short.MaxValue;

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
                BasicValue negated = Factor();
                return IsInteger(negated) ? Integer(unchecked(-Int(negated))) : new(-Number(negated));
            case (byte)'+':
                _at++;
                BasicValue plus = Factor();
                Number(plus);
                return plus;
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

            // TOP has no token of its own: the tokeniser makes it TO, then P.
            if (word == "TO" && _at < _bytes.Length && _bytes[_at] == 'P')
            {
                _at++;
                word = "TOP";
            }

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
                return Real(Math.PI);                   // the ROM's packed &490FDAA2 mantissa, as P=PI stores it
            case "PAGE":
                return Integer(_memory.Read(PageHigh) << 8);
            case "TOP":
                return Integer(Word(Top));
            case "LOMEM":
                return Integer(Word(Lomem));
            case "HIMEM":
                return Integer(Word(Himem));
            case "ERL":
                return Integer(Word(ErrorLine));
            case "COUNT":
                return Integer(_memory.Read(Count));
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
            "ABS" => IsInteger(argument)
                ? Integer(Int(argument) < 0 ? unchecked(-Int(argument)) : Int(argument))
                : Real(Math.Abs(Number(argument))),
            "ACS" => Real(Math.Acos(Unit(Number(argument)))),
            "ASN" => Real(Math.Asin(Unit(Number(argument)))),
            "ATN" => Real(Math.Atan(Number(argument))),
            "COS" => Real(Math.Cos(Angle(argument))),
            "DEG" => Real(Number(argument) * 180 / Math.PI),
            "EXP" => Number(argument) switch
            {
                >= 89.5 => throw new FormatException("Exp range."),
                <= -89.5 => new(0),
                double power => Real(Math.Exp(power))
            },
            "INT" => IsInteger(argument)
                ? Integer(Int(argument))
                : Math.Abs(Number(argument)) < TwoToThe31
                    ? Integer((int)Math.Floor(Number(argument)))
                    : throw new FormatException("Too big."),
            "LN" => Real(Logarithm(Number(argument), Math.Log)),
            "LOG" => Real(Logarithm(Number(argument), Math.Log10)),
            "RAD" => Real(Number(argument) * Math.PI / 180),
            "SGN" => Integer(Math.Sign(Number(argument))),
            "SIN" => Real(Math.Sin(Angle(argument))),
            "SQR" => Number(argument) < 0 ? throw new FormatException("-ve root.") : Real(Math.Sqrt(Number(argument))),
            "TAN" => Real(Math.Tan(Angle(argument))),
            "LEN" => Integer(Text(argument).Length),
            "ASC" => Integer(Text(argument) is { Length: > 0 } text ? text[0] : -1),
            "VAL" => Value(Text(argument)),
            _ => BasicValue.Of([(byte)Int(argument)])     // CHR$
        };
    }

    // STR$ n, or STR$~ n for hexadecimal: the number as PRINT shows it, without the field width.
    private BasicValue StringOf()
    {
        bool hex = TakeCharacter('~');
        BasicValue argument = Factor();

        // With @%'s top byte set, STR$ takes @%'s format and digits, which a watch does not reproduce: it says so rather
        // than give the general format the program would not. STR$~ is hexadecimal either way.
        if (!hex && _memory.Read(BbcBasicDialect.ResidentIntegers + 3) != 0)
        {
            throw new FormatException("STR$ uses @%'s format here, as @%'s top byte is set, which a watch does not show.");
        }

        string text = hex
            ? Int(argument).ToString("X", System.Globalization.CultureInfo.InvariantCulture)
            : Format(Number(argument));

        return BasicValue.Of(Encoding.ASCII.GetBytes(text));
    }

    private BasicValue Bracketed(string word)
    {
        List<BasicValue> arguments = [Expression()];
        while (TakeCharacter(',')) { arguments.Add(Expression()); }
        Expect(')');
        // BASIC takes only the low byte of these integers: LEFT$("ABC",256) is empty.
        int Whole(int index) => Int(arguments[index]) & 0xFF;
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
                if (start > text.Length + 1) { return Integer(0); }
                int found = text.AsSpan(start - 1).IndexOf(find);
                return Integer(found < 0 ? 0 : found + start);
        }
    }

    // FNname or FNname(argument): a one-line DEF FN's body, with its parameter bound to the argument.
    private BasicValue Function()
    {
        string name = RoutineName();
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

        // The call's argument must match the definition's parameter, as BASIC's "Arguments" error has it.
        string parameter = function.Parameter;
        if (argument is null != (parameter.Length == 0)) { throw new FormatException("Arguments."); }
        if (argument is not { } given) { return Evaluate(function.Body).Value; }

        // The argument takes the parameter's type: a string for $, an integer, truncated, for %, else a real.
        BasicValue value;
        if (parameter.EndsWith('$'))
        {
            value = given.IsString ? given : throw new FormatException("Type mismatch.");
        }
        else
        {
            value = parameter.EndsWith('%') ? Integer(Int(given)) : Real(Number(given));
        }

        bool had = _bound.TryGetValue(parameter, out BasicValue previous);
        _bound[parameter] = value;
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
                return Typed(array.Kind, _variables.Read(array.Kind, array.ElementAddress(subscripts)));
            }
            catch (ArgumentOutOfRangeException exception)
            {
                throw new FormatException(exception.Message.Split(" (")[0], exception);
            }
        }

        if (_bound.TryGetValue(name, out BasicValue bound)) { return bound; }
        return _variables.Find(name) is { } variable
            ? Typed(variable.Kind, _variables.Read(variable.Kind, variable.ValueAddress))
            : throw new FormatException($"No such variable: {name}.");
    }

    private static BasicValue Typed(BasicVariableKind kind, BasicValue value) =>
        kind == BasicVariableKind.Integer ? Integer((int)value.Number) : value;

    // A PROC or FN name, as SCAN_VARIABLE_NAME reads one after the word: name characters, digits and @, anywhere.
    private string RoutineName()
    {
        int start = _at;
        while (_at < _bytes.Length && (BbcBasicDialect.IsNameCharacter(_bytes[_at]) || _bytes[_at] == '@')) { _at++; }
        return Encoding.ASCII.GetString(_bytes, start, _at - start);
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
        string text = Encoding.ASCII.GetString(_bytes, start, _at - start);
        if (_at < _bytes.Length && _bytes[_at] == 'E')
        {
            // READ_EXPONENT takes the E and a sign whatever follows, then at most two digits: none is an exponent of 0,
            // so 1E and 1E- are 1, and a third digit is left over.
            int sign = _at + 1;
            int at = sign < _bytes.Length && _bytes[sign] is (byte)'+' or (byte)'-' ? sign + 1 : sign;
            _at = at;
            while (_at < _bytes.Length && _at - at < 2 && char.IsAsciiDigit((char)_bytes[_at])) { _at++; }
            if (_at > at) { text += Encoding.ASCII.GetString(_bytes, start + text.Length, _at - start - text.Length); }
        }

        return Classify(text, negative: false) ?? throw Syntax($"'{text}' is not a number");
    }

    // A number BASIC has read, as READ_NUMBER types it: an integer when it has no decimal point, its exponent is zero
    // (so 1E0 is one) and its magnitude fits 31 bits; otherwise a real. The sign goes on after, so -2147483648 is real.
    private static BasicValue? Classify(string magnitude, bool negative)
    {
        // BASIC takes a point with no digits around it, as in . (real zero) or 5., which the host's parser does not.
        string digits = magnitude.StartsWith('.') ? "0" + magnitude : magnitude;
        int point = digits.IndexOf('.', StringComparison.Ordinal);
        if (point >= 0 && (point + 1 == digits.Length || !char.IsAsciiDigit(digits[point + 1])))
        {
            digits = digits.Insert(point + 1, "0");
        }

        if (!BasicNumbers.TryParse(digits, out double number)) { return null; }
        int mark = magnitude.IndexOf('E', StringComparison.Ordinal);
        bool zeroScale = mark < 0 || int.TryParse(magnitude[(mark + 1)..], System.Globalization.CultureInfo.InvariantCulture, out int power) && power == 0;
        bool integer = !magnitude.Contains('.') && zeroScale && number <= int.MaxValue;
        return integer ? Integer(negative ? -(int)number : (int)number) : Real(negative ? -number : number);
    }

    // VAL: the number at the start of the string, or 0, read as BASIC reads one: spaces, a sign, spaces, the digits
    // with one point, and an exponent, typed as Classify says.
    private static BasicValue Value(byte[] text)
    {
        string trimmed = Encoding.ASCII.GetString(text).TrimStart(' ');
        bool negative = false;
        if (trimmed.Length != 0 && trimmed[0] is '+' or '-')
        {
            negative = trimmed[0] == '-';
            trimmed = trimmed[1..].TrimStart(' ');
        }

        int end = 0;
        bool point = false;
        while (end < trimmed.Length && (char.IsAsciiDigit(trimmed[end]) || (trimmed[end] == '.' && !point)))
        {
            point |= trimmed[end] == '.';
            end++;
        }

        if (end < trimmed.Length && trimmed[end] == 'E')
        {
            int at = end + 1;
            if (at < trimmed.Length && trimmed[at] is '+' or '-') { at++; }
            if (at < trimmed.Length && char.IsAsciiDigit(trimmed[at]))
            {
                end = at;
                while (end < trimmed.Length && end - at < 2 && char.IsAsciiDigit(trimmed[end])) { end++; }
            }
        }

        return Classify(trimmed[..end], negative) ?? Integer(0);
    }

    /// <summary>
    ///  Writes a number in BASIC II's general format, as STR$ and PRINT with @%'s default show it: up to ten
    ///  significant digits without trailing zeros, E notation when the power of ten is ten or more or below -1, and a
    ///  leading zero from 0.1 up to 1.
    /// </summary>
    /// <param name="value">The number.</param>
    /// <returns>The text, such as <c>1234567890</c>, <c>0.5</c>, <c>1.5E10</c> or <c>1E-2</c>.</returns>
    internal static string Format(double value)
    {
        const int Digits = 10;
        if (!double.IsFinite(value)) { throw new FormatException("Too big."); }
        if (value == 0) { return "0"; }

        // The digits, rounded to ten, and the power of ten of the first.
        string scientific = Math.Abs(value).ToString("E" + (Digits - 1), System.Globalization.CultureInfo.InvariantCulture);
        int mark = scientific.IndexOf('E');
        string digits = scientific[..mark].Replace(".", "", StringComparison.Ordinal).TrimEnd('0');
        int power = int.Parse(scientific[(mark + 1)..], System.Globalization.CultureInfo.InvariantCulture);
        string sign = value < 0 ? "-" : "";
        if (power >= Digits || power < -1)
        {
            string fraction = digits.Length > 1 ? "." + digits[1..] : "";
            return $"{sign}{digits[0]}{fraction}E{power}";
        }

        if (power == -1) { return $"{sign}0.{digits}"; }
        return digits.Length <= power + 1
            ? sign + digits.PadRight(power + 1, '0')
            : $"{sign}{digits[..(power + 1)]}.{digits[(power + 1)..]}";
    }

    // ACS and ASN take -1 to 1, and BASIC says "-ve root" for anything else.
    private static double Unit(double value) => value is >= -1 and <= 1 ? value : throw new FormatException("-ve root.");

    private static double Logarithm(double value, Func<double, double> logarithm) =>
        value <= 0 ? throw new FormatException("Log range.") : logarithm(value);

    // A real as BASIC II holds one, in five bytes: past about 1.7E38 it is "Too big", and below about 1.5E-39, where
    // the exponent would go below 0, it is 0.
    // ROUND_FP_A checks the exponent again after rounding, so 1.7014118345E38, which rounds up to 2^127, is too big.
    private static BasicValue Real(double value) => value switch
    {
        double.NaN => throw new FormatException("Log range."),
        >= LargestReal or <= -LargestReal => throw new FormatException("Too big."),
        > -SmallestReal and < SmallestReal => new(0),
        _ => RoundMantissa(value) is var rounded && Math.Abs(rounded) < LargestReal
            ? new(rounded)
            : throw new FormatException("Too big.")
    };

    /// <summary>
    ///  Rounds a real to BASIC II's 32-bit mantissa, as ROUND_FP_A rounds it: 1E10+1 is 1E10.
    /// </summary>
    /// <param name="value">The real.</param>
    /// <returns>The rounded real.</returns>
    /// <remarks>
    ///  <para>
    ///   The rounding byte is the eight bits after the mantissa: above &amp;80 rounds up, &amp;80 itself sets the
    ///   mantissa's lowest bit, so an odd mantissa stays (2147483649+0.5 is 2147483649), and below &amp;80 truncates.
    ///  </para>
    /// </remarks>
    internal static double RoundMantissa(double value)
    {
        if (value == 0) { return 0; }

        // The value itself is scaled, not by a factor of 2^(31 - exponent), which overflows for a tiny one.
        int power = Math.ILogB(value);
        double scaled = Math.ScaleB(Math.Abs(value), 31 - power);
        double mantissa = Math.Floor(scaled);
        double rounding = Math.Floor((scaled - mantissa) * 256);
        if (rounding > 0x80)
        {
            mantissa++;
        }
        else if (rounding == 0x80 && mantissa % 2 == 0)
        {
            mantissa++;
        }

        return Math.CopySign(Math.ScaleB(mantissa, power - 31), value);
    }

    private static BasicValue Truth(bool value) => Integer(value ? -1 : 0);

    // An integer value, which BASIC keeps apart from a real one: Long holds it.
    private static BasicValue Integer(int value) => BasicValue.OfLong(value);

    private static bool IsInteger(BasicValue value) => value.Long is not null;

    private static double Number(BasicValue value) =>
        value.IsString ? throw new FormatException("Type mismatch: a string where a number is needed.") : value.Number;

    private static byte[] Text(BasicValue value) =>
        value.Text ?? throw new FormatException("Type mismatch: a number where a string is needed.");

    // A number as a 32-bit integer, as BASIC's integer operators take it: an integer as it is, and a real truncated,
    // which REAL_TO_INTEGER refuses from 2^31 up in size, -2^31 included, though the integer &80000000 is fine.
    private static int Int(BasicValue value)
    {
        if (value.Long is long whole)
        {
            return whole is >= int.MinValue and <= int.MaxValue ? (int)whole : throw new FormatException("Too big.");
        }

        // Written so that NaN, which no comparison holds for, is too big rather than cast.
        double real = Number(value);
        return Math.Abs(real) < TwoToThe31 ? (int)Math.Truncate(real) : throw new FormatException("Too big.");
    }

    /// <summary>
    ///  2^31: the size from which a real is too big to be made an integer, -2^31 included.
    /// </summary>
    internal const double TwoToThe31 = 2147483648.0;

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
