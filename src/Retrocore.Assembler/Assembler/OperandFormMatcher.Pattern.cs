// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Isa;

namespace Retrocore.Assembler;

internal sealed partial class OperandFormMatcher
{
    /// <summary>
    ///  A pattern split at its holes.
    /// </summary>
    private sealed class Pattern
    {
        /// <summary>
        ///  Splits a pattern.
        /// </summary>
        /// <param name="text">The pattern.</param>
        /// <param name="form">The form that declares it, whose fields say which holes are displacements.</param>
        internal Pattern(string text, OperandForm form)
        {
            Text = text;
            List<string> literals = [];
            int start = 0;
            int hole = text.IndexOf("{}", StringComparison.Ordinal);
            while (hole >= 0)
            {
                literals.Add(text[start..hole]);
                start = hole + 2;
                hole = text.IndexOf("{}", start, StringComparison.Ordinal);
            }

            literals.Add(text[start..]);
            Literals = [.. literals];
            _first = Literals[0];
            _last = Literals[^1];
            Holes = Literals.Length - 1;
            if (Holes > MaximumHoles)
            {
                throw new FormatException($"Pattern \"{text}\" has more than {MaximumHoles} holes.");
            }

            Displacement = new bool[Math.Max(Holes, 1)];

            // Each hole holds one field when the counts agree; one hole may hold a field list.
            for (int index = 0; index < Holes && Holes == form.FieldCount; index++)
            {
                Displacement[index] = form.Field(index) == OperandFieldKind.Displacement8;
            }

            Grouped = text.IndexOfAny(['(', '[']) >= 0;
        }

        /// <summary>
        ///  Gets the whole pattern.
        /// </summary>
        internal string Text { get; }

        /// <summary>
        ///  Gets the literal text around the holes: one more than <see cref="Holes"/>.
        /// </summary>
        internal string[] Literals { get; }

        /// <summary>
        ///  Gets the number of holes.
        /// </summary>
        internal int Holes { get; }

        /// <summary>
        ///  Gets, for each hole, whether it is a signed displacement.
        /// </summary>
        internal bool[] Displacement { get; }

        /// <summary>
        ///  Gets whether the pattern has a parenthesis or bracket, so each expression must balance its own.
        /// </summary>
        internal bool Grouped { get; }

        /// <summary>
        ///  Gets whether an operand has the pattern's syntax, without finding its holes.
        /// </summary>
        /// <param name="text">The compact operand.</param>
        /// <returns>Whether it matches.</returns>
        /// <remarks>
        ///  <para>
        ///   Classification tries many patterns per instruction; one hole, as every 6502 pattern has, needs no
        ///   search for the literal text between holes.
        ///  </para>
        /// </remarks>
        internal bool Matches(ReadOnlySpan<char> text)
        {
            if (Holes != 1)
            {
                Span<Range> holes = stackalloc Range[MaximumHoles];
                return Match(text, holes);
            }

            string first = _first;
            string last = _last;
            if (text.Length < first.Length + last.Length
                || !text.StartsWith(first.AsSpan(), StringComparison.OrdinalIgnoreCase)
                || !text.EndsWith(last.AsSpan(), StringComparison.OrdinalIgnoreCase))
            {
                return false;
            }

            ReadOnlySpan<char> expression = text[first.Length..(text.Length - last.Length)];
            return (!Grouped || IsBalanced(expression))
                && (!Displacement[0] || expression.IsEmpty || expression[0] is '+' or '-');
        }

        private readonly string _first;
        private readonly string _last;

        /// <summary>
        ///  Matches an operand, finding each hole's expression.
        /// </summary>
        /// <param name="text">The compact operand.</param>
        /// <param name="holes">Receives each hole's range.</param>
        /// <returns>Whether the operand has the pattern's syntax.</returns>
        internal bool Match(ReadOnlySpan<char> text, Span<Range> holes)
        {
            string first = _first;
            string last = _last;
            if (text.Length < first.Length + last.Length
                || !text.StartsWith(first.AsSpan(), StringComparison.OrdinalIgnoreCase)
                || !text.EndsWith(last.AsSpan(), StringComparison.OrdinalIgnoreCase))
            {
                return false;
            }

            int position = first.Length;
            int end = text.Length - last.Length;
            for (int index = 0; index < Holes; index++)
            {
                int close = end;
                if (index < Holes - 1)
                {
                    close = FindLiteral(text, position, end, Literals[index + 1]);
                    if (close < 0) { return false; }
                }

                ReadOnlySpan<char> expression = text[position..close];
                if (Grouped && !IsBalanced(expression)) { return false; }
                if (Displacement[index] && !expression.IsEmpty && expression[0] is not ('+' or '-')) { return false; }
                holes[index] = position..close;
                position = close + (index < Holes - 1 ? Literals[index + 1].Length : 0);
            }

            return true;
        }
    }
}
