// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Documentation;

/// <summary>
///  Applies the files' <c>ignore=</c> exclusions to the lint's diagnostics: the one place the editor and the tests
///  filter them.
/// </summary>
public static class DocumentationExclusions
{
    /// <summary>
    ///  Drops each warning and information an exclusion covers, and adds information for each exclusion that covers
    ///  nothing. Errors, and the rules that are not <see cref="DocumentationRule.Ignorable"/>, are kept.
    /// </summary>
    /// <param name="diagnostics">Every diagnostic of the files, from the parser, the resolver and the editor.</param>
    /// <param name="files">The files, whose exclusions apply to their own diagnostics.</param>
    /// <returns>The diagnostics that remain.</returns>
    public static List<DocumentationDiagnostic> Apply(IEnumerable<DocumentationDiagnostic> diagnostics, IEnumerable<DocumentationFile> files)
    {
        Dictionary<string, IReadOnlyList<DocumentationExclusion>> byPath = [with(StringComparer.OrdinalIgnoreCase)];
        foreach (DocumentationFile file in files)
        {
            if (file.Exclusions.Count != 0) { byPath.TryAdd(Path.GetFullPath(file.Path), file.Exclusions); }
        }

        List<DocumentationDiagnostic> kept = [];
        HashSet<DocumentationExclusion> used = [];
        foreach (DocumentationDiagnostic diagnostic in diagnostics)
        {
            bool ignorable = diagnostic.Severity != DocumentationSeverity.Error
                && DocumentationRules.Find(diagnostic.Rule) is { Ignorable: true };

            if (!ignorable
                || byPath.Count == 0
                || !byPath.TryGetValue(Path.GetFullPath(diagnostic.Path), out IReadOnlyList<DocumentationExclusion>? exclusions))
            {
                kept.Add(diagnostic);
                continue;
            }

            bool covered = false;
            foreach (DocumentationExclusion exclusion in exclusions)
            {
                if (!exclusion.Covers(diagnostic)) { continue; }
                used.Add(exclusion);
                covered = true;
            }

            if (!covered) { kept.Add(diagnostic); }
        }

        // An exclusion that outlives its reason is removed, so it says so.
        foreach (DocumentationExclusion exclusion in byPath.Values.SelectMany(exclusions => exclusions))
        {
            if (used.Contains(exclusion)) { continue; }
            kept.Add(new(
                $"Nothing here breaks {exclusion.Written}; remove the exclusion.",
                exclusion.Path,
                exclusion.Line,
                DocumentationSeverity.Information,
                DocumentationRules.Exclusion)
            {
                Name = exclusion.Written
            });
        }

        return kept;
    }
}
