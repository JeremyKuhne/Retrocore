// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

internal sealed partial class AssemblyLinker
{
    private char Peek()
    {
        while (_position < _text.Length)
        {
            if (char.IsWhiteSpace(_text[_position]))
            {
                _position++;
            }
            else if (_text[_position] == '#')
            {
                while (_position < _text.Length && _text[_position] != '\n') { _position++; }
            }
            else
            {
                return _text[_position];
            }
        }

        return '\0';
    }

    private void Expect(char value)
    {
        if (Peek() != value) { throw Failure($"Expected '{value}' in linker configuration."); }
        _position++;
    }

    private string Token()
    {
        Peek();
        int start = _position;
        while (_position < _text.Length && AssemblySyntax.IsWord(_text[_position])) { _position++; }
        return start == _position ? throw Failure("Expected a linker identifier.") : _text[start.._position];
    }

    private string Value()
    {
        Peek();
        int start = _position;
        int depth = 0;
        bool quoted = false;
        while (_position < _text.Length)
        {
            char character = _text[_position];
            if (character == '"') { quoted = !quoted; }
            if (!quoted)
            {
                if (character == '(') { depth++; }
                if (character == ')') { depth--; }
                if (character is ',' or ';' or '#' && depth == 0) { break; }
                if (character is '{' or '}') { throw Failure("Unterminated linker attribute."); }
                if (depth == 0 && char.IsWhiteSpace(character) && StartsAttribute(_position)) { break; }
            }

            _position++;
        }

        return quoted || depth != 0 || _position == _text.Length
            ? throw Failure("Unterminated linker attribute.")
            : _text[start.._position].Trim();
    }

    // Finds "name =" after whitespace, which starts the next attribute when its comma is omitted.
    private bool StartsAttribute(int position)
    {
        while (position < _text.Length && char.IsWhiteSpace(_text[position])) { position++; }
        int name = position;
        while (position < _text.Length && AssemblySyntax.IsWord(_text[position])) { position++; }
        if (position == name || !AssemblySyntax.IsIdentifierStart(_text[name])) { return false; }
        while (position < _text.Length && char.IsWhiteSpace(_text[position])) { position++; }
        return position < _text.Length && _text[position] == '=' && (position + 1 == _text.Length || _text[position + 1] != '=');
    }
}
