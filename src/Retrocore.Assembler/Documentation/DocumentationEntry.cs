// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Documentation;

/// <summary>
///  One entry of a section such as <c>In:</c>: a name and its meaning.
/// </summary>
/// <param name="Name">The register, flag, symbol or parameter.</param>
/// <param name="Meaning">What it means.</param>
/// <param name="Line">The zero-based source line.</param>
public sealed record DocumentationEntry(string Name, string Meaning, int Line)
{
    private const string KeepsClause = "; keeps ";

    /// <summary>
    ///  Gets what an <c>Entry:</c> label keeps where its meaning ends in a clause that says, as
    ///  <c>Aux = stores from an auxiliary byte; keeps A</c>, <c>; keeps X and Y</c> or <c>; keeps nothing</c>: the
    ///  items, in place of the routine's <c>Keeps:</c> for a call there. Items are split at commas and "and" outside
    ///  parentheses, each without its note in parentheses, and a final period is dropped. Null where the meaning has
    ///  no such clause, so the routine's <c>Keeps:</c> applies.
    /// </summary>
    public IReadOnlyList<string>? Keeps
    {
        get
        {
            int clause = Meaning.LastIndexOf(KeepsClause, StringComparison.OrdinalIgnoreCase);
            if (clause < 0) { return null; }
            string items = Meaning[(clause + KeepsClause.Length)..].Trim().TrimEnd('.');
            if (items.Equals("nothing", StringComparison.OrdinalIgnoreCase)) { return []; }

            // Commas and "and" outside parentheses separate items, as in "X (the index, or the count) and Y".
            List<string> kept = [];
            int depth = 0, start = 0;
            for (int index = 0; index <= items.Length; index++)
            {
                // The end closes the last item, even one whose note is left open; a stray ")" closes nothing.
                bool end = index == items.Length;
                char current = end ? ',' : items[index];
                if (current == '(') { depth++; }
                else if (current == ')') { depth = Math.Max(0, depth - 1); }

                int separator = 0;
                if (end || (depth == 0 && current == ',')) { separator = 1; }
                else if (depth == 0 && string.Compare(items, index, " and ", 0, 5, StringComparison.OrdinalIgnoreCase) == 0)
                {
                    separator = 5;
                }

                if (separator == 0) { continue; }
                Add(items[start..index]);
                start = index + separator;
                index = start - 1;
            }

            return kept;

            // An item without the note in parentheses that may follow it, as Keeps: has "Y (for a sound channel)".
            void Add(string item)
            {
                string name = item.Trim();
                int note = name.IndexOf(" (", StringComparison.Ordinal);
                if (note > 0 && name[^1] == ')') { name = name[..note]; }
                if (name.Length != 0) { kept.Add(name); }
            }
        }
    }
}
