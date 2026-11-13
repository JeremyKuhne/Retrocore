// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Basic;

/// <summary>
///  Help for each dialect's reserved words: how each is written and what it does.
/// </summary>
public static class BasicKeywordHelp
{
    private static readonly Lazy<List<(string Word, string Dialects, string Syntax, string Summary)>> s_entries = new(Load);

    /// <summary>
    ///  Describes a reserved word.
    /// </summary>
    /// <param name="dialect">The dialect.</param>
    /// <param name="keyword">The word, as the dialect's <see cref="BasicDialect.Keywords"/> spells it.</param>
    /// <returns>Its syntax and summary, or null when there is no help for it.</returns>
    public static (string Syntax, string Summary)? Describe(BasicDialect dialect, string keyword)
    {
        ArgumentNullException.ThrowIfNull(dialect);
        char code = dialect.Name switch
        {
            "level2" => '2',
            "integer" or "apple1" => 'i',
            "business" => 'b',
            _ => 'a'
        };

        foreach ((string word, string dialects, string syntax, string summary) in s_entries.Value)
        {
            if (word == keyword && dialects.Contains(code, StringComparison.Ordinal)) { return (syntax, summary); }
        }

        return null;
    }

    /// <summary>
    ///  Describes a reserved word as Markdown, for hover and completion.
    /// </summary>
    /// <param name="dialect">The dialect.</param>
    /// <param name="keyword">The word.</param>
    /// <returns>The Markdown, or null when there is no help for it.</returns>
    public static string? Markdown(BasicDialect dialect, string keyword) =>
        Describe(dialect, keyword) is { } help ? $"```\n{help.Syntax}\n```\n{help.Summary}" : null;

    private static List<(string, string, string, string)> Load()
    {
        using Stream stream = typeof(BasicKeywordHelp).Assembly.GetManifestResourceStream("Retrocore.Basic.Keywords.txt")
            ?? throw new InvalidOperationException("The keyword help is missing from the assembly.");

        using StreamReader reader = new(stream);
        List<(string, string, string, string)> entries = [];
        while (reader.ReadLine() is { } line)
        {
            if (line.Length == 0 || line.StartsWith("# ", StringComparison.Ordinal)) { continue; }
            string[] fields = line.Split('|', 4);
            entries.Add((fields[0], fields[1], fields[2], fields[3]));
        }

        return entries;
    }
}
