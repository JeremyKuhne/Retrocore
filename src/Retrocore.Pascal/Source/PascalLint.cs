// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Documentation;
using Retrocore.Media;

namespace Retrocore.Pascal.Source;

/// <summary>
///  Checks Apple Pascal sources against the SDK's Pascal style (docs/PascalStyle.md): what the editor reports and
///  the SDK's tests require.
/// </summary>
public static class PascalLint
{
    /// <summary>
    ///  The widest a line may be: the Editor's screen.
    /// </summary>
    public const int LineWidth = 80;

    /// <summary>
    ///  The most text the strictest Editor loads: Apple Pascal 1.1's and 1.2's on a 64K Apple II, in bytes as the disk
    ///  stores it, leading blanks compressed and each page's padding left out (measured; see docs/PascalStyle.md).
    /// </summary>
    public const int EditorBytes = 16_348;

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
        CheckLines(file.Path, file.Lines, problems);
        foreach (PascalToken token in file.Tokens.Where(token => token.Kind == PascalTokenKind.BraceComment))
        {
            int end = token.Line == token.EndLine ? token.EndColumn : token.Column + 1;
            string message = token.Text.StartsWith("{$", StringComparison.Ordinal)
                ? "Write options as (*$ *), not in braces."
                : "Write comments as (* *), and documentation as (** *).";

            problems.Add(new(file.Path, token.Line, token.Column, end, IsError: false, "comment", message));
        }
    }

    /// <summary>
    ///  Checks a text file for the Editor alone: its lines, its name and its size, as for a source of Apple's
    ///  Assembler that a Pascal program's code links with.
    /// </summary>
    /// <param name="path">The file's path.</param>
    /// <param name="text">Its text.</param>
    /// <returns>The problems, by line.</returns>
    public static List<PascalDiagnostic> CheckText(string path, string text)
    {
        ArgumentNullException.ThrowIfNull(path);
        ArgumentNullException.ThrowIfNull(text);
        List<PascalDiagnostic> problems = [];
        CheckLines(path, PascalLexer.Lines(text), problems);
        return problems;
    }

    // What a file's lines alone decide: their width, the file's name and its size.
    private static void CheckLines(string path, string[] lines, List<PascalDiagnostic> problems)
    {
        for (int line = 0; line < lines.Length; line++)
        {
            string text = lines[line];
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

        // A .TEXT file is one for a disk, whose name the disk keeps; a .pas file is the editor's own.
        string name = Path.GetFileName(path);
        bool forDisk = name.EndsWith(".TEXT", StringComparison.OrdinalIgnoreCase);
        if (forDisk && name.Length > FileNameLength)
        {
            Add(0, 0, 0, "file-name", $"'{name}' is over {FileNameLength} characters, the longest a disk keeps.");
        }
        else if (forDisk && name != name.ToUpperInvariant())
        {
            Add(0, 0, 0, "file-name", "Name the file as the disk does, in capitals ending .TEXT.");
        }

        // A line too long for a page has no disk form, which line-length reports; its size is counted in pieces.
        int stored = StoredLength(PascalTextFile.Write(string.Join('\n', lines.SelectMany(Pieces))));

        if (stored > EditorBytes)
        {
            Add(
                0,
                0,
                0,
                "file-size",
                $"The file is {stored:N0} bytes on a disk; Apple Pascal 1.1's Editor holds {EditorBytes:N0}. "
                    + "Move procedures to another (*$I*) file.");
        }

        void Add(int line, int column, int end, string rule, string message) =>
            problems.Add(new(path, line, column, end, IsError: false, rule, message));
    }

    /// <summary>
    ///  Gets the bytes of text a <c>.TEXT</c> file holds, as the Editor reads them: each page after the header, without
    ///  the padding that ends it.
    /// </summary>
    /// <param name="file">The file, as <see cref="PascalTextFile.Write"/> makes it.</param>
    /// <returns>The bytes.</returns>
    public static int StoredLength(ReadOnlySpan<byte> file)
    {
        int total = 0;
        for (int page = PageSize; page < file.Length; page += PageSize)
        {
            ReadOnlySpan<byte> text = file[page..Math.Min(page + PageSize, file.Length)];
            total += text.TrimEnd((byte)0).Length;
        }

        return total;
    }

    // A line, or a line too long for a disk's page in pieces that each fit one.
    private static IEnumerable<string> Pieces(string line)
    {
        const int Piece = PageSize / 2;
        if (line.Length <= Piece)
        {
            yield return line;
            yield break;
        }

        for (int start = 0; start < line.Length; start += Piece)
        {
            yield return line[start..Math.Min(start + Piece, line.Length)];
        }
    }

    private static void CheckIncludes(PascalProgram program, List<PascalDiagnostic> problems)
    {
        foreach (PascalInclude include in program.Includes.Where(include => include.Path is null))
        {
            string message = $"There is no file '{include.Name}' beside this one to include.";
            problems.Add(Diagnostic(include.Token, "include", message) with { IsError = true });
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
                // After a ".", a name is a field's, which the source's record or another unit's declares.
                bool standard = token.Kind == PascalTokenKind.Identifier
                    && PascalNames.IsStandard(token.Text)
                    && !declared.Contains(token)
                    && (!references.TryGetValue(token, out PascalReference? reference)
                        || (!reference.AfterDot && program.Resolve(reference) is null));

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
            foreach (PascalDocLink link in doc.Links.Where(link => program.FindLink(link.Target) is null))
            {
                problems.Add(new(
                    doc.Token.File,
                    link.Line,
                    link.Column,
                    link.EndColumn,
                    IsError: false,
                    "link",
                    $"No declaration is named '{link.Target}'."));
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
        HashSet<string> given = [with(StringComparer.OrdinalIgnoreCase)];
        foreach ((string item, DocumentationAlso? also) in doc.Also)
        {
            if (also is not null && !given.Add(also.Name))
            {
                Add($"The historical name {also.Name} is given twice: give its documents in one item.");
            }

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

            // A use of a reserved word or standard identifier would otherwise find the declaration that gives it.
            if (PascalNames.IsKeyword(also.Name) || PascalNames.IsStandard(also.Name))
            {
                Add($"The historical name {also.Name} is Pascal's own: give it in prose.");
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
}
