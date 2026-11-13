// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text;
using System.Text.RegularExpressions;

namespace Retrocore.Basic;

/// <summary>
///  Evaluates BASIC expressions against a machine's variables without running BASIC, so nothing changes: no RND,
///  no I/O, nothing that moves strings or makes variables.
/// </summary>
/// <remarks>
///  <para>
///   The expression is tokenized as the ROM would tokenize it, so reserved words are found where BASIC finds them;
///   a bare name such as <c>SCORE</c> is the variable it names, as a debugger's hover and watch mean it. Operators
///   have BASIC's precedence. True is 1 in AppleSoft and -1 in Level II, whose AND, OR and NOT work on the bits of
///   integers. Variables BASIC has not made yet are zero or empty, as BASIC reads them.
///  </para>
/// </remarks>
public sealed partial class BasicEvaluator
{
    private const int MaximumDepth = 32;
    private const string EmptyAscii = "?ILLEGAL QUANTITY ERROR: ASC of an empty string.";
    private const int AutomaticDimension = 11;

    private static readonly HashSet<string> s_refused =
    [
        "RND", "FRE", "POS", "USR", "INP", "INKEY$", "TIME$", "POINT", "PDL", "SCRN(", "TAB(", "SPC(", "VARPTR", "MEM",
        "ERL", "ERR", "CVI", "CVS", "CVD", "EOF", "LOC", "LOF", "MKI$", "MKS$", "MKD$", "USING"
    ];

    private readonly BasicDialect _dialect;
    private readonly IBasicMemory _memory;
    private readonly BasicVariables _variables;
    private readonly Func<string, (string Parameter, string Body)?>? _functions;
    private readonly Dictionary<string, BasicValue> _bound = new(StringComparer.Ordinal);
    private byte[] _bytes = [];
    private int _at;
    private int _depth;

    /// <summary>
    ///  Creates an evaluator.
    /// </summary>
    /// <param name="dialect">The interpreter.</param>
    /// <param name="memory">The memory.</param>
    /// <param name="functions">
    ///  Finds a DEF FN function's parameter and body by name, for FN calls; null for none.
    /// </param>
    public BasicEvaluator(
        BasicDialect dialect,
        IBasicMemory memory,
        Func<string, (string Parameter, string Body)?>? functions = null)
    {
        ArgumentNullException.ThrowIfNull(dialect);
        ArgumentNullException.ThrowIfNull(memory);
        _dialect = dialect;
        _memory = memory;
        _variables = new(dialect, memory);
        _functions = functions;
    }

    private bool LevelTwo => _dialect == BasicDialect.Level2;

    // Level II and Color BASIC take true as -1, and AND, OR and NOT bit by bit on 16-bit integers.
    private bool Bitwise => LevelTwo || _dialect is ColorBasicDialect;

    private double True => Bitwise ? -1 : 1;

    /// <summary>
    ///  Evaluates an expression.
    /// </summary>
    /// <param name="expression">The expression, as BASIC would take it.</param>
    /// <returns>The result.</returns>
    /// <exception cref="FormatException">
    ///  The expression is not BASIC, or uses what cannot run without BASIC.
    /// </exception>
    public BasicResult Evaluate(string expression)
    {
        ArgumentNullException.ThrowIfNull(expression);
        if (_dialect == BasicDialect.Integer)
        {
            return new IntegerBasicExpression(_variables, _memory).Evaluate(expression);
        }

        if (_dialect == BasicDialect.BusinessBasic)
        {
            return new BusinessBasicExpression(_variables).Evaluate(expression);
        }

        if (BareName().IsMatch(expression.Trim())) { return Variable(expression.Trim(), subscripts: null); }
        byte[] saved = _bytes;
        int savedAt = _at;
        try
        {
            _bytes = _dialect.Tokenize(expression);
            _at = 0;
            BasicResult result = Or();
            Skip();
            if (_at < _bytes.Length) { throw Syntax($"'{Rest()}' is left over"); }
            return result;
        }
        finally
        {
            _bytes = saved;
            _at = savedAt;
        }
    }

    /// <summary>
    ///  Tests whether a result is true, as IF tests it: not zero, or for a string, not empty.
    /// </summary>
    /// <param name="result">The result.</param>
    /// <returns>Whether it is true.</returns>
    public static bool IsTrue(BasicResult result) =>
        result.Value.IsString ? result.Value.Text?.Length > 0 : result.Value.Number != 0;

    /// <summary>
    ///  Writes a result as PRINT would, without a positive number's leading space; a string is quoted.
    /// </summary>
    /// <param name="result">The result.</param>
    /// <returns>The text.</returns>
    public string Format(BasicResult result)
    {
        if (_dialect == BasicDialect.Integer) { return IntegerBasicExpression.Format(result.Value); }
        if (_dialect == BasicDialect.BusinessBasic) { return BusinessBasicExpression.Format(result.Value); }
        if (result.Value.Text is { } text)
        {
            StringBuilder builder = new("\"");
            foreach (byte value in text) { BasicText.AppendCharacter(builder, value); }
            return builder.Append('"').ToString();
        }

        return BasicNumbers.Format(result.Value.Number, LevelTwo ? (result.Double ? 16 : 6) : 9);
    }

    private BasicResult Or()
    {
        BasicResult left = And();
        while (Take("OR")) { left = Logic(left, And(), (a, b) => a | b, (a, b) => a || b); }
        return left;
    }

    private BasicResult And()
    {
        BasicResult left = Not();
        while (Take("AND")) { left = Logic(left, Not(), (a, b) => a & b, (a, b) => a && b); }
        return left;
    }

    private BasicResult Not()
    {
        if (!Take("NOT")) { return Relation(); }
        double value = Number(Not());
        return new(new(Bitwise ? ~ToInteger(value) : (value == 0 ? 1 : 0)));
    }

    private BasicResult Relation()
    {
        BasicResult left = Additive();
        while (true)
        {
            bool less = false;
            bool equal = false;
            bool greater = false;
            while (true)
            {
                if (Take("<")) { less = true; }
                else if (Take("=")) { equal = true; }
                else if (Take(">")) { greater = true; }
                else { break; }
            }

            if (!less && !equal && !greater) { return left; }
            BasicResult right = Additive();
            int order = Compare(left, right);
            bool holds = (less && order < 0) || (equal && order == 0) || (greater && order > 0);
            left = new(new(holds ? True : 0));
        }
    }

    private BasicResult Additive()
    {
        BasicResult left = Term();
        while (true)
        {
            if (Take("+"))
            {
                BasicResult right = Term();
                left = left.Value.IsString || right.Value.IsString
                    ? new(BasicValue.Of([.. Text(left), .. Text(right)]))
                    : new(new(Number(left) + Number(right)), left.Double || right.Double);
            }
            else if (Take("-"))
            {
                BasicResult right = Term();
                left = new(new(Number(left) - Number(right)), left.Double || right.Double);
            }
            else
            {
                return left;
            }
        }
    }

    private BasicResult Term()
    {
        BasicResult left = Unary();
        while (true)
        {
            if (Take("*"))
            {
                BasicResult right = Unary();
                left = new(new(Number(left) * Number(right)), left.Double || right.Double);
            }
            else if (Take("/"))
            {
                BasicResult right = Unary();
                double divisor = Number(right);
                if (divisor == 0) { throw new FormatException(Bitwise ? "?/0 ERROR." : "?DIVISION BY ZERO ERROR."); }
                left = new(new(Number(left) / divisor), left.Double || right.Double);
            }
            else
            {
                return left;
            }
        }
    }

    private BasicResult Unary()
    {
        if (Take("-"))
        {
            BasicResult value = Unary();
            return new(new(-Number(value)), value.Double);
        }

        return Take("+") ? Unary() : Power();
    }

    private BasicResult Power()
    {
        BasicResult left = Primary();
        while (Take(LevelTwo ? "[" : "^"))
        {
            BasicResult right = Unary();
            left = new(new(Math.Pow(Number(left), Number(right))), left.Double || right.Double);
        }

        return left;
    }

    private BasicResult Primary()
    {
        Skip();
        if (_at >= _bytes.Length) { throw Syntax("the expression ends early"); }
        byte value = _bytes[_at];
        if (value == '(')
        {
            _at++;
            BasicResult inner = Or();
            Expect(')');
            return inner;
        }

        if (value == '"') { return StringLiteral(); }
        if (char.IsAsciiDigit((char)value) || value == '.') { return NumberLiteral(); }
        if (_dialect.KeywordAt(_bytes, _at, out int length) is { } word)
        {
            _at += length;
            return word == "FN" ? Function() : Call(word);
        }

        if (char.IsAsciiLetter((char)value)) { return Name(); }
        throw Syntax($"'{Rest()}' is not a value");
    }

    private BasicResult StringLiteral()
    {
        _at++;
        int end = Array.IndexOf(_bytes, (byte)'"', _at);
        if (end < 0) { end = _bytes.Length; }
        byte[] text = _bytes[_at..end];
        _at = Math.Min(end + 1, _bytes.Length);
        return new(BasicValue.Of(text));
    }

    private BasicResult NumberLiteral()
    {
        StringBuilder text = new();
        while (_at < _bytes.Length && (char.IsAsciiDigit((char)_bytes[_at]) || _bytes[_at] is (byte)'.' or (byte)' '))
        {
            text.Append((char)_bytes[_at++]);
        }

        bool precise = false;
        if (_at < _bytes.Length && _bytes[_at] is (byte)'E' or (byte)'D')
        {
            precise = _bytes[_at] == 'D';
            int at = _at + 1;
            string sign = "";
            if (at < _bytes.Length && _dialect.Keyword(_bytes[at]) is "+" or "-")
            {
                sign = _dialect.Keyword(_bytes[at]) ?? "";
                at++;
            }

            if (at < _bytes.Length && char.IsAsciiDigit((char)_bytes[at]))
            {
                text.Append('E').Append(sign);
                _at = at;
                int digits = _at;
                while (_at < _bytes.Length && char.IsAsciiDigit((char)_bytes[_at])) { _at++; }
                text.Append(Encoding.ASCII.GetString(_bytes, digits, _at - digits));
            }
        }

        if (_at < _bytes.Length && LevelTwo && _bytes[_at] is (byte)'#' or (byte)'!' or (byte)'%')
        {
            precise |= _bytes[_at] == '#';
            _at++;
        }

        return BasicNumbers.TryParse(text.ToString().Replace(" ", "", StringComparison.Ordinal), out double number)
            ? new(new(number), precise)
            : throw Syntax($"'{text}' is not a number");
    }

    // A variable or array element, named as BASIC names it: letters and digits, then a suffix.
    private BasicResult Name()
    {
        string name = Letters();
        if (_at < _bytes.Length && IsSuffix(_bytes[_at])) { name += (char)_bytes[_at++]; }

        List<int>? subscripts = null;
        Skip();
        if (_at < _bytes.Length && _bytes[_at] == '(')
        {
            _at++;
            subscripts = [.. Arguments().Select(argument => (int)Math.Truncate(Number(argument)))];
        }

        return Variable(name, subscripts);
    }

    // Letters and digits, as a name continues.
    private string Letters()
    {
        int start = _at;
        while (_at < _bytes.Length && char.IsAsciiLetterOrDigit((char)_bytes[_at])) { _at++; }
        return Encoding.ASCII.GetString(_bytes, start, _at - start);
    }

    // A type suffix: $ and %, and on Level II ! and # too.
    private bool IsSuffix(byte value) =>
        value is (byte)'$' or (byte)'%' || (LevelTwo && value is (byte)'!' or (byte)'#');

    private BasicResult Variable(string name, List<int>? subscripts)
    {
        string key = name.ToUpperInvariant();
        if (subscripts is null && _bound.TryGetValue(key, out BasicValue bound)) { return new(bound); }
        if (subscripts is null)
        {
            if (_variables.Find(name) is not { } variable)
            {
                return name.EndsWith('$') ? new(BasicValue.Of([])) : new(new(0));
            }

            return new(_variables.Read(variable.Kind, variable.ValueAddress), variable.Kind == BasicVariableKind.Double);
        }

        if (_variables.FindArray(name) is not { } array)
        {
            // BASIC makes an array it has not seen with 11 elements for each subscript.
            if (subscripts.Any(subscript => subscript is < 0 or >= AutomaticDimension))
            {
                throw new FormatException("?BAD SUBSCRIPT ERROR.");
            }

            return name.EndsWith('$') ? new(BasicValue.Of([])) : new(new(0));
        }

        try
        {
            return new(_variables.Read(array.Kind, array.ElementAddress(subscripts)), array.Kind == BasicVariableKind.Double);
        }
        catch (ArgumentOutOfRangeException exception)
        {
            throw new FormatException(exception.Message.Split(" (")[0], exception);
        }
    }

    // FN name(argument): the DEF FN body with its parameter bound to the argument.
    private BasicResult Function()
    {
        Skip();
        string name = Letters();
        Expect('(');
        BasicResult argument = Or();
        Expect(')');
        if (_functions?.Invoke(name.ToUpperInvariant()) is not { } function)
        {
            throw new FormatException("?UNDEF'D FUNCTION ERROR.");
        }

        if (++_depth > MaximumDepth) { throw new FormatException("?FORMULA TOO COMPLEX ERROR."); }
        string parameter = function.Parameter.ToUpperInvariant();
        bool had = _bound.TryGetValue(parameter, out BasicValue previous);
        _bound[parameter] = argument.Value;
        try
        {
            return Evaluate(function.Body);
        }
        finally
        {
            _depth--;
            if (had) { _bound[parameter] = previous; }
            else { _bound.Remove(parameter); }
        }
    }

    private BasicResult Call(string word)
    {
        if (s_refused.Contains(word))
        {
            throw new FormatException($"{word.TrimEnd('(')} cannot be evaluated without running BASIC.");
        }

        Skip();
        if (!word.EndsWith('(')) { Expect('('); }
        List<BasicResult> arguments = Arguments();
        double First() => Number(arguments[0]);
        byte[] Text0() => Text(arguments[0]);
        int Count(int index) => (int)Math.Truncate(Number(arguments[index]));
        return word switch
        {
            "SGN" => Numeric(Math.Sign(First())),
            "INT" => Numeric(Math.Floor(First())),
            "ABS" => Numeric(Math.Abs(First())),
            "SQR" => Numeric(Math.Sqrt(First())),
            "LOG" => Numeric(Math.Log(First())),
            "EXP" => Numeric(Math.Exp(First())),
            "COS" => Numeric(Math.Cos(First())),
            "SIN" => Numeric(Math.Sin(First())),
            "TAN" => Numeric(Math.Tan(First())),
            "ATN" => Numeric(Math.Atan(First())),
            "FIX" => Numeric(Math.Truncate(First())),
            "CINT" => Numeric(ToInteger(Math.Round(First(), MidpointRounding.AwayFromZero))),
            "CSNG" => Numeric(First()),
            "CDBL" => new(new(First()), Double: true),
            "PEEK" => Numeric(_memory.Read(Count(0) & 0xFFFF)),
            "LEN" => Numeric(Text0().Length),
            "ASC" => Text0() is { Length: > 0 } text ? Numeric(text[0]) : throw new FormatException(EmptyAscii),
            "VAL" => Numeric(BasicNumbers.TryParse(Leading(Encoding.ASCII.GetString(Text0())), out double number) ? number : 0),
            "STR$" => new(BasicValue.Of(Encoding.ASCII.GetBytes((First() >= 0 ? " " : "") + Format(arguments[0])))),
            "CHR$" => new(BasicValue.Of([(byte)Count(0)])),
            "LEFT$" => new(BasicValue.Of([.. Text0().Take(Count(1))])),
            "RIGHT$" => new(BasicValue.Of([.. Text0().Skip(Math.Max(0, Text0().Length - Count(1)))])),
            "MID$" => new(BasicValue.Of([.. Text0().Skip(Count(1) - 1).Take(arguments.Count > 2 ? Count(2) : 255)])),
            "STRING$" => Repeat(arguments),
            "INSTR" => Numeric(Instr(arguments)),
            _ => throw new FormatException($"{word} is not a function.")
        };
    }

    private static BasicResult Numeric(double value) => new(new(value));

    // STRING$(count, character): the character as a code or the first of a string.
    private static BasicResult Repeat(List<BasicResult> arguments)
    {
        byte character = arguments[1].Value.IsString ? Text(arguments[1]).FirstOrDefault() : (byte)Number(arguments[1]);
        return new(BasicValue.Of([.. Enumerable.Repeat(character, (int)Math.Truncate(Number(arguments[0])))]));
    }

    // The arguments in parentheses, after the opening one.
    private List<BasicResult> Arguments()
    {
        List<BasicResult> arguments = [Or()];
        while (Skip() && _at < _bytes.Length && _bytes[_at] == ',')
        {
            _at++;
            arguments.Add(Or());
        }

        Expect(')');
        return arguments;
    }

    private static int Instr(List<BasicResult> arguments)
    {
        int start = arguments.Count == 3 ? (int)Number(arguments[0]) : 1;
        byte[] text = Text(arguments[^2]);
        byte[] find = Text(arguments[^1]);
        if (start < 1 || start > text.Length) { return 0; }
        int found = text.AsSpan(start - 1).IndexOf(find);
        return found < 0 ? 0 : found + start;
    }

    private BasicResult Logic(BasicResult left, BasicResult right, Func<int, int, int> bits, Func<bool, bool, bool> logic) =>
        Bitwise
            ? new(new(bits(ToInteger(Number(left)), ToInteger(Number(right)))))
            : new(new(logic(Number(left) != 0, Number(right) != 0) ? 1 : 0));

    private static int ToInteger(double value) =>
        value is < short.MinValue or > short.MaxValue
            ? throw new FormatException("?ILLEGAL QUANTITY ERROR: AND, OR and NOT take -32768 to 32767.")
            : (short)Math.Truncate(value);

    private static int Compare(BasicResult left, BasicResult right)
    {
        if (left.Value.IsString != right.Value.IsString) { throw new FormatException("?TYPE MISMATCH ERROR."); }
        return left.Value.IsString ? Text(left).AsSpan().SequenceCompareTo(Text(right)) : Number(left).CompareTo(Number(right));
    }

    private static double Number(BasicResult result) =>
        result.Value.IsString ? throw new FormatException("?TYPE MISMATCH ERROR: a string where a number is needed.") : result.Value.Number;

    private static byte[] Text(BasicResult result) =>
        result.Value.Text ?? throw new FormatException("?TYPE MISMATCH ERROR: a number where a string is needed.");

    private static string Leading(string text) => LeadingNumber().Match(text).Value;

    private bool Take(string keyword)
    {
        Skip();
        if (_at >= _bytes.Length || _dialect.KeywordAt(_bytes, _at, out int length) != keyword) { return false; }
        _at += length;
        return true;
    }

    private void Expect(char character)
    {
        Skip();
        if (_at >= _bytes.Length || _bytes[_at] != character) { throw Syntax($"'{character}' is missing"); }
        _at++;
    }

    // Skips the spaces Level II keeps; always true, for chaining.
    private bool Skip()
    {
        while (_at < _bytes.Length && _bytes[_at] == ' ') { _at++; }
        return true;
    }

    private string Rest() => _dialect.Detokenize(_bytes.AsSpan(_at));

    private static FormatException Syntax(string why) => new($"?SYNTAX ERROR: {why}.");

    [GeneratedRegex(@"^[A-Za-z][A-Za-z0-9]*[$%!#]?$")]
    private static partial Regex BareName();

    [GeneratedRegex(@"^\s*[-+]?(\d+\.?\d*|\.\d+)([ED][-+]?\d+)?", RegexOptions.IgnoreCase)]
    private static partial Regex LeadingNumber();
}
