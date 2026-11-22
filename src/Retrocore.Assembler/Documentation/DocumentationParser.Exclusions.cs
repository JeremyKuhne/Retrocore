// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Documentation;

public static partial class DocumentationParser
{
    /// <summary>
    ///  Reads a source's first-line <c>; retrocore:</c> pragma.
    /// </summary>
    /// <param name="text">The source text.</param>
    /// <returns>The pragma, or null when the first line is not one.</returns>
    public static DocumentationPragma? ReadPragma(string text)
    {
        int end = text.IndexOfAny(['\r', '\n']);
        return DocumentationPragma.Read(end < 0 ? text : text[..end]);
    }

    /// <summary>
    ///  Gets where a line's comment starts, as the lint reads it: semicolons in strings and character literals
    ///  such as <c>';'</c> are not comments, and an apostrophe elsewhere is not a quote.
    /// </summary>
    /// <param name="line">The line.</param>
    /// <returns>The semicolon's index, or -1.</returns>
    public static int CommentStart(string line) => Split(line).Comment is { } comment ? line.Length - comment.Length : -1;

    // The exclusions of a file: its first line's, each line of code's own trailing pragma, and each pragma comment
    // line directly above a ;; block. Each ignore= item is checked, and one that can't apply is a diagnostic instead.
    private static List<DocumentationExclusion> Exclusions(string[] lines, string path, List<DocumentationDiagnostic> diagnostics)
    {
        List<DocumentationExclusion> exclusions = [];
        for (int index = 0; index < lines.Length; index++)
        {
            (string code, string? comment) = Split(lines[index]);
            if (comment is null || comment.StartsWith(Marker, StringComparison.Ordinal)) { continue; }
            bool first = index == 0 && code.Trim().Length == 0;
            if (!first && !DocumentationPragma.HasIgnore(comment)) { continue; }
            if (DocumentationPragma.Read(comment) is not { } pragma) { continue; }

            DocumentationExclusionScope scope;
            int last = index;
            int from = index;
            if (first)
            {
                scope = DocumentationExclusionScope.File;
                from = 0;
                last = int.MaxValue;
            }
            else if (code.Trim().Length != 0)
            {
                scope = DocumentationExclusionScope.Line;
            }
            else if (index + 1 < lines.Length && lines[index + 1].TrimStart().StartsWith(Marker, StringComparison.Ordinal))
            {
                scope = DocumentationExclusionScope.Comment;
                from = index + 1;
                last = from;
                while (last + 1 < lines.Length && lines[last + 1].TrimStart().StartsWith(Marker, StringComparison.Ordinal))
                {
                    last++;
                }
            }
            else
            {
                Problem(
                    "Put an exclusion at the end of the line of code it ignores, or on the line directly above a ;; block.",
                    index,
                    DocumentationSeverity.Warning);

                continue;
            }

            if (pragma.EmptyIgnore)
            {
                Problem("ignore= names no rule.", index, DocumentationSeverity.Warning);
            }

            HashSet<string> seen = [with(StringComparer.Ordinal)];
            foreach ((string id, IReadOnlyList<string> names, bool narrowed) in pragma.Ignores)
            {
                if (narrowed && names.Count == 0)
                {
                    Problem($"{id}: names no name; write the names after the colon, or leave the colon out.", index, DocumentationSeverity.Warning);
                    continue;
                }

                if (DocumentationRules.Find(id) is not { } rule)
                {
                    Problem($"No lint rule named '{id}'.", index, DocumentationSeverity.Warning);
                    continue;
                }

                if (!rule.Ignorable)
                {
                    string message = rule.Id == DocumentationRules.Exclusion
                        ? $"{rule.Id} can't be ignored."
                        : $"{rule.Id} reports only errors, which can't be ignored.";

                    Problem(message, index, DocumentationSeverity.Error);
                    continue;
                }

                if (names.Count != 0 && !rule.TakesNames)
                {
                    Problem($"{rule.Id} takes no names.", index, DocumentationSeverity.Error);
                    continue;
                }

                // Each rule, or rule and name, is one exclusion however often it is written.
                foreach (string? name in names.Count == 0 ? [null] : names.Cast<string?>())
                {
                    if (seen.Add(name is null ? rule.Id : $"{rule.Id}:{name}"))
                    {
                        exclusions.Add(new(path, index, scope, from, last, rule.Id, name));
                    }
                }
            }
        }

        return exclusions;

        void Problem(string message, int line, DocumentationSeverity severity) =>
            diagnostics.Add(new(message, path, line, severity, DocumentationRules.Exclusion));
    }
}
