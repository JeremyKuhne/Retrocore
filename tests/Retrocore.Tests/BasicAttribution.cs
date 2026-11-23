// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.RegularExpressions;

namespace Retrocore.Tests;

/// <summary>
///  Finds the vendor names the shared BASIC sources attribute to a routine in their remarks, one sentence per
///  variant: "In PET BASIC 4, Commodore's 1979 source calls it `TENC` (code19)."
/// </summary>
/// <remarks>
///  <para>
///   The sentences stand in for <c>Also:</c> entries until <c>Also:</c> is read inside macro bodies. The variant,
///   the name and the source that gives it must all be in one sentence.
///  </para>
/// </remarks>
internal static partial class BasicAttribution
{
    /// <summary>
    ///  Gets whether a sentence of the remarks attributes a name to one of the variants and cites its source.
    /// </summary>
    /// <param name="remarks">The comment's remark paragraphs, as the documentation parser gives them.</param>
    /// <param name="name">The vendor's name for the routine.</param>
    /// <param name="variants">
    ///  The variants that may give it, as <c>AppleSoft</c>, <c>PET BASIC 4</c> or <c>PET BASIC 1/2</c>.
    /// </param>
    /// <param name="prefix">Whether a variant matches any variant that starts with it, as <c>PET BASIC</c>.</param>
    /// <returns>Whether such a sentence is present.</returns>
    internal static bool Has(IEnumerable<string> remarks, string name, IReadOnlyCollection<string> variants, bool prefix = false)
    {
        string marker = $"`{name}`";
        foreach (string sentence in Sentences(remarks))
        {
            Match match = Attribution().Match(sentence);
            if (!match.Success) { continue; }

            string variant = match.Groups["variant"].Value.Replace(" and ", "/", StringComparison.Ordinal);
            bool known = variants.Any(candidate => prefix
                ? variant.StartsWith(candidate, StringComparison.OrdinalIgnoreCase)
                : variant.Equals(candidate, StringComparison.OrdinalIgnoreCase));

            if (known && match.Groups["rest"].Value.Contains(marker, StringComparison.Ordinal)) { return true; }
        }

        return false;
    }

    // The remarks are one entry per source line, with an empty entry between paragraphs. Each attribution starts a
    // sentence or clause with "In <variant>,", so a new one starts at ". In " or "; in ".
    private static IEnumerable<string> Sentences(IEnumerable<string> remarks)
    {
        List<string> paragraphs = [""];
        foreach (string line in remarks)
        {
            if (line.Trim().Length == 0) { paragraphs.Add(""); continue; }
            paragraphs[^1] = $"{paragraphs[^1]} {line.Trim()}".TrimStart();
        }

        return paragraphs.SelectMany(paragraph => SentenceBreak().Split(paragraph));
    }

    // "In <variant>, <source> call(s) ... `NAME` ...": the source is the text before "calls" and must not be empty.
    [GeneratedRegex(@"^[Ii]n (?<variant>(?:AppleSoft|PET BASIC [0-9](?: and [0-9])?)), (?<source>\S.*?) calls? (?<rest>.*)$")]
    private static partial Regex Attribution();

    [GeneratedRegex(@"(?<=[.;])\s+(?=[Ii]n )")]
    private static partial Regex SentenceBreak();
}
