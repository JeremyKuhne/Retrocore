// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

/// <summary>
///  Stack-only integer expression parsing over source slices, without token arrays or strings.
/// </summary>
/// <remarks>
///  <para>
///   This is a precedence-climbing parser with one-token lookahead. <see cref="Advance"/> selects a token
///   using offsets into the original expression; it never creates token strings. Saved token slices remain
///   valid when recursive calls advance the cursor.
///  </para>
///  <para>
///   The resolution flag is shared by the entire evaluation. A forward reference makes the result unknown,
///   but parsing continues so later layout passes can retry the same expression without losing syntax validation.
///  </para>
/// </remarks>
internal ref struct ExpressionEvaluator
{
    /// <summary>
    ///  The error for a character literal that does not hold exactly one character.
    /// </summary>
    internal const string CharacterLiteralMessage =
        "A character literal holds one character, as in 'A'; write a string in double quotes.";

    private const int BinaryRadix = 2;
    private const int DecimalRadix = 10;
    private const int HexadecimalRadix = 16;
    private const int IntegerBitCount = sizeof(long) * InstructionEncoding.BitsPerByte;

    private readonly ReadOnlyMemory<char> _text;
    private readonly AssemblySymbols _symbols;
    private readonly int _address;
    private readonly int _line;
    private int _position;
    private int _tokenStart;
    private int _tokenLength;
    private bool _contextual;
    private bool _readsAddress;
    private readonly ExpressionPrograms? _recording;

    /// <summary>
    ///  Creates a cursor over an expression.
    /// </summary>
    /// <param name="text">The expression slice.</param>
    /// <param name="symbols">Symbols resolved during layout.</param>
    /// <param name="address">The current assembly address.</param>
    /// <param name="line">The diagnostic statement index.</param>
    /// <param name="recording">Receives the expression's postfix steps while it evaluates, when supplied.</param>
    internal ExpressionEvaluator(
        ReadOnlyMemory<char> text,
        AssemblySymbols symbols,
        int address,
        int line,
        ExpressionPrograms? recording = null)
    {
        _text = text;
        _symbols = symbols;
        _address = address;
        _line = line;
        _recording = recording;
        _position = 0;
        _tokenStart = 0;
        _tokenLength = 0;
        _contextual = false;
        _readsAddress = false;
        Advance();
        if (_tokenLength == 0) { throw new AssemblyError(line, $"Invalid expression '{text}'."); }
    }

    /// <summary>
    ///  Gets whether the evaluated expression read a symbol or the location counter.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   A complete evaluation that read neither has a value and diagnostics fixed by its text alone, so layout
    ///   passes may reuse that value instead of evaluating the expression again.
    ///  </para>
    /// </remarks>
    internal readonly bool IsContextual => _contextual;

    /// <summary>
    ///  Gets whether the expression read * rather than only constants.
    /// </summary>
    internal readonly bool ReadsAddress => _readsAddress;

    /// <summary>
    ///  Evaluates an expression, retaining unresolved forward symbols for later layout passes.
    /// </summary>
    /// <param name="value">The value if fully resolved; ignore it when the return value is false.</param>
    /// <returns>Whether every symbol is currently known.</returns>
    /// <exception cref="AssemblyError">
    ///  The expression contains invalid syntax or an invalid arithmetic operation.
    /// </exception>
    /// <exception cref="OverflowException">
    ///  Checked arithmetic overflowed; the compiler converts this to an assembly diagnostic.
    /// </exception>
    internal bool TryEvaluate(out long value)
    {
        bool known = true;
        value = Parse(minimum: 0, ref known);
        return _tokenLength != 0 ? throw new AssemblyError(_line, "Unexpected expression suffix.") : known;
    }

    /// <summary>
    ///  Parses binary operators that bind at least as tightly as the requested precedence.
    /// </summary>
    /// <param name="minimum">The minimum accepted precedence; zero admits every binary operator.</param>
    /// <param name="known">The shared resolution flag, which stays false once any symbol is unresolved.</param>
    /// <returns>The accumulated value, meaningful only while <paramref name="known"/> remains true.</returns>
    /// <remarks>
    ///  <para>
    ///   Equal-precedence operators are consumed by this loop, while recursive calls consume only stronger
    ///   operators. A closing parenthesis has no binary precedence and is left for its enclosing group.
    ///  </para>
    /// </remarks>
    private long Parse(int minimum, ref bool known)
    {
        long left = Primary(ref known);
        while (_tokenLength != 0 && Precedence(Current) >= minimum)
        {
            ReadOnlySpan<char> operation = Current;
            ExpressionOperationKind kind = BinaryOperation(operation);
            Advance();

            // The stricter right-hand threshold groups a - b - c as (a - b) - c.
            long right = Parse(Precedence(operation) + 1, ref known);
            _recording?.Add(new(kind));
            if (!known)
            {
                // Consume syntax, but do not divide or shift using unresolved symbols' placeholder values.
                left = 0;
                continue;
            }

            left = kind switch
            {
                ExpressionOperationKind.Add => checked(left + right),
                ExpressionOperationKind.Subtract => checked(left - right),
                ExpressionOperationKind.Multiply => checked(left * right),
                ExpressionOperationKind.Divide => right == 0 ? throw new AssemblyError(_line, "Division by zero.") : checked(left / right),
                ExpressionOperationKind.Modulo => right == 0 ? throw new AssemblyError(_line, "Division by zero.") : checked(left % right),
                ExpressionOperationKind.ShiftLeft => right is < 0 or >= IntegerBitCount
                    ? throw new AssemblyError(_line, "Invalid shift count.") : left << (int)right,
                ExpressionOperationKind.ShiftRight => right is < 0 or >= IntegerBitCount
                    ? throw new AssemblyError(_line, "Invalid shift count.") : left >> (int)right,
                ExpressionOperationKind.And => left & right,
                ExpressionOperationKind.Or => left | right,
                ExpressionOperationKind.Xor => left ^ right,
                ExpressionOperationKind.Equal => left == right ? 1 : 0,
                ExpressionOperationKind.NotEqual => left != right ? 1 : 0,
                ExpressionOperationKind.Less => left < right ? 1 : 0,
                ExpressionOperationKind.Greater => left > right ? 1 : 0,
                ExpressionOperationKind.LessOrEqual => left <= right ? 1 : 0,
                ExpressionOperationKind.GreaterOrEqual => left >= right ? 1 : 0,
                ExpressionOperationKind.LogicalAnd => left != 0 && right != 0 ? 1 : 0,
                ExpressionOperationKind.LogicalOr => left != 0 || right != 0 ? 1 : 0,
                ExpressionOperationKind.LogicalXor => (left != 0) != (right != 0) ? 1 : 0,
                _ => throw new AssemblyError(_line, "Unsupported expression operator.")
            };
        }

        return left;
    }

    /// <summary>
    ///  Parses an operand, parenthesized expression or prefix operator before binary operators are considered.
    /// </summary>
    /// <param name="known">The shared resolution flag; a missing symbol sets it to false.</param>
    /// <returns>The operand value, meaningful only while <paramref name="known"/> remains true.</returns>
    /// <remarks>
    ///  <para>
    ///   Prefix operators recurse into another primary, so they bind more tightly than binary operators.
    ///   Use parentheses, such as <c>&lt;(label + 1)</c>, to extract a byte from an entire binary expression.
    ///   A <c>*</c> in operand position is the location counter rather than multiplication.
    ///  </para>
    /// </remarks>
    private long Primary(ref bool known)
    {
        if (_tokenLength == 0) { throw new AssemblyError(_line, "Missing expression operand."); }

        // Keep memory as well as a span so symbol lookup can use the original slice as its key.
        ReadOnlyMemory<char> memory = _text.Slice(_tokenStart, _tokenLength);
        ReadOnlySpan<char> token = memory.Span;
        Advance();
        if (token is "(")
        {
            long value = Parse(minimum: 0, ref known);
            if (Current is not ")") { throw new AssemblyError(_line, "Missing closing parenthesis."); }
            Advance();
            return value;
        }

        if (token is "+" or "-" or "~" or "<" or ">"
            || (token[0] == '.' && token.Equals(".not", StringComparison.OrdinalIgnoreCase)))
        {
            // Here < and > select bytes; between operands Parse treats them as comparisons.
            long value = Primary(ref known);
            if (token is "+") { return value; }
            ExpressionOperationKind operation = UnaryOperation(token);
            _recording?.Add(new(operation));
            return operation switch
            {
                ExpressionOperationKind.Negate => checked(-value),
                ExpressionOperationKind.Complement => ~value,
                ExpressionOperationKind.LowByte => value & byte.MaxValue,
                ExpressionOperationKind.LogicalNot => value == 0 ? 1 : 0,
                _ => (value >> InstructionEncoding.BitsPerByte) & byte.MaxValue
            };
        }

        if (token[0] == '.' && (token.Equals(".lobyte", StringComparison.OrdinalIgnoreCase)
            || token.Equals(".hibyte", StringComparison.OrdinalIgnoreCase)
            || token.Equals(".bankbyte", StringComparison.OrdinalIgnoreCase)))
        {
            if (Current is not "(")
            {
                throw new AssemblyError(_line, "Byte extraction functions require parentheses.");
            }

            long value = Primary(ref known);
            ExpressionOperationKind operation = token.Equals(".lobyte", StringComparison.OrdinalIgnoreCase)
                ? ExpressionOperationKind.LowByte
                : token.Equals(".hibyte", StringComparison.OrdinalIgnoreCase)
                    ? ExpressionOperationKind.HighByte : ExpressionOperationKind.BankByte;

            _recording?.Add(new(operation));
            int shift = operation == ExpressionOperationKind.LowByte
                ? 0
                : operation == ExpressionOperationKind.HighByte
                    ? InstructionEncoding.BitsPerByte : 2 * InstructionEncoding.BitsPerByte;

            return (value >> shift) & byte.MaxValue;
        }

        if (token is "*")
        {
            _contextual = true;
            _readsAddress = true;
            _recording?.Add(new(ExpressionOperationKind.Address));
            return _address;
        }

        if (token[0] == '\'') { return Literal(token[1]); }
        if (token[0] is '$' or '%')
        {
            return Literal(Integer(token[1..], token[0] == '$' ? HexadecimalRadix : BinaryRadix));
        }

        if (char.IsAsciiDigit(token[0]))
        {
            return Literal(token.Length > 2 && token[0] == '0' && token[1] is 'x' or 'X'
                ? Integer(token[2..], HexadecimalRadix) : Integer(token, DecimalRadix));
        }

        if (!AssemblySyntax.IsIdentifierStart(token[0]) && !(token.Length > 2 && token[0] == ':' && token[1] == ':'))
        {
            throw new AssemblyError(_line, "Missing expression operand.");
        }

        _contextual = true;
        int id = _symbols.GetId(memory);
        if (id == AssemblySymbols.UnassignedVariable)
        {
            throw new AssemblyError(_line, $"Variable '{memory}' is used before assignment.");
        }

        _recording?.Add(new(ExpressionOperationKind.Symbol, id));
        if (_symbols.TryGetValue(id, out long symbol)) { return symbol; }

        // A later layout pass may resolve this name. Zero is a placeholder, not a resolved symbol value.
        known = false;
        return 0;
    }

    /// <summary>
    ///  Gets the current lookahead token, or an empty span at the end of the expression.
    /// </summary>
    private readonly ReadOnlySpan<char> Current => _text.Span.Slice(_tokenStart, _tokenLength);

    /// <summary>
    ///  Skips whitespace and selects the next complete token without interpreting its value.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   The token occupies <c>[_tokenStart, _tokenStart + _tokenLength)</c>; <c>_position</c> points just
    ///   beyond it. At end of input the token length is zero. Numeric prefixes and character literals are
    ///   recognized here, while prefix-versus-binary operator meaning is decided by the parser.
    ///  </para>
    /// </remarks>
    /// <exception cref="AssemblyError">The next characters do not form a native-dialect token.</exception>
    private void Advance()
    {
        ReadOnlySpan<char> text = _text.Span;
        while (_position < text.Length && char.IsWhiteSpace(text[_position])) { _position++; }
        _tokenStart = _position;
        _tokenLength = 0;
        if (_position == text.Length) { return; }
        char value = text[_position++];
        if (value is '$' or '%')
        {
            int digits = _position;
            while (_position < text.Length && (value == '$' ? char.IsAsciiHexDigit(text[_position]) : text[_position] is '0' or '1'))
            {
                _position++;
            }

            if (_position == digits) { throw new AssemblyError(_line, $"Invalid expression '{_text}'."); }
        }
        else if (char.IsAsciiDigit(value))
        {
            // Recognize 0x only when at least one hexadecimal digit follows it.
            if (value == '0'
                && _position + 1 < text.Length
                && text[_position] is 'x' or 'X'
                && char.IsAsciiHexDigit(text[_position + 1]))
            {
                _position++;
                while (_position < text.Length && char.IsAsciiHexDigit(text[_position])) { _position++; }
            }
            else
            {
                while (_position < text.Length && char.IsAsciiDigit(text[_position])) { _position++; }
            }
        }
        else if (value is not ('@' or ':') && AssemblySyntax.IsIdentifierStart(value))
        {
            // Plain names are the common case; only a following :: needs the qualified-name scanner.
            while (_position < text.Length && AssemblySyntax.IsWord(text[_position])) { _position++; }
            if (_position + 2 < text.Length && text[_position] == ':' && text[_position + 1] == ':')
            {
                _position = _tokenStart + AssemblySyntax.IdentifierLength(text[_tokenStart..]);
            }
        }
        else if (value == '@' || (value == ':' && _position < text.Length && text[_position] == ':'))
        {
            int length = AssemblySyntax.IdentifierLength(text[_tokenStart..]);
            if (length == 0) { throw new AssemblyError(_line, $"Invalid expression '{_text}'."); }
            _position = _tokenStart + length;
        }
        else if (value == '.' && _position < text.Length && char.IsAsciiLetter(text[_position]))
        {
            while (_position < text.Length && char.IsAsciiLetter(text[_position])) { _position++; }
        }
        else if (value == '\'' && _position + 1 < text.Length && text[_position] != '\'' && text[_position + 1] == '\'')
        {
            // Native character literals contain one UTF-16 code unit; escape sequences are not supported.
            _position += 2;
        }
        else if (value == '\'')
        {
            throw new AssemblyError(_line, CharacterLiteralMessage);
        }
        else if (value == '<' && _position < text.Length && text[_position] == '>')
        {
            // Other assemblers' inequality would otherwise read as a less-than of a high byte.
            throw new AssemblyError(_line, $"Use != for inequality in '{_text}'.");
        }
        else if (_position < text.Length
            && ((value is '=' or '!' or '<' or '>' && text[_position] == '=')
                || (value is '<' or '>' or '&' or '|' && text[_position] == value)))
        {
            // Prefer a complete comparison or shift token to its one-character prefix.
            _position++;
        }
        else if (value is not ('(' or ')' or '+' or '-' or '*' or '/' or '&' or '|' or '^' or '~' or '<' or '>' or '='))
        {
            throw new AssemblyError(_line, $"Invalid expression '{_text}'.");
        }

        _tokenLength = _position - _tokenStart;
    }

    /// <summary>
    ///  Parses prefix-free digits without culture-dependent conversion or temporary strings.
    /// </summary>
    /// <param name="digits">Non-empty digits already separated from a numeric prefix and any unary sign.</param>
    /// <param name="numberBase">The native literal radix: 2, 10 or 16.</param>
    /// <returns>The signed value, with hexadecimal and binary literals preserving all 64 bits.</returns>
    /// <remarks>
    ///  <para>
    ///   Decimal literals must fit the non-negative <see cref="long"/> range; unary minus is parsed separately.
    ///   Hexadecimal and binary literals may use the full unsigned range and are reinterpreted as signed
    ///   two's-complement values, so <c>$FFFFFFFFFFFFFFFF</c> represents -1.
    ///  </para>
    /// </remarks>
    /// <exception cref="AssemblyError">
    ///  A digit is invalid for the radix, or the literal exceeds its allowed range.
    /// </exception>
    private readonly long Integer(ReadOnlySpan<char> digits, int numberBase)
    {
        ulong value = 0;
        foreach (char character in digits)
        {
            int digit = character is >= '0' and <= '9'
                ? character - '0'
                : character is >= 'A' and <= 'F'
                    ? character - 'A' + 10
                    : character is >= 'a' and <= 'f' ? character - 'a' + 10 : -1;

            // Check before multiplying and adding so overflow cannot wrap an out-of-range literal.
            if (digit < 0 || digit >= numberBase || value > (ulong.MaxValue - (uint)digit) / (uint)numberBase)
            {
                throw new AssemblyError(_line, "Numeric literal overflow.");
            }

            value = value * (uint)numberBase + (uint)digit;
        }

        return numberBase == DecimalRadix && value > long.MaxValue
            ? throw new AssemblyError(_line, "Numeric literal overflow.") : unchecked((long)value);
    }

    /// <summary>
    ///  Records a literal operand when recording and returns its value.
    /// </summary>
    /// <param name="value">The literal value.</param>
    /// <returns>The same value.</returns>
    private readonly long Literal(long value)
    {
        _recording?.Add(new(ExpressionOperationKind.Constant, value));
        return value;
    }

    /// <summary>
    ///  Maps a binary operator token to its recorded step.
    /// </summary>
    /// <param name="operation">The operator token.</param>
    /// <returns>The step.</returns>
    private readonly ExpressionOperationKind BinaryOperation(ReadOnlySpan<char> operation) => operation switch
    {
        "+" => ExpressionOperationKind.Add, "-" => ExpressionOperationKind.Subtract, "*" => ExpressionOperationKind.Multiply,
        "/" => ExpressionOperationKind.Divide, "<<" => ExpressionOperationKind.ShiftLeft, ">>" => ExpressionOperationKind.ShiftRight,
        "&" => ExpressionOperationKind.And, "|" => ExpressionOperationKind.Or, "^" => ExpressionOperationKind.Xor,
        "=" or "==" => ExpressionOperationKind.Equal, "!=" => ExpressionOperationKind.NotEqual,
        "<" => ExpressionOperationKind.Less, ">" => ExpressionOperationKind.Greater,
        "<=" => ExpressionOperationKind.LessOrEqual, ">=" => ExpressionOperationKind.GreaterOrEqual,
        "&&" => ExpressionOperationKind.LogicalAnd, "||" => ExpressionOperationKind.LogicalOr,
        _ when operation.Equals(".and", StringComparison.OrdinalIgnoreCase) => ExpressionOperationKind.LogicalAnd,
        _ when operation.Equals(".or", StringComparison.OrdinalIgnoreCase) => ExpressionOperationKind.LogicalOr,
        _ when operation.Equals(".xor", StringComparison.OrdinalIgnoreCase) => ExpressionOperationKind.LogicalXor,
        _ when operation.Equals(".mod", StringComparison.OrdinalIgnoreCase) => ExpressionOperationKind.Modulo,
        _ => throw new AssemblyError(_line, "Unsupported expression operator.")
    };

    /// <summary>
    ///  Maps a prefix operator token, other than unary plus, to its recorded step.
    /// </summary>
    /// <param name="operation">The operator token.</param>
    /// <returns>The step.</returns>
    private static ExpressionOperationKind UnaryOperation(ReadOnlySpan<char> operation) => operation switch
    {
        "-" => ExpressionOperationKind.Negate,
        "~" => ExpressionOperationKind.Complement,
        "<" => ExpressionOperationKind.LowByte,
        _ when operation.Equals(".not", StringComparison.OrdinalIgnoreCase) => ExpressionOperationKind.LogicalNot,
        _ => ExpressionOperationKind.HighByte
    };

    /// <summary>
    ///  Gets native binary-operator precedence, from comparisons through multiplication and division.
    /// </summary>
    /// <param name="operation">The current token.</param>
    /// <returns>A precedence from zero to six, or -1 for a non-operator or end of input.</returns>
    /// <remarks>
    ///  <para>
    ///   A single <c>=</c> means equality here, not assignment. Returning -1 for closing parentheses lets
    ///   each nested parse stop without consuming the delimiter owned by its caller.
    ///  </para>
    /// </remarks>
    private static int Precedence(ReadOnlySpan<char> operation) => operation switch
    {
        "||" => 0, "&&" => 2,
        "=" or "==" or "!=" or "<" or ">" or "<=" or ">=" => 3,
        "|" => 4, "^" => 5, "&" => 6, "<<" or ">>" => 7, "+" or "-" => 8, "*" or "/" => 9,
        _ => NamedPrecedence(operation)
    };

    private static int NamedPrecedence(ReadOnlySpan<char> operation) => operation.Length switch
    {
        3 when operation.Equals(".or", StringComparison.OrdinalIgnoreCase) => 0,
        4 when operation.Equals(".xor", StringComparison.OrdinalIgnoreCase) => 1,
        4 when operation.Equals(".and", StringComparison.OrdinalIgnoreCase) => 2,
        4 when operation.Equals(".mod", StringComparison.OrdinalIgnoreCase) => 9,
        _ => -1
    };
}
