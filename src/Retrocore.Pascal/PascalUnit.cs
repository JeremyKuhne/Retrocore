// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

/// <summary>
///  A unit as its interface declares it: its procedures, numbered as calls name them, and its enumerated types.
/// </summary>
/// <param name="Name">Its segment's name, up to eight characters, such as <c>TURTLEGR</c>.</param>
/// <param name="Segment">Its segment number, which <c>CXP</c> calls it by.</param>
/// <param name="Procedures">Its procedures and functions, the first numbered 2.</param>
/// <param name="Enumerations">Its enumerated types, by name, each with its values' names in order.</param>
public sealed record PascalUnit(
    string Name,
    int Segment,
    IReadOnlyList<PascalUnitProcedure> Procedures,
    IReadOnlyDictionary<string, IReadOnlyList<string>> Enumerations)
{
    // The names Apple's units are known by, whose segments keep eight characters.
    private static readonly Dictionary<string, string> s_fullNames = new(StringComparer.OrdinalIgnoreCase)
    {
        ["TURTLEGR"] = "TURTLEGRAPHICS",
        ["APPLESTU"] = "APPLESTUFF",
        ["TRANSCEN"] = "TRANSCEND",
        ["CHAINSTU"] = "CHAINSTUFF",
        ["LONGINTI"] = "LONGINTIO"
    };

    /// <summary>
    ///  Gets the name a program's <c>USES</c> names it by: Apple's units by their full names, such as
    ///  <c>TURTLEGRAPHICS</c>; the compiler reads only eight characters, so either names it.
    /// </summary>
    public string UsesName => s_fullNames.TryGetValue(Name, out string? full) ? full : Name;

    /// <summary>
    ///  Gets a procedure by the number calls name it by.
    /// </summary>
    /// <param name="number">The number, from 2.</param>
    /// <returns>The procedure, or null.</returns>
    public PascalUnitProcedure? Procedure(int number) =>
        number >= 2 && number - 2 < Procedures.Count ? Procedures[number - 2] : null;

    /// <summary>
    ///  Reads a unit's interface text.
    /// </summary>
    /// <param name="name">The unit's segment name.</param>
    /// <param name="segment">Its segment number.</param>
    /// <param name="text">The interface text.</param>
    /// <returns>The unit.</returns>
    public static PascalUnit Parse(string name, int segment, string text)
    {
        ArgumentNullException.ThrowIfNull(text);
        List<string> tokens = Tokens(text);
        List<PascalUnitProcedure> procedures = [];
        Dictionary<string, IReadOnlyList<string>> enumerations = new(StringComparer.OrdinalIgnoreCase);
        int at = 0;
        while (at < tokens.Count)
        {
            string token = tokens[at];
            if (Is(token, "PROCEDURE") || Is(token, "FUNCTION"))
            {
                procedures.Add(Header(tokens, ref at));
            }
            else if (at + 2 < tokens.Count && tokens[at + 1] == "=" && tokens[at + 2] == "(")
            {
                // An enumerated type: NAME = (A, B, C).
                List<string> values = [];
                at += 3;
                while (at < tokens.Count && tokens[at] != ")")
                {
                    if (tokens[at] != ",") { values.Add(tokens[at].ToUpperInvariant()); }
                    at++;
                }

                enumerations[token.ToUpperInvariant()] = values;
                at++;
            }
            else
            {
                at++;
            }
        }

        return new PascalUnit(name, segment, procedures, enumerations);
    }

    // PROCEDURE NAME(A, B: T; VAR C: U); or FUNCTION NAME(...): T;
    private static PascalUnitProcedure Header(List<string> tokens, ref int at)
    {
        bool function = Is(tokens[at++], "FUNCTION");
        string name = at < tokens.Count ? tokens[at++].ToUpperInvariant() : "";
        List<PascalUnitParameter> parameters = [];
        if (at < tokens.Count && tokens[at] == "(")
        {
            at++;
            while (at < tokens.Count && tokens[at] != ")")
            {
                bool reference = Is(tokens[at], "VAR");
                if (reference) { at++; }

                List<string> names = [];
                while (at < tokens.Count && tokens[at] is not (":" or ";" or ")"))
                {
                    if (tokens[at] != ",") { names.Add(tokens[at].ToUpperInvariant()); }
                    at++;
                }

                // An untyped VAR parameter, such as DRAWBLOCK's SOURCE, has no type.
                string? type = null;
                if (at < tokens.Count && tokens[at] == ":")
                {
                    at++;
                    type = at < tokens.Count ? tokens[at++].ToUpperInvariant() : null;
                }

                parameters.AddRange(names.Select(parameter => new PascalUnitParameter(parameter, reference, type)));
                if (at < tokens.Count && tokens[at] == ";") { at++; }
            }

            at++;
        }

        string? result = null;
        if (function && at + 1 < tokens.Count && tokens[at] == ":")
        {
            result = tokens[at + 1].ToUpperInvariant();
            at += 2;
        }

        return new PascalUnitProcedure(name, function, parameters, result);
    }

    private static bool Is(string token, string word) => string.Equals(token, word, StringComparison.OrdinalIgnoreCase);

    // Identifiers and numbers, and single punctuation; comments in braces or (* *) are skipped.
    private static List<string> Tokens(string text)
    {
        List<string> tokens = [];
        int at = 0;
        while (at < text.Length)
        {
            char character = text[at];
            if (char.IsWhiteSpace(character))
            {
                at++;
            }
            else if (character == '{')
            {
                int end = text.IndexOf('}', at);
                at = end < 0 ? text.Length : end + 1;
            }
            else if (character == '(' && at + 1 < text.Length && text[at + 1] == '*')
            {
                int end = text.IndexOf("*)", at + 2, StringComparison.Ordinal);
                at = end < 0 ? text.Length : end + 2;
            }
            else if (char.IsLetterOrDigit(character) || character == '_')
            {
                int start = at;
                while (at < text.Length && (char.IsLetterOrDigit(text[at]) || text[at] == '_')) { at++; }
                tokens.Add(text[start..at]);
            }
            else
            {
                tokens.Add(character.ToString());
                at++;
            }
        }

        return tokens;
    }
}
