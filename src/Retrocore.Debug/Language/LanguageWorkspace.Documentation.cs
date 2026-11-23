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
        if (target.Topic is { } topic)
        {
            // Where macros' bodies share the topic with other definitions of the name, the target's symbol is one of
            // them: its own comment, a definition outside the bodies first, as without the macro. Only a definition
            // in the build counts: a body the build expands once, or one outside in the build's branch. Failing
            // those, the link opens the only definition the build has, if it has just one.
            bool Gives(DocumentationComment comment) =>
                topic.Set.ReachesInBuild(comment) && topic.Set.SymbolOf(topic, comment) == target.Name;

            List<DocumentationComment> defining = [.. topic.Comments.Where(topic.Set.ReachesInBuild)];
            DocumentationComment? own = topic.Comments.Any(comment => comment.Macro is not null)
                ? topic.Comments.FirstOrDefault(comment => comment.Macro is null && Gives(comment))
                    ?? topic.Comments.FirstOrDefault(Gives)
                    ?? (defining.Count == 1 ? defining[0] : null)
                : null;

            return own is null ? FileLink(topic.Path, topic.Line) : FileLink(own.Path, own.Line);
        }

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
    ///  Gets the documentation problems of an analysis as editor diagnostics, by file: the lint, uses of deprecated
    ///  definitions and of historical names, less what the files' <c>ignore=</c> exclusions turn off. Each carries
    ///  its rule's ID as its code.
    /// </summary>
    private Dictionary<string, List<Diagnostic>> DocumentationDiagnostics(SourceAnalysis analysis)
    {
        Dictionary<DocumentationDiagnostic, (string Name, string? Alternative)> replacements = [];
        List<DocumentationDiagnostic> own = [.. Deprecated(analysis), .. HistoricalNames(analysis, replacements)];
        Dictionary<string, List<Diagnostic>> byFile = [with(StringComparer.OrdinalIgnoreCase)];
        foreach (DocumentationDiagnostic diagnostic in ResolverFor(analysis).Lint(own, DocumentationRules.EditorRules))
        {
            string path = Path.GetFullPath(diagnostic.Path);
            if (!byFile.TryGetValue(path, out List<Diagnostic>? list)) { byFile[path] = list = []; }
            (string Name, string? Alternative)? fix = replacements.TryGetValue(diagnostic, out var found) ? found : null;
            list.Add(LintEditor.ToDiagnostic(diagnostic, LineRange(path, diagnostic.Line, 0), fix?.Name, fix?.Alternative));
        }

        return byFile;
    }

    // Code that uses a deprecated definition, here or in the SDK, gets a warning at each use.
    private IEnumerable<DocumentationDiagnostic> Deprecated(SourceAnalysis analysis)
    {
        List<DocumentationTopic> deprecated = [.. SdkAnalyses().Append(analysis)
            .SelectMany(source => source.Documentation.Topics)
            .Where(topic => topic.Section("Deprecated") is not null)];

        if (deprecated.Count == 0) { yield break; }
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
                        yield return new(
                            $"{name} is deprecated. {reason}".Trim(),
                            member,
                            line,
                            DocumentationSeverity.Warning,
                            DocumentationRules.Deprecated)
                        {
                            Name = name
                        };
                    }
                }
            }
        }
    }

    // Code written with a historical name gets an information message at each use, which a quick fix replaces with
    // the definition's current name. A name that two definitions give is the assembler's error instead. Where a
    // .using makes the name mean another definition, the use gets a warning, since code typed in from a listing
    // would mean the old name's definition; its quick fixes write either name.
    private List<DocumentationDiagnostic> HistoricalNames(
        SourceAnalysis analysis,
        Dictionary<DocumentationDiagnostic, (string Name, string? Alternative)> replacements)
    {
        List<DocumentationDiagnostic> diagnostics = [];
        Dictionary<string, string?> current = [with(StringComparer.Ordinal)];
        HashSet<string> own = [with(StringComparer.Ordinal)];
        foreach (DocumentationSet set in analysis.OtherModules(SdkAnalyses()).Select(sdk => sdk.Documentation).Prepend(analysis.Documentation))
        {
            bool thisBuild = ReferenceEquals(set, analysis.Documentation);
            foreach (string name in set.AlsoNames)
            {
                // A name a root symbol has is never historical; one a scope defines is checked at each use, below.
                if (analysis.Definitions.Any(site => site.Name == name)) { continue; }

                // The file's own build gives its old names first: an SDK module's Also: of the same spelling, which
                // the build does not include, neither replaces nor cancels one the build gives.
                if (!thisBuild && own.Contains(name)) { continue; }

                IReadOnlyList<DocumentationTopic> topics = set.FindAlso(name, thisBuild);
                IReadOnlyList<string> symbols = topics.Count == 1 ? set.SymbolsOf(topics[0], name, thisBuild) : [];
                string? replacement = symbols.Count == 1 ? symbols[0] : null;
                current[name] = current.TryGetValue(name, out string? earlier) && earlier != replacement ? null : replacement;

                // Only a name whose definition the build makes takes precedence; one in a branch it leaves out stays
                // as ambiguous with the SDK's as before. While the file has errors, the assembly may stop short of its
                // definitions, so those its text makes count, in a branch whose condition holds.
                bool built = replacement is not null && (analysis.Result.Success
                    ? analysis.Result.Symbols.ContainsKey(replacement)
                    : analysis.Definitions.Any(site => site.Name == replacement));

                bool taken = topics.Count == 1 && set.ConditionHolds(topics[0]);
                if (thisBuild && built && taken)
                {
                    own.Add(name);
                }
            }
        }

        if (current.Count == 0) { return diagnostics; }
        foreach (string member in analysis.Members)
        {
            string[] lines = analysis.LinesOf(member);
            foreach ((int line, int start, string name) in SourceText.CodeNames(lines))
            {
                if (!current.TryGetValue(name, out string? replacement) || replacement is null) { continue; }

                // A name the line's scopes or .using directives define binds there, not to the historical name; a
                // .using that does so is reported, as the code may mean the old name. A root-qualified ::Name is the
                // plain name at the root, which no scope or .using changes.
                bool root = start >= 2 && lines[line].AsSpan(start - 2, 2) is "::";
                if (!root && analysis.Bound(name, member, line) is not null)
                {
                    if (Shadowed(analysis, name, member, line, start, replacement) is { } shadowed)
                    {
                        diagnostics.Add(shadowed.Diagnostic);
                        replacements[shadowed.Diagnostic] = (shadowed.Used, replacement);
                    }

                    continue;
                }

                DocumentationDiagnostic diagnostic = new(
                    $"{name} is a historical name of {replacement}.",
                    member,
                    line,
                    DocumentationSeverity.Information,
                    DocumentationRules.HistoricalName)
                {
                    Name = name,
                    Column = start,
                    Length = name.Length
                };

                diagnostics.Add(diagnostic);
                replacements[diagnostic] = (replacement, null);
            }
        }

        return diagnostics;
    }

    // The warning for a historical name that a .using brings to another definition at a use, and that definition's
    // name; null when the code's own scopes bind it, or the .using reaches more than one definition site (even of one
    // name), so the fix would be a guess.
    private static (DocumentationDiagnostic Diagnostic, string Used)? Shadowed(
        SourceAnalysis analysis,
        string name,
        string member,
        int line,
        int start,
        string replacement)
    {
        if (analysis.BoundThroughUsing(name, member, line) is not { } used) { return null; }

        // A .using is native syntax only, and does not reach into an included file, so the names compare as the
        // native dialect's do: case matters.
        if (used.Count != 1 || used[0].Name == replacement) { return null; }
        string target = used[0].Name;
        DocumentationDiagnostic diagnostic = new(
            $"{name} is a historical name of {replacement}, but the .using in effect here makes it {target}.",
            member,
            line,
            DocumentationSeverity.Warning,
            DocumentationRules.UsingShadow)
        {
            Name = name,
            Column = start,
            Length = name.Length
        };

        return (diagnostic, target);
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
