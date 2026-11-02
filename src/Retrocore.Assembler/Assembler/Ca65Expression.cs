// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Buffers;
using System.Globalization;

namespace Retrocore.Assembler;

/// <summary>
///  Parses one ca65 expression with ca65 operator precedence and writes an explicitly grouped native expression.
/// </summary>
/// <remarks>
///  <para>
///   ca65 ranks operators differently from native syntax: multiplication, bitwise and, xor and shifts share one
///   level; addition, subtraction and bitwise or share the next; <c>.and</c> and <c>.xor</c> share a level; and
///   <c>!</c> applies to the whole remaining expression. Every operator node below the top is therefore
///   parenthesized, so the native evaluator's own precedence never affects the result. The top level stays
///   unparenthesized because an instruction operand wrapped in parentheses means indirect addressing.
///  </para>
///  <para>
///   The output is written once, into a pooled buffer. Each node returns where its text starts and whether it is
///   atomic; a parent that needs a compound child grouped inserts the parentheses around that child's text.
///  </para>
/// </remarks>
internal ref partial struct Ca65Expression
{
    private readonly string _text;
    private readonly long _time;
    private int _position;
    private char[] _output;
    private int _length;

    // Binary operators by ca65 precedence level; a longer token precedes any token that is its prefix.
    private static readonly string[][] Operators =
    [
        [],
        [],
        ["*", "/", ".mod", "&", ".bitand", "^", ".bitxor", "<<", ".shl", ">>", ".shr"],
        ["+", "-", "|", ".bitor"],
        ["<>", "<=", ">=", "<", ">", "="],
        ["&&", ".and", ".xor"],
        ["||", ".or"]
    ];

    private Ca65Expression(string text, DateTimeOffset time)
    {
        _text = text;
        _time = time.ToUnixTimeSeconds();
        _output = ArrayPool<char>.Shared.Rent(text.Length * 2 + 16);
    }

    /// <summary>
    ///  Translates a complete ca65 expression.
    /// </summary>
    /// <param name="text">The ca65 expression.</param>
    /// <param name="time">The reproducible value of <c>.time</c>.</param>
    /// <returns>Native syntax, or null when the text is not a ca65 expression this translator understands.</returns>
    internal static string? Translate(string text, DateTimeOffset time)
    {
        Ca65Expression parser = new(text, time);
        try
        {
            _ = parser.Not();
            parser.SkipSpace();
            if (parser._position != text.Length) { return null; }

            // A plain number or name comes out unchanged, so the original string serves without a copy.
            ReadOnlySpan<char> result = parser._output.AsSpan(0, parser._length);
            return result.SequenceEqual(text.AsSpan()) ? text : result.ToString();
        }
        catch (FormatException)
        {
            return null;
        }
        finally
        {
            ArrayPool<char>.Shared.Return(parser._output);
        }
    }

    // Level 7: ! and .not apply to the entire expression that follows them.
    private Node Not()
    {
        if (!TakeWord(".not") && !TakeBang()) { return Or(); }
        int start = _length;
        Append(".not ");
        Group(Not());
        return new(start, Atomic: false);
    }

    // Level 6: ||. Level 5: && with .xor. Level 4: comparisons. Level 3: additive. Level 2: multiplicative.
    private Node Or() => Level(6);

    private Node Level(int level)
    {
        if (level == 1) { return Unary(); }
        Node left = Level(level - 1);
        while (Operator(level) is { } op)
        {
            Group(left);
            Append(' ');
            Append(op);
            Append(' ');
            Group(Level(level - 1));
            left = new(left.Start, Atomic: false);
        }

        return left;
    }

    private string? Operator(int level)
    {
        SkipSpace();
        foreach (string token in Operators[level])
        {
            if (!IsOperatorAhead(token)) { continue; }
            _position += token.Length;
            return NativeOperator(token);
        }

        return null;
    }

    private readonly bool IsOperatorAhead(string token)
    {
        if (token[0] == '.') { return IsWordAhead(token); }
        if (string.CompareOrdinal(_text, _position, token, 0, token.Length) != 0) { return false; }

        // A single |, &, < or > must not take the first half of ||, &&, << or >>.
        return token.Length != 1 || token[0] is not ('|' or '&' or '<' or '>') || PeekAt(1) != token[0];
    }

    private static string NativeOperator(string token) => token.ToLowerInvariant() switch
    {
        ".bitand" => "&",
        ".bitxor" => "^",
        ".shl" => "<<",
        ".shr" => ">>",
        ".bitor" => "|",
        "<>" => "!=",
        ".and" => "&&",
        ".or" => "||",
        _ => token.ToLowerInvariant()
    };

    // Level 1: prefix operators bind to the next prefix expression or primary.
    private Node Unary()
    {
        if (TakeChar('+')) { return Unary(); }
        int start = _length;
        if (TakeChar('^'))
        {
            Append(".bankbyte(");
            _ = Unary();
            Append(')');
            return new(start, Atomic: true);
        }

        char prefix;
        if (TakeChar('-')) { prefix = '-'; }
        else if (TakeChar('~') || TakeWord(".bitnot")) { prefix = '~'; }
        else if (TakeChar('<')) { prefix = '<'; }
        else if (TakeChar('>')) { prefix = '>'; }
        else { return Primary(); }

        Append(prefix);
        Group(Unary());
        return new(start, Atomic: false);
    }

    private Node Primary()
    {
        char next = Peek();
        int start = _position;
        if (next == '(')
        {
            _position++;
            Node inner = Not();
            if (Peek() != ')') { throw new FormatException(); }
            _position++;
            return inner;
        }

        if (next == '!' || (next == '.' && IsWordAhead(".not")))
        {
            return Not();
        }

        if (next == '*')
        {
            _position++;
        }
        else if (next is '"' or '\'')
        {
            _position++;
            while (_position < _text.Length && _text[_position] != next) { _position++; }
            if (_position == _text.Length) { throw new FormatException(); }
            _position++;
        }
        else if (next == '$' || next == '%' || char.IsAsciiDigit(next))
        {
            _position++;
            while (_position < _text.Length && (char.IsAsciiLetter(_text[_position]) || char.IsAsciiDigit(_text[_position])))
            {
                _position++;
            }
        }
        else if (next == ':' && PeekAt(1) is '+' or '-')
        {
            char sign = _text[_position + 1];
            _position += 2;
            while (_position < _text.Length && _text[_position] == sign) { _position++; }
        }
        else if (next == '.')
        {
            return Function();
        }
        else
        {
            int length = AssemblySyntax.IdentifierLength(_text.AsSpan(_position));
            if (length == 0) { throw new FormatException(); }
            _position += length;
        }

        return Source(start);
    }

    private Node Function()
    {
        int start = _position;
        _position++;
        while (_position < _text.Length && char.IsAsciiLetter(_text[_position])) { _position++; }
        ReadOnlySpan<char> word = _text.AsSpan(start, _position - start);
        int output = _length;
        if (word.Equals(".time", StringComparison.OrdinalIgnoreCase))
        {
            // The build time may predate 1970, and the current culture can spell the minus sign differently.
            long seconds = _time;
            Append(seconds.ToString(CultureInfo.InvariantCulture));
            return new(output, Atomic: true);
        }

        if (word.Equals(".version", StringComparison.OrdinalIgnoreCase))
        {
            Append("$0213");
            return new(output, Atomic: true);
        }

        bool low = word.Equals(".lobyte", StringComparison.OrdinalIgnoreCase);
        bool high = word.Equals(".hibyte", StringComparison.OrdinalIgnoreCase);
        if (low || high || word.Equals(".bankbyte", StringComparison.OrdinalIgnoreCase))
        {
            if (Peek() != '(') { throw new FormatException(); }
            _position++;
            Append(low ? "<(" : high ? ">(" : ".bankbyte(");
            _ = Not();
            Append(')');
            if (Peek() != ')') { throw new FormatException(); }
            _position++;
            return new(output, Atomic: !low && !high);
        }

        // Other built-in functions keep their ca65 spelling, so the native evaluator reports them if unsupported.
        SkipSpace();
        int arguments = _position;
        if (Peek() == '(')
        {
            int depth = 0;
            for (; _position < _text.Length; _position++)
            {
                char character = _text[_position];
                if (character is '"' or '\'')
                {
                    int close = _text.IndexOf(character, _position + 1);
                    if (close < 0) { throw new FormatException(); }
                    _position = close;
                }
                else if (character == '(')
                {
                    depth++;
                }
                else if (character == ')' && --depth == 0)
                {
                    _position++;
                    break;
                }
            }

            if (depth != 0) { throw new FormatException(); }
        }

        if (arguments < _text.Length && _text[arguments] == '(')
        {
            string name = word.ToString().ToLowerInvariant();
            string? replacement = StringFunction(name, _text[(arguments + 1)..(_position - 1)], FunctionNumber);
            if (replacement is not null)
            {
                Append(replacement);
                return new(output, Atomic: true);
            }
        }

        return Source(start);
    }

    /// <summary>
    ///  Copies the source text read since a position, as an atomic node.
    /// </summary>
    /// <param name="start">Where the token starts in the source.</param>
    /// <returns>The node.</returns>
    private Node Source(int start)
    {
        int output = _length;
        Append(_text.AsSpan(start, _position - start));
        return new(output, Atomic: true);
    }

    /// <summary>
    ///  Puts a compound node in parentheses, so native precedence cannot regroup it.
    /// </summary>
    /// <param name="node">The node, which must be the last text written.</param>
    private void Group(Node node)
    {
        if (node.Atomic) { return; }
        Reserve(2);
        _output.AsSpan(node.Start, _length - node.Start).CopyTo(_output.AsSpan(node.Start + 1));
        _output[node.Start] = '(';
        _length++;
        _output[_length++] = ')';
    }

    private void Append(char value)
    {
        Reserve(1);
        _output[_length++] = value;
    }

    private void Append(scoped ReadOnlySpan<char> value)
    {
        Reserve(value.Length);
        value.CopyTo(_output.AsSpan(_length));
        _length += value.Length;
    }

    private void Reserve(int count)
    {
        if (_length + count <= _output.Length) { return; }
        char[] larger = ArrayPool<char>.Shared.Rent(Math.Max(_output.Length * 2, _length + count));
        _output.AsSpan(0, _length).CopyTo(larger);
        ArrayPool<char>.Shared.Return(_output);
        _output = larger;
    }

    private void SkipSpace()
    {
        while (_position < _text.Length && char.IsWhiteSpace(_text[_position])) { _position++; }
    }

    private char Peek()
    {
        SkipSpace();
        return _position < _text.Length ? _text[_position] : '\0';
    }

    private readonly char PeekAt(int offset) =>
        _position + offset < _text.Length ? _text[_position + offset] : '\0';

    private bool TakeChar(char value, char unless = '\0')
    {
        if (Peek() != value || (unless != '\0' && PeekAt(1) == unless)) { return false; }
        _position++;
        return true;
    }

    private bool TakeBang()
    {
        if (Peek() != '!') { return false; }
        _position++;
        return true;
    }

    private bool TakeWord(string word)
    {
        SkipSpace();
        if (!IsWordAhead(word)) { return false; }
        _position += word.Length;
        return true;
    }

    private readonly bool IsWordAhead(string word) =>
        _position + word.Length <= _text.Length
            && string.Compare(_text, _position, word, 0, word.Length, StringComparison.OrdinalIgnoreCase) == 0
            && (_position + word.Length == _text.Length || !AssemblySyntax.IsWord(_text[_position + word.Length]));
}
