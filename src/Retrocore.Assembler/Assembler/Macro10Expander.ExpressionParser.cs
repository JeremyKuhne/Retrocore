// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Globalization;

namespace Retrocore.Assembler;

internal sealed partial class Macro10Expander
{
    /// <summary>
    ///  Recursive-descent parsing of one MACRO-10 expression into fully grouped native text.
    /// </summary>
    /// <param name="owner">The expander, for the radix, symbol values and native names.</param>
    /// <param name="text">The expression.</param>
    /// <param name="addresses">Whether labels and the location counter have the expander's layout values.</param>
    private sealed class ExpressionParser(Macro10Expander owner, string text, bool addresses)
    {
        private int _position;

        /// <summary>
        ///  Parses the whole expression.
        /// </summary>
        /// <returns>The native text and the value when constant.</returns>
        internal (string Text, long? Value) Parse()
        {
            if (text.Trim().Length == 0) { throw new AssemblyError(0, "Expected an expression."); }
            (string Text, long? Value) result = Additive();
            Skip();
            string rest = text[_position..].Trim();
            return rest.Length != 0 ? throw new AssemblyError(0, $"Unexpected '{rest}' in expression.") : result;
        }

        private (string Text, long? Value) Additive()
        {
            (string Text, long? Value) left = Multiplicative();
            while (Operator("+", "-") is { } operation)
            {
                (string Text, long? Value) right = Multiplicative();
                long? value = null;
                if (left.Value is { } a && right.Value is { } b) { value = operation == "+" ? a + b : a - b; }
                left = Binary(left, operation, right, value);
            }

            return left;
        }

        private (string Text, long? Value) Multiplicative()
        {
            (string Text, long? Value) left = Logical();
            while (Operator("*", "/") is { } operation)
            {
                (string Text, long? Value) right = Logical();
                long? value = null;
                if (left.Value is { } a && right.Value is { } b)
                {
                    if (operation == "/" && b == 0) { throw new AssemblyError(0, "Division by zero."); }
                    value = operation == "*" ? a * b : a / b;
                }

                left = Binary(left, operation, right, value);
            }

            return left;
        }

        private (string Text, long? Value) Logical()
        {
            (string Text, long? Value) left = Shift();
            while (Operator("&", "!", "^!") is { } operation)
            {
                (string Text, long? Value) right = Shift();
                string native = operation switch
                {
                    "&" => "&",
                    "!" => "|",
                    _ => "^"
                };

                long? value = null;
                if (left.Value is { } a && right.Value is { } b)
                {
                    value = operation switch
                    {
                        "&" => a & b,
                        "!" => a | b,
                        _ => a ^ b
                    };
                }

                left = Binary(left, native, right, value);
            }

            return left;
        }

        private (string Text, long? Value) Shift()
        {
            (string Text, long? Value) left = Unary();
            while (Operator("_") is not null)
            {
                (string Text, long? Value) right = Unary();
                if (right.Value is not { } count) { throw new AssemblyError(0, "A shift count must be a constant."); }
                long? value = null;
                if (left.Value is { } a) { value = count >= 0 ? a << (int)count : a >> (int)-count; }
                (string Text, long? Value) amount = Constant(Math.Abs(count));
                left = Binary(left, count >= 0 ? "<<" : ">>", amount, value);
            }

            return left;
        }

        private (string Text, long? Value) Unary()
        {
            if (Operator("^-") is not null)
            {
                (string Text, long? Value) operand = Unary();
                return operand.Value is { } value ? Constant(~value) : ($"(~{operand.Text})", null);
            }

            if (Operator("-") is not null)
            {
                (string Text, long? Value) operand = Unary();
                return operand.Value is { } value ? Constant(-value) : ($"(-{operand.Text})", null);
            }

            return Operator("+") is not null ? Unary() : Primary();
        }

        private (string Text, long? Value) Primary()
        {
            Skip();
            char next = Peek(0);
            if (next == '<')
            {
                _position++;
                (string Text, long? Value) inner = Additive();
                return Operator(">") is null ? throw new AssemblyError(0, "Unterminated <expression>.") : inner;
            }

            if (next == '^' && char.ToUpperInvariant(Peek(1)) is 'D' or 'O' or 'B')
            {
                int radix = char.ToUpperInvariant(Peek(1)) switch
                {
                    'D' => 10,
                    'O' => 8,
                    _ => 2
                };

                _position += 2;
                Skip();
                return Number(radix, allowDecimalPoint: false);
            }

            if (char.IsAsciiDigit(next)) { return Number(owner._radix, allowDecimalPoint: true); }
            if (next == '"') { return Ascii(); }
            if (next == '.' && !IsSymbolCharacter(Peek(1)))
            {
                _position++;
                return ("*", addresses ? owner._location : null);
            }

            string symbol = ReadSymbol(text, ref _position)
                ?? throw new AssemblyError(0, $"Unexpected '{(next == '\0' ? "end" : next.ToString())}' in expression.");

            string normalized = Normalize(symbol);
            if (owner._values.TryGetValue(normalized, out long? known) && known is { } value)
            {
                return Constant(value);
            }

            long? address = addresses && owner._addresses.TryGetValue(normalized, out long laidOut) ? laidOut : null;
            return (owner.NativeName(normalized), address);
        }

        private (string Text, long? Value) Number(int radix, bool allowDecimalPoint)
        {
            int start = _position;
            while (_position < text.Length && char.IsAsciiDigit(text[_position])) { _position++; }
            if (start == _position) { throw new AssemblyError(0, "Expected a number."); }
            string digits = text[start.._position];

            // A trailing decimal point makes a number decimal whatever the radix.
            if (allowDecimalPoint && Peek(0) == '.' && !IsSymbolCharacter(Peek(1)))
            {
                _position++;
                radix = 10;
            }

            // As in MACRO-10, 8 and 9 keep their face value in radix 8; the math package's 8*ADDPRC relies on it.
            long value = 0;
            foreach (char digit in digits) { value = checked((value * radix) + (digit - '0')); }

            return Constant(value);
        }

        private (string Text, long? Value) Ascii()
        {
            int close = text.IndexOf('"', _position + 1);
            if (close < 0) { throw new AssemblyError(0, "Unterminated string."); }
            long value = 0;
            foreach (char character in text[(_position + 1)..close]) { value = (value << 7) | (character & 0x7FL); }
            _position = close + 1;
            return Constant(value);
        }

        private static (string Text, long? Value) Constant(long value)
        {
            string digits = Math.Abs(value).ToString(CultureInfo.InvariantCulture);
            return (value < 0 ? $"(-{digits})" : digits, value);
        }

        private static (string Text, long? Value) Binary(
            (string Text, long? Value) left,
            string operation,
            (string Text, long? Value) right,
            long? value)
        {
            return value is { } known ? Constant(known) : ($"({left.Text} {operation} {right.Text})", null);
        }

        /// <summary>
        ///  Takes the first of the given operators that comes next.
        /// </summary>
        /// <param name="operations">The operators, longer before any that is its prefix.</param>
        /// <returns>The operator taken, or null.</returns>
        private string? Operator(params string[] operations)
        {
            Skip();
            foreach (string operation in operations)
            {
                if (string.CompareOrdinal(text, _position, operation, 0, operation.Length) != 0) { continue; }

                // '^!' and '^-' are operators of their own, so a lone '^' never starts '!' or '-'.
                if (operation == "-" && _position > 0 && text[_position - 1] == '^') { continue; }
                _position += operation.Length;
                return operation;
            }

            return null;
        }

        private void Skip()
        {
            while (_position < text.Length && text[_position] is ' ' or '\t') { _position++; }
        }

        private char Peek(int offset) => _position + offset < text.Length ? text[_position + offset] : '\0';
    }
}
