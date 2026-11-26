// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Documentation;
using Retrocore.Pascal.Source;
using System.Text.RegularExpressions;

namespace Retrocore.Debug.Language;

/// <summary>
///  The language features of Apple Pascal documents: hover, definitions and the outline, by the names the source
///  declares and the historical names its <c>Also:</c> sections give.
/// </summary>
internal static partial class PascalFeatures
{
    /// <summary>
    ///  Describes the name under the cursor: what it declares, and its documentation comment.
    /// </summary>
    /// <param name="program">The program the document is part of.</param>
    /// <param name="path">The document.</param>
    /// <param name="position">The cursor.</param>
    /// <returns>The hover, or null.</returns>
    internal static Hover? Hover(PascalProgram program, string path, Position position)
    {
        if (Find(program, path, position) is not { } found) { return null; }
        (PascalDeclaration declaration, bool historical, LspRange range, string name) = found;
        DocumentationBibliography? bibliography = PascalDocuments.Bibliography(program);

        // Paragraphs, a blank line between each.
        List<string> parts = [$"```pascal\n{Heading(declaration)}\n```"];
        if (historical)
        {
            string old = name.Split('.')[^1].ToUpperInvariant();
            parts.Add($"`{old}` is a historical name of `{declaration.QualifiedName}`.");
        }

        if (declaration.Doc is { } doc)
        {
            if (doc.Summary.Length > 0) { parts.Add(Prose(doc.Summary)); }
            parts.AddRange(doc.Remarks.Select(Prose));
            foreach (PascalDocSection section in doc.DocSections)
            {
                string body = section.Name == "Also"
                    ? string.Join("; ", section.Items.Select(item => DocumentationMarkdown.Also(item, bibliography)))
                    : Prose(section.Text);

                string title = section.Name == "See" ? "See also" : section.Name;
                parts.Add($"**{title}:** {body}");
            }
        }

        return new Hover
        {
            Contents = new MarkupContent { Kind = MarkupKind.Markdown, Value = string.Join("\n\n", parts) },
            Range = range
        };
    }

    /// <summary>
    ///  Finds where the name under the cursor is declared, by its name or a historical one, or where a link in a
    ///  documentation comment leads.
    /// </summary>
    /// <param name="program">The program the document is part of.</param>
    /// <param name="path">The document.</param>
    /// <param name="position">The cursor.</param>
    /// <returns>The declarations.</returns>
    internal static IEnumerable<LspLocation> Definition(PascalProgram program, string path, Position position) =>
        Find(program, path, position) is { } found ? [Location(found.Declaration.Token)] : [];

    /// <summary>
    ///  Finds where the name under the cursor's declaration is used, by any of its names.
    /// </summary>
    /// <param name="program">The program the document is part of.</param>
    /// <param name="path">The document.</param>
    /// <param name="position">The cursor.</param>
    /// <param name="includeDeclaration">Whether to include the declaration itself.</param>
    /// <returns>The uses.</returns>
    internal static IEnumerable<LspLocation> References(
        PascalProgram program,
        string path,
        Position position,
        bool includeDeclaration)
    {
        if (Find(program, path, position) is not { } found) { return []; }
        IEnumerable<PascalToken> uses = program.References
            .Where(reference => program.Resolve(reference)?.Declaration == found.Declaration)
            .Select(reference => reference.Token);

        if (includeDeclaration) { uses = uses.Prepend(found.Declaration.Token); }
        return [.. uses.Distinct().Select(Location)];
    }

    /// <summary>
    ///  Lists a document's declarations as an outline: its routines and types, with what they declare under them.
    /// </summary>
    /// <param name="program">The program the document is part of.</param>
    /// <param name="path">The document.</param>
    /// <returns>The outline.</returns>
    internal static List<DocumentSymbol> Symbols(PascalProgram program, string path)
    {
        Dictionary<PascalDeclaration, List<PascalScope>> owned = [];
        foreach (PascalScope scope in program.Scopes)
        {
            if (scope.Owner is { } owner)
            {
                if (!owned.TryGetValue(owner, out List<PascalScope>? scopes)) { owned[owner] = scopes = []; }
                scopes.Add(scope);
            }
        }

        // The file's outermost declarations: the program's own, and the routines of one declared in another file,
        // such as the nested procedures an include holds for its segment, not that routine's other locals.
        return
        [
            .. program.Declarations
                .Where(declaration => InFile(declaration, path) && IsOutermost(declaration))
                .Select(declaration => Symbol(declaration, path, owned, top: true))
        ];

        bool IsOutermost(PascalDeclaration declaration) =>
            declaration.Kind is PascalDeclarationKind.Program or PascalDeclarationKind.Unit
                || declaration.Scope == program.Outer
                || (declaration.Kind is PascalDeclarationKind.Procedure or PascalDeclarationKind.Function
                    && declaration.Scope.Owner is { } owner
                    && !InFile(owner, path));
    }

    // The declaration a position names: a declared or used name, or a link in a documentation comment.
    private static (PascalDeclaration Declaration, bool Historical, LspRange Range, string Name)? Find(
        PascalProgram program,
        string path,
        Position position)
    {
        if (program.TokenAt(path, position.Line, position.Character) is not { } token) { return null; }
        if (token.Kind == PascalTokenKind.Identifier)
        {
            return program.DeclarationAt(path, position.Line, position.Character) is { } found
                ? (found.Declaration, found.Historical, Range(token), token.Text)
                : null;
        }

        if (token.Kind != PascalTokenKind.DocComment) { return null; }
        PascalDocLink? link = PascalDocComment.Parse(token).Links.FirstOrDefault(link => link.Line == position.Line
            && position.Character >= link.Column
            && position.Character < link.EndColumn);

        if (link is null || program.FindLink(link.Target) is not { } target) { return null; }
        string last = link.Target.Split('.')[^1];
        bool historical = !string.Equals(PascalNames.Key(last), target.Key, StringComparison.Ordinal);
        return (target, historical, new LspRange(link.Line, link.Column, link.Line, link.EndColumn), link.Target);
    }

    private static DocumentSymbol Symbol(
        PascalDeclaration declaration,
        string path,
        Dictionary<PascalDeclaration, List<PascalScope>> owned,
        bool top)
    {
        // A program's scope is the outermost, whose declarations are listed beside it.
        List<DocumentSymbol> children = [];
        if (!top || declaration.Kind is not (PascalDeclarationKind.Program or PascalDeclarationKind.Unit))
        {
            IEnumerable<PascalDeclaration> under = owned.GetValueOrDefault(declaration, [])
                .SelectMany(scope => scope.Declarations)
                .Where(child => child.Kind != PascalDeclarationKind.Parameter && InFile(child, path));

            children = [.. under.Select(child => Symbol(child, path, owned, top: false))];
        }

        return new DocumentSymbol
        {
            Name = declaration.Name,
            Detail = declaration.Doc?.Summary is { Length: > 0 } summary ? summary : null,
            Kind = KindOf(declaration),
            Range = Range(declaration.Token),
            SelectionRange = Range(declaration.Token),
            Children = children.Count > 0 ? children : null
        };
    }

    private static bool InFile(PascalDeclaration declaration, string path) =>
        string.Equals(declaration.Token.File, path, StringComparison.OrdinalIgnoreCase);

    private static SymbolKind KindOf(PascalDeclaration declaration) => declaration.Kind switch
    {
        PascalDeclarationKind.Program or PascalDeclarationKind.Unit => SymbolKind.Module,
        PascalDeclarationKind.Procedure or PascalDeclarationKind.Function => SymbolKind.Function,
        PascalDeclarationKind.Constant => SymbolKind.Constant,
        PascalDeclarationKind.Type => SymbolKind.Struct,
        PascalDeclarationKind.Field => SymbolKind.Field,
        PascalDeclarationKind.EnumValue => SymbolKind.EnumMember,
        _ => SymbolKind.Variable
    };

    // What a declaration is, as Pascal would write it: "FUNCTION Outer.Inner", "VAR Count", "(field) Item.Next".
    private static string Heading(PascalDeclaration declaration)
    {
        string word = declaration.Kind switch
        {
            PascalDeclarationKind.Program => "PROGRAM",
            PascalDeclarationKind.Unit => "UNIT",
            PascalDeclarationKind.Procedure => "PROCEDURE",
            PascalDeclarationKind.Function => "FUNCTION",
            PascalDeclarationKind.Constant => "CONST",
            PascalDeclarationKind.Type => "TYPE",
            PascalDeclarationKind.Variable => "VAR",
            PascalDeclarationKind.Parameter => "(parameter)",
            PascalDeclarationKind.Field => "(field)",
            _ => "(value)"
        };

        string segment = declaration.IsSegment ? "SEGMENT " : "";
        return $"{segment}{word} {declaration.QualifiedName}";
    }

    // A comment's text for Markdown: its links as code, since Markdown would take them for HTML.
    private static string Prose(string text) => LinkText().Replace(text, link => $"`{link.Groups["target"].Value}`");

    private static LspRange Range(PascalToken token) => new(token.Line, token.Column, token.EndLine, token.EndColumn);

    private static LspLocation Location(PascalToken token) => new()
    {
        Uri = DocumentUri.FromFileSystemPath(token.File),
        Range = Range(token)
    };

    [GeneratedRegex(@"<(?:[^<>]* at )?(?<target>[A-Za-z][A-Za-z0-9.]*)>")]
    private static partial Regex LinkText();
}
