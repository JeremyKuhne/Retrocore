// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

/// <summary>
///  Enumerates validated operand slices without splitting quoted or parenthesized commas.
/// </summary>
/// <remarks>
///  <para>
///   Validation is lazy: consumers must exhaust the cursor to detect malformed trailing operands. A comma
///   separates items only outside literals and at parenthesis depth zero.
///  </para>
/// </remarks>
internal ref struct AssemblyOperands
{
    private readonly ReadOnlyMemory<char> _text;
    private readonly int _line;
    private int _position;

    /// <summary>
    ///  Creates a directive operand cursor.
    /// </summary>
    /// <param name="text">The complete operands.</param>
    /// <param name="line">The diagnostic statement index.</param>
    internal AssemblyOperands(ReadOnlyMemory<char> text, int line)
    {
        _text = text;
        _line = line;
        _position = 0;
        Current = default;
    }

    /// <summary>
    ///  Gets the current trimmed operand.
    /// </summary>
    public ReadOnlyMemory<char> Current { get; private set; }

    /// <summary>
    ///  Gets a value-copy cursor.
    /// </summary>
    /// <returns>The cursor.</returns>
    public readonly AssemblyOperands GetEnumerator() => this;

    /// <summary>
    ///  Advances to the next operand and diagnoses malformed lists.
    /// </summary>
    /// <returns>Whether an operand remains.</returns>
    public bool MoveNext()
    {
        ReadOnlySpan<char> span = _text.Span;

        // Equality still attempts an empty final item, so a trailing comma is an error rather than end of input.
        if (_position > span.Length) { return false; }
        int start = _position;
        int end = start;
        int depth = 0;
        char quote = '\0';
        for (; end < span.Length; end++)
        {
            char value = span[end];
            if (AssemblySyntax.TogglesQuote(span, end, quote)) { quote = quote == '\0' ? value : '\0'; }
            if (quote != '\0') { continue; }
            if (value == '(') { depth++; }
            else if (value == ')') { depth--; }
            else if (value == ',' && depth == 0) { break; }
            if (depth < 0) { throw new AssemblyError(_line, "Unbalanced operand parentheses."); }
        }

        Current = _text[start..end].Trim();
        if (depth != 0 || quote != '\0' || Current.IsEmpty)
        {
            throw new AssemblyError(_line, "Empty or unbalanced directive operands.");
        }

        // Advancing beyond Length after the final item distinguishes completion from an empty trailing item.
        _position = end + 1;
        return true;
    }
}
