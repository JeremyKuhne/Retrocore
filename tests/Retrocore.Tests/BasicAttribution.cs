// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.RegularExpressions;
using Retrocore.Assembler;
using Retrocore.Documentation;
using Retrocore.Machines.Commodore;

namespace Retrocore.Tests;

/// <summary>
///  Checks the vendors' names for shared BASIC code: each is an alias in the vendor's own file, which cites the
///  documents that give it in the form of an <c>Also:</c> item, <c>SQR05 (CBM4S79, HV1)</c>, by their keys in
///  <c>docs/Bibliography.md</c>.
/// </summary>
/// <remarks>
///  <para>
///   A vendor's name can't be an <c>Also:</c> entry on the shared definition, which every build of every vendor
///   shares: it would resolve in the other vendor's builds too. Nor can it be one on the alias, whose own name it is.
///  </para>
/// </remarks>
internal static partial class BasicAttribution
{
    /// <summary>
    ///  Gets the documents that give each Commodore name for shared code, which are the same for every one.
    /// </summary>
    internal static string[] CommodoreKeys { get; } = ["CBM4S79", "HV1", "HV1R", "HV2", "HV4", "HV4R"];

    /// <summary>
    ///  Gets the SDK's bibliography, <c>docs/Bibliography.md</c>.
    /// </summary>
    internal static DocumentationBibliography Bibliography { get; } = ReadBibliography();

    /// <summary>
    ///  Gets the documents that give a PET build its Commodore names: its own reconstruction, and for BASIC 4,
    ///  Commodore's 1979 listing.
    /// </summary>
    /// <param name="model">The PET model.</param>
    /// <param name="original">Whether BASIC 1 or 4 uses its original chip.</param>
    /// <returns>The documents' keys.</returns>
    internal static string[] PetKeys(PetModel model, bool original) => model.BasicVersion() switch
    {
        1 => [original ? "HV1" : "HV1R"],
        2 => ["HV2"],
        4 => [original ? "HV4" : "HV4R", "CBM4S79"],
        int version => throw new AssertFailedException($"Unexpected PET BASIC version {version}.")
    };

    /// <summary>
    ///  Gets the documents a comment cites for a name, written as an <c>Also:</c> item is: the name, then the keys in
    ///  parentheses.
    /// </summary>
    /// <param name="remarks">The comment's summary and remarks, one entry per source line.</param>
    /// <param name="name">The name.</param>
    /// <returns>The keys, or null when no citation of the name has any.</returns>
    internal static IReadOnlyList<string>? Citation(IEnumerable<string> remarks, string name)
    {
        string text = string.Join(" ", remarks.Select(line => line.Trim()));
        foreach (Match match in Cited().Matches(text))
        {
            if (match.Groups["name"].Value != name) { continue; }
            if (DocumentationAlso.Parse(match.Value) is { Sources.Count: > 0 } also) { return also.Sources; }
        }

        return null;
    }

    /// <summary>
    ///  Asserts that a vendor's alias cites the documents that give its name, that every key is in the bibliography,
    ///  and that the build's own documents are among them.
    /// </summary>
    /// <param name="alias">The alias's documentation.</param>
    /// <param name="build">The documents that cover the build being checked.</param>
    /// <param name="expected">Every document that gives the name, or null to check only the build's.</param>
    /// <param name="target">The definition the alias names, which its documentation must link to, or null.</param>
    internal static void AssertCites(
        DocumentationTopic alias,
        IReadOnlyCollection<string> build,
        IReadOnlyCollection<string>? expected = null,
        string? target = null)
    {
        IReadOnlyList<string> keys = Citation([alias.Summary, .. alias.Remarks], alias.Name)
            ?? throw new AssertFailedException($"{alias.Name}'s documentation must cite its documents, as '{alias.Name} (KEY)'.");

        if (target is not null)
        {
            string.Join(" ", [alias.Summary, .. alias.Remarks]).Should().Contain($"<{target}>", $"{alias.Name}'s documentation must name the definition it aliases");
        }

        foreach (string key in keys)
        {
            Bibliography.Find(key).Should().NotBeNull($"{alias.Name} cites {key}, which must be in docs/Bibliography.md");
        }

        keys.Should().Contain(build, $"{alias.Name} must cite the documents that give it in this build");
        if (expected is not null)
        {
            keys.Should().BeEquivalentTo(expected, $"{alias.Name} must cite every document that gives it");
        }
    }

    /// <summary>
    ///  Asserts that a vendor's name for shared code is no historical name of a shared definition, which would make it
    ///  resolve in every vendor's builds.
    /// </summary>
    /// <param name="result">A build.</param>
    /// <param name="docs">The build's documentation.</param>
    /// <param name="name">The vendor's name.</param>
    internal static void AssertNotShared(AssemblyResult result, DocumentationSet docs, string name)
    {
        result.HistoricalNames.Should().NotContainKey(name, $"{name} must resolve only through its vendor's alias");
        Regex word = new($@"(?<![\w$]){Regex.Escape(name)}(?![\w$])");
        foreach (DocumentationTopic topic in SharedTopics(docs))
        {
            DocumentationAlso.Of(topic.Sections).Select(also => also.Name)
                .Should().NotContain(name, $"{topic.Name} is shared, so its Also: must not give the vendor's {name}");

            word.IsMatch(string.Join(" ", topic.Comments.SelectMany(Text)))
                .Should().BeFalse($"{topic.Name} is shared, so its documentation must not give the vendor's {name}");
        }
    }

    /// <summary>
    ///  Asserts that every historical name a shared definition gives is Microsoft's, which every build shares: a name
    ///  only a vendor's documents give belongs in that vendor's own file.
    /// </summary>
    /// <param name="docs">A build's documentation.</param>
    internal static void AssertSharedNamesAreMicrosofts(DocumentationSet docs)
    {
        foreach (DocumentationTopic topic in SharedTopics(docs))
        {
            foreach (DocumentationAlso also in DocumentationAlso.Of(topic.Sections))
            {
                also.Sources.Should().Contain("M6502", $"{topic.Name} is shared, so {also.Name} must be Microsoft's name");
            }
        }
    }

    /// <summary>
    ///  Gets whether a sentence of the remarks attributes a name to one of the variants and cites its source, for a
    ///  vendor's name that can't resolve at all: one that is already another definition's name in that build, as
    ///  AppleSoft's COPY and GARBAG are. "In AppleSoft, Apple Computer, in The Apple Orchard, calls it `GARBAG`."
    /// </summary>
    /// <param name="remarks">The comment's remark paragraphs, as the documentation parser gives them.</param>
    /// <param name="name">The vendor's name for the routine.</param>
    /// <param name="variant">The variant that gives it, as <c>AppleSoft</c>.</param>
    /// <returns>Whether such a sentence is present.</returns>
    internal static bool Has(IEnumerable<string> remarks, string name, string variant)
    {
        string marker = $"`{name}`";
        foreach (string sentence in Sentences(remarks))
        {
            Match match = Attribution().Match(sentence);
            if (match.Success
                && match.Groups["variant"].Value.Equals(variant, StringComparison.OrdinalIgnoreCase)
                && match.Groups["rest"].Value.Contains(marker, StringComparison.Ordinal))
            {
                return true;
            }
        }

        return false;
    }

    // A comment's text: its summary, remarks and sections, in each of the comments a topic merges.
    private static string[] Text(DocumentationComment comment) =>
        [comment.Summary, .. comment.Remarks, .. comment.Sections.Select(section => section.Text)];

    // The build's definitions documented in the shared Microsoft modules, of which every build has some.
    private static List<DocumentationTopic> SharedTopics(DocumentationSet docs)
    {
        List<DocumentationTopic> shared = [.. docs.Topics.Where(IsShared)];
        shared.Should().NotBeEmpty("the build must include the shared Microsoft modules' documentation");
        return shared;
    }

    // Whether a definition is documented in the shared Microsoft modules.
    private static bool IsShared(DocumentationTopic topic)
    {
        string shared = $"{Path.DirectorySeparatorChar}Microsoft6502Basic{Path.DirectorySeparatorChar}";
        return topic.Comments.Any(comment => comment.Path.Contains(shared, StringComparison.OrdinalIgnoreCase));
    }

    private static DocumentationBibliography ReadBibliography()
    {
        string? root = AppContext.BaseDirectory;
        while (root is not null && !File.Exists(Path.Join(root, "docs", "Bibliography.md")))
        {
            root = Path.GetDirectoryName(root);
        }

        string folder = root ?? throw new AssertFailedException("docs/Bibliography.md was not found above the test's folder.");
        return DocumentationBibliography.Parse(File.ReadAllText(Path.Join(folder, "docs", "Bibliography.md")));
    }

    // The remarks are one entry per source line, with an empty entry between paragraphs. Each attribution starts a
    // sentence, or a clause after a semicolon, with "In <variant>,".
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

    // A name, not part of a longer one or a link, followed by its documents' keys: "SQR05 (CBM4S79, HV1)".
    [GeneratedRegex(@"(?<![\w$<])(?<name>[A-Za-z_][A-Za-z0-9_]*) \([^()]*\)")]
    private static partial Regex Cited();

    // "In <variant>, <source> call(s) ... `NAME` ...": the source is the text before "calls" and must not be empty.
    [GeneratedRegex(@"^[Ii]n (?<variant>AppleSoft), (?<source>\S.*?) calls? (?<rest>.*)$")]
    private static partial Regex Attribution();

    [GeneratedRegex(@"(?<=[.;])\s+(?=[Ii]n )")]
    private static partial Regex SentenceBreak();
}
