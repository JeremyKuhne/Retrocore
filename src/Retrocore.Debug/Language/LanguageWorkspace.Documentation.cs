// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Documentation;

namespace Retrocore.Debug.Language;

internal sealed partial class LanguageWorkspace
{
    /// <summary>
    ///  Creates a resolver for an analysis's documentation, reaching the SDK's ROM sources as other modules.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   See <see cref="SourceAnalysis.OtherModules"/> for which SDK modules it reaches.
    ///  </para>
    /// </remarks>
    /// <param name="analysis">The analysis.</param>
    /// <returns>The resolver.</returns>
    internal DocumentationResolver ResolverFor(SourceAnalysis analysis) => new(
        analysis.Documentation,
        analysis.OtherModules(SdkAnalyses()).Select(sdk => sdk.Documentation),
        isDirective: name => DirectiveDocs.Describe(name) is not null,
        isInstruction: InstructionDocs.IsMnemonic,
        readText: path => OpenText(path) ?? (File.Exists(path) ? File.ReadAllText(path) : null),
        root: RepositoryRoot(analysis.Root));

    /// <summary>
    ///  Finds the documentation of a definition.
    /// </summary>
    /// <param name="site">The definition.</param>
    /// <returns>The topic, inheritance merged, with the resolver for its links; or null when undocumented.</returns>
    internal (DocumentationTopic Topic, DocumentationResolver Resolver)? TopicOf(SymbolSite site)
    {
        foreach (SourceAnalysis analysis in AllAnalyses())
        {
            if (!analysis.Members.Contains(site.Path)) { continue; }
            DocumentationSet set = analysis.Documentation;
            DocumentationTopic? topic = set.Topics.FirstOrDefault(candidate => Documents(candidate, site))
                ?? set.Find(site.Name)
                ?? set.FindRoutine(site.Name);

            if (topic is null) { continue; }
            DocumentationResolver resolver = ResolverFor(analysis);
            return (resolver.Effective(topic), resolver);
        }

        return null;
    }

    private static bool Documents(DocumentationTopic topic, SymbolSite site) =>
        topic.Comments.Any(comment =>
            comment.TargetLine == site.Line && string.Equals(comment.Path, site.Path, StringComparison.OrdinalIgnoreCase));

    /// <summary>
    ///  Gets the address a documentation link opens: the definition's file and line.
    /// </summary>
    /// <param name="target">The resolved target.</param>
    /// <returns>A file URI with a line fragment, or null.</returns>
    internal string? Href(DocumentationTarget target)
    {
        if (target.Topic is { } topic) { return FileLink(topic.Path, topic.Line); }
        foreach (SourceAnalysis analysis in AllAnalyses())
        {
            if (analysis.Find(target.Name).FirstOrDefault() is { } site) { return FileLink(site.Path, site.Line); }
        }

        return null;
    }

    private static string FileLink(string path, int line) => $"{new Uri(path).AbsoluteUri}#L{line + 1}";

    /// <summary>
    ///  Gets the documentation problems of an analysis as editor diagnostics, by file: the lint, and uses of
    ///  deprecated definitions.
    /// </summary>
    private Dictionary<string, List<Diagnostic>> DocumentationDiagnostics(SourceAnalysis analysis)
    {
        Dictionary<string, List<Diagnostic>> byFile = new(StringComparer.OrdinalIgnoreCase);
        void Add(string path, int line, string message, DiagnosticSeverity severity)
        {
            if (!byFile.TryGetValue(path, out List<Diagnostic>? list)) { byFile[path] = list = []; }
            list.Add(new Diagnostic
            {
                Range = LineRange(path, line, 0),
                Severity = severity,
                Source = "retrocore docs",
                Message = message
            });
        }

        DocumentationResolver resolver = ResolverFor(analysis);
        foreach (DocumentationDiagnostic diagnostic in resolver.Check())
        {
            DiagnosticSeverity severity = diagnostic.Severity == DocumentationSeverity.Error
                ? DiagnosticSeverity.Error
                : DiagnosticSeverity.Warning;

            Add(Path.GetFullPath(diagnostic.Path), diagnostic.Line, diagnostic.Message, severity);
        }

        // Code that uses a deprecated definition, here or in the SDK, gets a warning at each use.
        List<DocumentationTopic> deprecated = [.. SdkAnalyses().Append(analysis)
            .SelectMany(source => source.Documentation.Topics)
            .Where(topic => topic.Section("Deprecated") is not null)];

        if (deprecated.Count == 0) { return byFile; }
        foreach (string member in analysis.Members)
        {
            string[] lines = analysis.LinesOf(member);
            for (int line = 0; line < lines.Length; line++)
            {
                int comment = SourceText.CommentStart(lines[line]);
                string code = comment < 0 ? lines[line] : lines[line][..comment];
                foreach (DocumentationTopic topic in deprecated)
                {
                    string name = topic.Name[(topic.Name.LastIndexOf(':') + 1)..];
                    bool definition = topic.Line == line && string.Equals(topic.Path, member, StringComparison.OrdinalIgnoreCase);
                    if (!definition && Mentions(code, name))
                    {
                        string reason = topic.Section("Deprecated")?.Text ?? "";
                        Add(member, line, $"{name} is deprecated. {reason}".Trim(), DiagnosticSeverity.Warning);
                    }
                }
            }
        }

        return byFile;
    }

    // Whether code uses a name as a whole word in an operand or operation (not as the label it defines).
    private static bool Mentions(string code, string name)
    {
        int index = 0;
        while ((index = code.IndexOf(name, index, StringComparison.Ordinal)) >= 0)
        {
            int end = index + name.Length;
            bool start = index == 0 || !SourceText.IsNameCharacter(code[index - 1]);
            bool finish = end == code.Length || !SourceText.IsNameCharacter(code[end]);
            bool label = index == 0 && end < code.Length && code[end] == ':';
            if (start && finish && !label && index != 0) { return true; }
            index = end;
        }

        return false;
    }

    private static string? RepositoryRoot(string path)
    {
        for (string? directory = Path.GetDirectoryName(path); directory is not null; directory = Path.GetDirectoryName(directory))
        {
            string git = Path.Join(directory, ".git");
            if (Directory.Exists(git) || File.Exists(git)) { return directory; }
        }

        return null;
    }
}
