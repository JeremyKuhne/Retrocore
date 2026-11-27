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
    ///  <c>Aux = stores from an auxiliary byte; keeps A</c>, <c>; keeps X, Y</c> or <c>; keeps nothing</c>: the
    ///  items, in place of the routine's <c>Keeps:</c> for a call there, split at commas and "and", each without a
    ///  note in parentheses, a final period dropped. Null where the meaning has no such clause, so the routine's <c>Keeps:</c> applies.
    /// </summary>
    public IReadOnlyList<string>? Keeps
    {
        get
        {
            int clause = Meaning.LastIndexOf(KeepsClause, StringComparison.OrdinalIgnoreCase);
            if (clause < 0) { return null; }
            string items = Meaning[(clause + KeepsClause.Length)..].Trim().TrimEnd('.');
            if (items.Equals("nothing", StringComparison.OrdinalIgnoreCase)) { return []; }
            // "and" separates items as commas do.
            for (int and; (and = items.IndexOf(" and ", StringComparison.OrdinalIgnoreCase)) >= 0;)
            {
                items = $"{items[..and]},{items[(and + 5)..]}";
            }

            List<string> kept = [];
            foreach (string item in items.Split(','))
            {
                // A note in parentheses may follow an item, as in Keeps:: "Y (for a sound channel)".
                string name = item.Trim();
                int note = name.IndexOf(" (", StringComparison.Ordinal);
                if (note > 0 && name[^1] == ')') { name = name[..note]; }
                if (name.Length != 0) { kept.Add(name); }
            }

            return kept;
        }
    }
}
