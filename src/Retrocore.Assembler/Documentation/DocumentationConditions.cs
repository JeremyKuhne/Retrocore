// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Documentation;

/// <summary>
///  Evaluates the <c>.if</c> conditions documentation sections are written under, from a build's symbols.
/// </summary>
internal static class DocumentationConditions
{
    /// <summary>
    ///  Gets whether a section's <c>.if</c> condition holds for the build an assembly's symbols come from: each part of
    ///  it ("MONITOR = MONITOR_IIE and not ENHANCED") is evaluated from those symbols, and an <c>.ifdef</c>'s
    ///  "defined NAME" by whether the build defines the name, as a symbol or a macro. A part they can't decide holds.
    /// </summary>
    /// <param name="condition">The section's condition, or null for one that always applies.</param>
    /// <param name="symbols">The build's symbols; with none, every condition holds.</param>
    /// <param name="isDefined">Whether a name is defined as an <c>.ifdef</c> sees it: a symbol or a macro.</param>
    /// <returns>Whether the section is in the build.</returns>
    internal static bool InBuild(string? condition, IReadOnlyDictionary<string, long> symbols, Func<string, bool> isDefined)
    {
        if (condition is null || symbols.Count == 0) { return true; }
        long? Symbol(string name) => symbols.TryGetValue(name, out long value) ? value : null;
        foreach (string untrimmed in condition.Split([" and "], StringSplitOptions.None))
        {
            string part = untrimmed.Trim();
            bool not = part.StartsWith("not ", StringComparison.OrdinalIgnoreCase);
            string test = not ? part[4..].Trim() : part;
            bool? holds = Holds(test, Symbol);
            if (test.StartsWith("defined ", StringComparison.Ordinal))
            {
                holds = isDefined(test["defined ".Length..].Trim());
            }

            if (holds == not) { return false; }
        }

        return true;
    }

    /// <summary>
    ///  Evaluates an <c>.if</c> operand of comparisons joined by <c>&amp;&amp;</c> and <c>||</c>, negated by
    ///  <c>.not</c> and grouped by parentheses.
    /// </summary>
    /// <param name="test">The operand.</param>
    /// <param name="symbol">The build's value of a symbol, or null when it does not define it.</param>
    /// <returns>Whether it holds, or null when it can't be decided.</returns>
    internal static bool? Holds(string test, Func<string, long?> symbol)
    {
        int at = 0;
        bool? value = Either(test, ref at, symbol);
        return at == test.Length ? value : null;
    }

    // Tests joined by ||, up to a closing parenthesis or the end.
    private static bool? Either(string text, ref int at, Func<string, long?> symbol)
    {
        bool? any = Both(text, ref at, symbol);
        while (Take(text, ref at, "||"))
        {
            bool? next = Both(text, ref at, symbol);
            any = any == true || next == true ? true : any is null || next is null ? null : false;
        }

        return any;
    }

    // Tests joined by &&.
    private static bool? Both(string text, ref int at, Func<string, long?> symbol)
    {
        bool? all = Test(text, ref at, symbol);
        while (Take(text, ref at, "&&"))
        {
            bool? next = Test(text, ref at, symbol);
            all = all == false || next == false ? false : all is null || next is null ? null : true;
        }

        return all;
    }

    // A parenthesized group, a negated test (.not, or ! in the dialects that have it), or a comparison running to the
    // next &&, || or closing parenthesis.
    private static bool? Test(string text, ref int at, Func<string, long?> symbol)
    {
        while (at < text.Length && text[at] == ' ') { at++; }
        if (Take(text, ref at, ".not ") || (Ahead(text, at, "!") && !Ahead(text, at, "!=") && Take(text, ref at, "!")))
        {
            return Test(text, ref at, symbol) is { } inner ? !inner : null;
        }

        if (Take(text, ref at, "("))
        {
            bool? group = Either(text, ref at, symbol);
            return Take(text, ref at, ")") ? group : null;
        }

        int start = at;
        while (at < text.Length && text[at] != ')' && !Ahead(text, at, "&&") && !Ahead(text, at, "||"))
        {
            at += IsCharacter(text, at) ? 3 : 1;
        }

        return Comparison(text[start..at], symbol);
    }

    // Skips spaces, then the token if it is next.
    private static bool Take(string text, ref int at, string token)
    {
        while (at < text.Length && text[at] == ' ') { at++; }
        if (!Ahead(text, at, token)) { return false; }
        at += token.Length;
        while (at < text.Length && text[at] == ' ') { at++; }
        return true;
    }

    private static bool Ahead(string text, int at, string token) =>
        string.CompareOrdinal(text, at, token, 0, token.Length) == 0;

    private static bool? Comparison(string text, Func<string, long?> symbol)
    {
        foreach (string op in (string[])["!=", "<=", ">=", "==", "=", "<", ">"])
        {
            int at = OperatorAt(text, op);
            if (at <= 0) { continue; }
            long? left = Operand(text[..at], symbol);
            long? right = Operand(text[(at + op.Length)..], symbol);
            return left is { } known && right is { } other ? Compare(op, known, other) : null;
        }

        // A bare symbol holds when it is nonzero.
        return Operand(text, symbol) is { } value ? value != 0 : null;
    }

    private static bool Compare(string op, long left, long right) => op switch
    {
        "!=" => left != right,
        "<=" => left <= right,
        ">=" => left >= right,
        "<" => left < right,
        ">" => left > right,
        _ => left == right
    };

    // Where an operator first appears outside character literals, or -1.
    private static int OperatorAt(string text, string op)
    {
        for (int at = 0; at < text.Length; at += IsCharacter(text, at) ? 3 : 1)
        {
            if (Ahead(text, at, op)) { return at; }
        }

        return -1;
    }

    // Whether a character literal, such as 'B', starts here.
    private static bool IsCharacter(string text, int at) =>
        text[at] == '\'' && at + 2 < text.Length && text[at + 2] == '\'';

    private static long? Operand(string text, Func<string, long?> symbol)
    {
        string trimmed = text.Trim();
        if (trimmed.Length == 3 && trimmed[0] == '\'' && trimmed[2] == '\'') { return trimmed[1]; }
        if (trimmed.StartsWith('$') && long.TryParse(trimmed[1..], System.Globalization.NumberStyles.HexNumber, provider: null, out long hex))
        {
            return hex;
        }

        if (long.TryParse(trimmed, out long number)) { return number; }
        bool name = trimmed.Length != 0 && (char.IsLetter(trimmed[0]) || trimmed[0] == '_');
        return name ? symbol(trimmed) : null;
    }
}
