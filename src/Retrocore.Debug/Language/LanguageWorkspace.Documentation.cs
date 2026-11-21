// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json.Nodes;
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
        root: RepositoryRoot(analysis.Root))
    {
        Bibliography = SourceBibliography.For(analysis.Root, analysis.Members)
    };

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
    /// <param name="path">The file containing the link.</param>
    /// <returns>A file URI with a line fragment, or null.</returns>
    internal string? Href(DocumentationTarget target, string path)
    {
        if (target.Topic is { } topic) { return FileLink(topic.Path, topic.Line); }
        bool macro10 = AnalysisOf(path)?.UsesMacro10(path) ?? SourceText.Macro10Dialect(path, LinesOf(path)) == true;
        foreach (SourceAnalysis analysis in AllAnalyses())
        {
            if (analysis.Find(target.Name, macro10).FirstOrDefault() is { } site)
            {
                return FileLink(site.Path, site.Line);
            }
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
        Dictionary<string, List<Diagnostic>> byFile = [with(StringComparer.OrdinalIgnoreCase)];
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

        HistoricalNames(analysis, byFile);

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

    /// <summary>
    ///  The diagnostic code of a use of a historical name, which the quick fix replaces with the current name.
    /// </summary>
    internal const string HistoricalNameCode = "retrocore.historicalName";

    // Code written with a historical name gets an information message at each use, which a quick fix replaces with
    // the definition's current name. A name that two definitions give is the assembler's error instead.
    private void HistoricalNames(SourceAnalysis analysis, Dictionary<string, List<Diagnostic>> byFile)
    {
        Dictionary<string, string?> current = [with(StringComparer.Ordinal)];
        foreach (DocumentationSet set in analysis.OtherModules(SdkAnalyses()).Select(sdk => sdk.Documentation).Prepend(analysis.Documentation))
        {
            foreach (string name in set.AlsoNames)
            {
                // A name some symbol has, in any scope, may be what the code there means, so it gets no quick fix.
                if (analysis.Definitions.Any(site => site.Name == name || site.Name.EndsWith($"::{name}", StringComparison.Ordinal)))
                {
                    continue;
                }

                IReadOnlyList<DocumentationTopic> topics = set.FindAlso(name);
                string? replacement = topics.Count == 1 ? topics[0].Name : null;
                current[name] = current.TryGetValue(name, out string? earlier) && earlier != replacement ? null : replacement;
            }
        }

        if (current.Count == 0) { return; }
        foreach (string member in analysis.Members)
        {
            string[] lines = analysis.LinesOf(member);
            bool inMacro = false;
            for (int line = 0; line < lines.Length; line++)
            {
                int comment = SourceText.CommentStart(lines[line]);
                string code = comment < 0 ? lines[line] : lines[line][..comment];

                // A macro's body names its parameters, which may share a historical name.
                string directive = code.TrimStart();
                if (directive.StartsWith(".macro", StringComparison.OrdinalIgnoreCase)) { inMacro = true; }
                if (directive.StartsWith(".endmacro", StringComparison.OrdinalIgnoreCase))
                {
                    inMacro = false;
                    continue;
                }

                if (inMacro) { continue; }
                foreach ((int start, string name) in Words(code))
                {
                    if (!current.TryGetValue(name, out string? replacement) || replacement is null) { continue; }
                    if (!byFile.TryGetValue(member, out List<Diagnostic>? list)) { byFile[member] = list = []; }
                    list.Add(new Diagnostic
                    {
                        Range = new LspRange(line, start, line, start + name.Length),
                        Severity = DiagnosticSeverity.Information,
                        Code = HistoricalNameCode,
                        Source = "retrocore docs",
                        Message = $"{name} is a historical name of {replacement}.",
                        Data = new JsonObject { ["replacement"] = replacement }
                    });
                }
            }
        }
    }

    // The names in a line of code, with their columns, but not a label the line defines at its start.
    private static IEnumerable<(int Start, string Name)> Words(string code)
    {
        int index = 0;
        while (index < code.Length)
        {
            if (code[index] is '"' or '\'')
            {
                // Skip a quoted string or character.
                char quote = code[index];
                int close = code.IndexOf(quote, index + 1);
                index = close < 0 ? code.Length : close + 1;
                continue;
            }

            if (!SourceText.IsNameCharacter(code[index]) || (index > 0 && SourceText.IsNameCharacter(code[index - 1])))
            {
                index++;
                continue;
            }

            int end = index;
            while (end < code.Length && SourceText.IsNameCharacter(code[end])) { end++; }
            bool qualified = index >= 2 && code[index - 1] == ':' && code[index - 2] == ':';
            if (index != 0 && !qualified && !char.IsAsciiDigit(code[index]) && code[index - 1] != '$')
            {
                yield return (index, code[index..end]);
            }

            index = end;
        }
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
