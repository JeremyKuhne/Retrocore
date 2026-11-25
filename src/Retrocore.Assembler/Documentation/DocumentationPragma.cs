// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Documentation;

/// <summary>
///  The documentation lint's words of a <c>; retrocore:</c> pragma comment: <c>style=strict</c>, and
///  <c>ignore=</c> with the rules to turn off. Text after <c> -- </c> is the reason, which the tools ignore.
/// </summary>
/// <param name="Strict">Whether it has <c>style=strict</c>.</param>
/// <param name="Ignores">
///  Each rule an <c>ignore=</c> names, with the names it is narrowed to (none for all) and whether a colon was written
///  to narrow it.
/// </param>
public sealed record DocumentationPragma(
    bool Strict,
    IReadOnlyList<(string Rule, IReadOnlyList<string> Names, bool Narrowed)> Ignores)
{
    /// <summary>
    ///  Gets whether an <c>ignore=</c> word names no rule at all.
    /// </summary>
    public bool EmptyIgnore { get; init; }

    /// <summary>
    ///  The words that start a pragma comment.
    /// </summary>
    public const string Prefix = "; retrocore:";

    /// <summary>
    ///  The word that starts an exclusion, before its rules.
    /// </summary>
    public const string IgnoreWord = "ignore=";

    /// <summary>
    ///  The separator before an exclusion's reason.
    /// </summary>
    public const string ReasonSeparator = " -- ";

    /// <summary>
    ///  Reads a comment as a pragma.
    /// </summary>
    /// <param name="comment">The comment, from its semicolon.</param>
    /// <returns>The pragma, or null when the comment is not one.</returns>
    public static DocumentationPragma? Read(string comment)
    {
        string text = comment.Trim();
        if (!text.StartsWith(Prefix, StringComparison.OrdinalIgnoreCase)) { return null; }
        bool strict = false;
        bool empty = false;
        List<(string, IReadOnlyList<string>, bool)> ignores = [];
        foreach (string word in Words(text))
        {
            if (word.Equals("style=strict", StringComparison.OrdinalIgnoreCase))
            {
                strict = true;
            }
            else if (word.StartsWith(IgnoreWord, StringComparison.OrdinalIgnoreCase))
            {
                if (word.Length == IgnoreWord.Length) { empty = true; }
                foreach (string item in word[IgnoreWord.Length..].Split([','], StringSplitOptions.RemoveEmptyEntries))
                {
                    int colon = item.IndexOf(':');
                    string rule = colon < 0 ? item : item[..colon];
                    IReadOnlyList<string> names = colon < 0
                        ? []
                        : item[(colon + 1)..].Split(['|'], StringSplitOptions.RemoveEmptyEntries);

                    ignores.Add((rule, names, colon >= 0));
                }
            }
        }

        return new(strict, ignores) { EmptyIgnore = empty };
    }

    /// <summary>
    ///  Gets a pragma comment's words, after <c>; retrocore:</c> and before the reason.
    /// </summary>
    /// <param name="comment">The pragma comment, from its semicolon.</param>
    /// <returns>The words.</returns>
    public static string[] Words(string comment)
    {
        string text = comment.Trim();
        text = text.StartsWith(Prefix, StringComparison.OrdinalIgnoreCase) ? text[Prefix.Length..] : text;
        int reason = text.IndexOf(ReasonSeparator, StringComparison.Ordinal);
        if (reason >= 0) { text = text[..reason]; }
        return text.Split([' ', '\t'], StringSplitOptions.RemoveEmptyEntries);
    }

    /// <summary>
    ///  Gets whether a comment is a pragma with an <c>ignore=</c> word.
    /// </summary>
    /// <param name="comment">The comment, from its semicolon.</param>
    /// <returns>Whether it holds an exclusion.</returns>
    public static bool HasIgnore(string comment) =>
        comment.TrimStart().StartsWith(Prefix, StringComparison.OrdinalIgnoreCase)
            && Words(comment).Any(word => word.StartsWith(IgnoreWord, StringComparison.OrdinalIgnoreCase));
}
