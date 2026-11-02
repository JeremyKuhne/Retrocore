// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

/// <summary>
///  Writes explicitly grouped native expressions using Merlin's left-to-right arithmetic.
/// </summary>
internal ref struct MerlinExpression
{
    private readonly string _text;
    private readonly MerlinNames _names;
    private readonly Dictionary<string, string>? _locals;
    private int _position;
    private readonly int _depth;
    private readonly bool _expandEquates;

    private MerlinExpression(string text, MerlinNames names, Dictionary<string, string>? locals, int depth, bool expandEquates)
    {
        _text = text;
        _names = names;
        _locals = locals;
        _depth = depth;
        _expandEquates = expandEquates;
    }

    /// <summary>
    ///  Translates a complete expression without turning a binary expression into indirect addressing.
    /// </summary>
    /// <param name="text">Merlin source syntax.</param>
    /// <param name="names">The compilation name map.</param>
    /// <param name="locals">Invocation bindings.</param>
    /// <param name="depth">Current textual expansion depth.</param>
    /// <param name="expandEquates">Whether this is a use rather than an EQU definition.</param>
    /// <returns>Equivalent native syntax.</returns>
    internal static string Translate(
        string text,
        MerlinNames names,
        Dictionary<string, string>? locals,
        int depth = 0,
        bool expandEquates = true)
    {
        if (depth >= names.MaximumDepth)
        {
            throw new AssemblyError(0, "Maximum Merlin EQU expression depth exceeded.");
        }

        MerlinExpression parser = new(text.Trim(), names, locals, depth, expandEquates);
        if (parser.Peek() == '#') { parser._position++; }
        string expression = parser.Expression();
        return parser.Peek() != '\0'
            ? throw new AssemblyError(0, $"Invalid Merlin expression '{text}'.")
            : expression.Length > 1 && expression[0] == '(' && expression[^1] == ')' ? expression[1..^1] : expression;
    }

    private string Expression()
    {
        string left = Primary();
        while (true)
        {
            char character = Peek();
            if (character is '\0' or ')') { return left; }
            string operation = character switch
            {
                '+' or '-' or '*' or '/' or '&' or '=' or '<' or '>' => character.ToString(),
                '.' => "|",
                '!' => "^",
                _ => throw new AssemblyError(0, $"Invalid Merlin operator '{character}'.")
            };

            _position++;
            if (character is '<' or '>' && Peek() == '=')
            {
                operation += "=";
                _position++;
            }
            else if (character == '<' && Peek() == '>')
            {
                operation = "!=";
                _position++;
            }

            left = $"({left}{operation}{Primary()})";
        }
    }

    private string Primary()
    {
        char character = Peek();
        if (character == '\0') { throw new AssemblyError(0, "Missing Merlin expression operand."); }
        if (character is '+' or '-' or '~')
        {
            _position++;
            return $"({character}{Primary()})";
        }

        if (character == '(')
        {
            _position++;
            string result = Expression();
            if (Peek() != ')') { throw new AssemblyError(0, "Unterminated Merlin expression group."); }
            _position++;
            return result;
        }

        if (character == '*')
        {
            _position++;
            return "*";
        }

        if (character is '"' or '\'')
        {
            _position++;
            if (_position + 1 >= _text.Length || _text[_position + 1] != character)
            {
                throw new AssemblyError(0, "A Merlin character expression requires one character.");
            }

            int value = _text[_position] | (character < '\'' ? 0x80 : 0);
            _position += 2;
            return value.ToString();
        }

        int start = _position;
        if (character is '$' or '%' || char.IsAsciiDigit(character))
        {
            _position++;
            while (_position < _text.Length && char.IsAsciiHexDigit(_text[_position])) { _position++; }
            return _text[start.._position];
        }

        while (_position < _text.Length && IsNameCharacter(_text[_position])) { _position++; }
        if (start == _position) { throw new AssemblyError(0, "Invalid Merlin symbol."); }
        string name = _text[start.._position];
        bool local = _locals?.ContainsKey(name) == true;
        return !local && _expandEquates && _names.Equates.TryGetValue(name, out string? equate)
            ? $"({Translate(equate, _names, _locals, _depth + 1)})"
            : _names.Resolve(name, _locals);
    }

    /// <summary>
    ///  Tests characters in Merlin symbol tokens.
    /// </summary>
    /// <param name="value">The character.</param>
    /// <returns>Whether it belongs to a name.</returns>
    internal static bool IsNameCharacter(char value) => !char.IsWhiteSpace(value) && !IsDelimiter(value);

    private static bool IsDelimiter(char value) =>
        value is '+' or '-' or '*' or '/' or '&' or '.' or '!' or '=' or '<' or '>' or '(' or ')' or ',' or ';' or '"' or '\'';

    private char Peek()
    {
        while (_position < _text.Length && char.IsWhiteSpace(_text[_position])) { _position++; }
        return _position < _text.Length ? _text[_position] : '\0';
    }
}
