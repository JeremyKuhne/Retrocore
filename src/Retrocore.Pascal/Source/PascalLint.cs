// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Documentation;
using Retrocore.Media;
using System.Text.RegularExpressions;

namespace Retrocore.Pascal.Source;

/// <summary>
///  Checks Apple Pascal sources against the SDK's Pascal style (docs/PascalStyle.md): what the editor reports and
///  the SDK's tests require.
/// </summary>
public static partial class PascalLint
{
    /// <summary>
    ///  The widest a line may be: the Editor's screen.
    /// </summary>
    public const int LineWidth = 80;

    /// <summary>
    ///  The pages of text the Editor holds: Apple Pascal 1.0's and 1.1's largest file, 38 blocks with its header.
    /// </summary>
    public const int EditorPages = 18;

    /// <summary>
    ///  The longest a file's name may be, its suffix included.
    /// </summary>
    public const int FileNameLength = 15;

    private const int PageSize = 1024;

    /// <summary>
    ///  Checks a program and each of its files.
    /// </summary>
    /// <param name="program">The program.</param>
    /// <param name="bibliography">
    ///  The documents the <c>Also:</c> sections may cite, or null not to check their keys.
    /// </param>
    /// <returns>The problems, by file and line.</returns>
    public static List<PascalDiagnostic> Check(PascalProgram program, DocumentationBibliography? bibliography)
    {
        ArgumentNullException.ThrowIfNull(program);
        List<PascalDiagnostic> problems = [];
        foreach (PascalSourceFile file in program.Files)
        {
            CheckFile(file, problems);
        }

        CheckIncludes(program, problems);
        CheckCase(program, problems);
        CheckNames(program, problems);
        CheckDocs(program, bibliography, problems);
        return
        [
            .. problems
                .OrderBy(problem => problem.File, StringComparer.Ordinal)
                .ThenBy(problem => problem.Line)
                .ThenBy(problem => problem.Column)
        ];
    }

    // What a file's text alone decides: its lines, its name, its size, its comments.
    private static void CheckFile(PascalSourceFile file, List<PascalDiagnostic> problems)
    {
        string path = file.Path;
        for (int line = 0; line < file.Lines.Length; line++)
        {
            string text = file.Lines[line];
            if (text.Length > LineWidth)
            {
                Add(line, LineWidth, text.Length, "line-length", $"Line is over {LineWidth} columns, the Editor's.");
            }

            int tab = text.IndexOf('\t', StringComparison.Ordinal);
            if (tab >= 0)
            {
                Add(line, tab, tab + 1, "tab", "Indent with spaces: the Editor has no tabs.");
            }
        }

        string name = Path.GetFileName(path);
        if (name.Length > FileNameLength)
        {
            Add(0, 0, 0, "file-name", $"'{name}' is over {FileNameLength} characters, the longest a disk keeps.");
        }
        else if (name != name.ToUpperInvariant() || !name.EndsWith(".TEXT", StringComparison.Ordinal))
        {
            Add(0, 0, 0, "file-name", "Name the file as the disk does, in capitals ending .TEXT.");
        }

        int pages = (PascalTextFile.Write(file.Text).Length / PageSize) - 1;
        if (pages > EditorPages)
        {
            Add(
                0,
                0,
                0,
                "file-size",
                $"The file is {pages} pages; the Editor holds {EditorPages}. Move procedures to another (*$I*) file.");
        }

        foreach (PascalToken token in file.Tokens.Where(token => token.Kind == PascalTokenKind.BraceComment))
        {
            int end = token.Line == token.EndLine ? token.EndColumn : token.Column + 1;
            Add(token.Line, token.Column, end, "comment", "Write comments as (* *), and documentation as (** *).");
        }

        void Add(int line, int column, int end, string rule, string message) =>
            problems.Add(new(path, line, column, end, IsError: false, rule, message));
    }

    private static void CheckIncludes(PascalProgram program, List<PascalDiagnostic> problems)
    {
        foreach (PascalInclude include in program.Includes.Where(include => include.Path is null))
        {
            PascalToken token = include.Token;
            problems.Add(new(
                token.File,
                token.Line,
                token.Column,
                token.EndColumn,
                IsError: true,
                "include",
                $"There is no file '{include.Name}' beside this one to include."));
        }
    }

    // Reserved words and standard identifiers in capitals.
    private static void CheckCase(PascalProgram program, List<PascalDiagnostic> problems)
    {
        HashSet<PascalToken> declared = [.. program.Declarations.Select(declaration => declaration.Token)];
        Dictionary<PascalToken, PascalReference> references = [];
        foreach (PascalReference reference in program.References)
        {
            references.TryAdd(reference.Token, reference);
        }

        foreach (PascalSourceFile file in program.Files)
        {
            foreach (PascalToken token in file.Tokens)
            {
                bool keyword = token.Kind == PascalTokenKind.Keyword;

                // A standard identifier the source redeclares is the source's own name, in its own case.
                bool standard = token.Kind == PascalTokenKind.Identifier
                    && PascalNames.IsStandard(token.Text)
                    && !declared.Contains(token)
                    && (!references.TryGetValue(token, out PascalReference? reference)
                        || program.Resolve(reference) is null);

                if ((keyword || standard) && token.Text != token.Text.ToUpperInvariant())
                {
                    string what = keyword ? "reserved word" : "standard identifier";
                    problems.Add(new(
                        token.File,
                        token.Line,
                        token.Column,
                        token.EndColumn,
                        IsError: false,
                        "case",
                        $"Write the {what} {token.Text.ToUpperInvariant()} in capitals."));
                }
            }
        }
    }

    // Names the source defines: PascalCase, no underscores, and distinct in their first 8 letters from what they
    // might be taken for.
    private static void CheckNames(PascalProgram program, List<PascalDiagnostic> problems)
    {
        foreach (PascalDeclaration declaration in program.Declarations)
        {
            if (declaration.Name.Contains('_', StringComparison.Ordinal))
            {
                Add(declaration, "name", $"'{declaration.Name}' has an underscore, which the Compiler leaves out.");
            }
            else if (!declaration.NameIsKept && !IsPascalCase(declaration.Name))
            {
                Add(declaration, "name", $"Write '{declaration.Name}' in PascalCase, in full words.");
            }
        }

        // The Compiler reads 8 letters, so a name that differs only after them means one it can see.
        foreach (PascalScope scope in program.Scopes)
        {
            foreach (PascalDeclaration declaration in scope.Declarations)
            {
                PascalDeclaration? other = SameKey(scope, declaration);
                if (other is not null)
                {
                    Add(
                        declaration,
                        "name-8",
                        $"'{declaration.Name}' and '{other.Name}' are one name to the Compiler, which reads "
                            + $"{PascalNames.Significant} letters ({declaration.Key}).");
                }
            }
        }

        void Add(PascalDeclaration declaration, string rule, string message)
        {
            PascalToken token = declaration.Token;
            problems.Add(new(token.File, token.Line, token.Column, token.EndColumn, IsError: false, rule, message));
        }
    }

    // A differently spelled name with the same key, declared earlier in the scope or in a scope around it.
    private static PascalDeclaration? SameKey(PascalScope scope, PascalDeclaration declaration)
    {
        for (PascalScope? outer = scope; outer is not null; outer = outer.Parent)
        {
            PascalDeclaration? other = outer.Declarations.FirstOrDefault(candidate => candidate != declaration
                && candidate.Key == declaration.Key
                && !string.Equals(candidate.Name, declaration.Name, StringComparison.OrdinalIgnoreCase)
                && (outer != scope || IsBefore(candidate, declaration)));

            if (other is not null || scope.IsRecord)
            {
                return other;
            }
        }

        return null;
    }

    private static bool IsBefore(PascalDeclaration first, PascalDeclaration second) =>
        first.Scope.Declarations.IndexOf(first) < second.Scope.Declarations.IndexOf(second);

    // PascalCase: starts with a capital, and is not all capitals unless it is one letter and digits.
    private static bool IsPascalCase(string name) =>
        char.IsUpper(name[0])
            && (name.Any(char.IsLower) || name.Skip(1).All(char.IsDigit));

    // Documentation comments: each documents something, with known sections, Also: items with known keys, and
    // links that reach a declaration.
    private static void CheckDocs(
        PascalProgram program,
        DocumentationBibliography? bibliography,
        List<PascalDiagnostic> problems)
    {
        foreach (PascalDocComment stray in program.StrayDocs)
        {
            Add(stray.Token, "doc-placement", "This (** *) comment documents nothing: make it (* *).");
        }

        IEnumerable<PascalDocComment> docs = program.Declarations
            .Select(declaration => declaration.Doc)
            .Concat(program.Files.Select(file => file.Doc))
            .OfType<PascalDocComment>()
            .Distinct();

        string sections = string.Join(", ", PascalDocComment.Sections.Select(section => section + ":"));
        foreach (PascalDocComment doc in docs)
        {
            foreach ((int line, string name) in doc.UnknownSections)
            {
                problems.Add(new(
                    doc.Token.File,
                    line,
                    0,
                    0,
                    IsError: false,
                    "doc-section",
                    $"'{name}:' is not a section: use {sections}"));
            }

            CheckAlso(program, bibliography, doc, problems);
            foreach (Match link in Link().Matches(doc.Token.Text))
            {
                string target = link.Groups["target"].Value;
                if (program.FindLink(target) is null)
                {
                    Add(doc.Token, "link", $"No declaration is named '{target}'.");
                }
            }
        }

        foreach ((string name, List<PascalDeclaration> owners) in program.OldNames.Where(pair => pair.Value.Count > 1))
        {
            PascalToken at = owners[1].Doc?.Token ?? owners[1].Token;
            Add(at, "also", $"The historical name {name} is {owners[0].QualifiedName}'s too: give it to one.");
        }

        void Add(PascalToken token, string rule, string message) => problems.Add(Diagnostic(token, rule, message));
    }

    private static void CheckAlso(
        PascalProgram program,
        DocumentationBibliography? bibliography,
        PascalDocComment doc,
        List<PascalDiagnostic> problems)
    {
        foreach ((string item, DocumentationAlso? also) in doc.Also)
        {
            if (also is null)
            {
                Add($"Write the historical name '{item}' as NAME (KEYS), such as GENLDC (UCSD20).");
                continue;
            }

            if (also.Sources.Count == 0)
            {
                Add($"Give the documents that call it {also.Name}, by their keys.");
            }

            IEnumerable<string> unknown = bibliography is null
                ? []
                : also.Sources.Where(key => bibliography.Find(key) is null);

            foreach (string key in unknown)
            {
                Add($"'{key}' is not a document in the bibliography (docs/Bibliography.md).");
            }

            if (program.Declarations.Any(declaration => string.Equals(
                declaration.Name,
                also.Name,
                StringComparison.OrdinalIgnoreCase)))
            {
                Add($"The historical name {also.Name} is a name the source declares: give it in prose.");
            }
        }

        void Add(string message) => problems.Add(Diagnostic(doc.Token, "also", message));
    }

    // A warning on a token, or on the opening of one that runs over lines.
    private static PascalDiagnostic Diagnostic(PascalToken token, string rule, string message) => new(
        token.File,
        token.Line,
        token.Column,
        token.Line == token.EndLine ? token.EndColumn : token.Column + 3,
        IsError: false,
        rule,
        message);

    [GeneratedRegex(@"<(?:[^<>]* at )?(?<target>[A-Za-z][A-Za-z0-9]*(?:\.[A-Za-z][A-Za-z0-9]*)*)>")]
    private static partial Regex Link();
}
