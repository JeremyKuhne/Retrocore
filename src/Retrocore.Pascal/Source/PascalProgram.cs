// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal.Source;

/// <summary>
///  A program or unit, its main file with the files it includes: its scopes, declarations and the names it uses.
/// </summary>
public sealed partial class PascalProgram
{
    private readonly List<PascalToken> _tokens = [];
    private readonly Dictionary<string, List<PascalDeclaration>> _oldNames = [with(StringComparer.Ordinal)];

    private PascalProgram(string root) => Root = root;

    /// <summary>
    ///  Gets the main file's path.
    /// </summary>
    public string Root { get; }

    /// <summary>
    ///  Gets the files, the main file first, then each included file in the order it is included.
    /// </summary>
    public List<PascalSourceFile> Files { get; } = [];

    /// <summary>
    ///  Gets the include directives.
    /// </summary>
    public List<PascalInclude> Includes { get; } = [];

    /// <summary>
    ///  Gets the outermost scope.
    /// </summary>
    public PascalScope Outer { get; } = new(parent: null, owner: null, isRecord: false);

    /// <summary>
    ///  Gets every scope, the outermost first.
    /// </summary>
    public List<PascalScope> Scopes { get; } = [];

    /// <summary>
    ///  Gets every declaration, in source order.
    /// </summary>
    public List<PascalDeclaration> Declarations { get; } = [];

    /// <summary>
    ///  Gets every name the source uses outside a declaration.
    /// </summary>
    public List<PascalReference> References { get; } = [];

    /// <summary>
    ///  Gets the documentation comments that document nothing: neither a file nor a declaration.
    /// </summary>
    public List<PascalDocComment> StrayDocs { get; } = [];

    /// <summary>
    ///  Analyzes a program from its main file, reading the files it includes from the same folder.
    /// </summary>
    /// <param name="root">The main file's path.</param>
    /// <param name="read">
    ///  Reads a file's text by path, or gives null when there is none: an open editor's text, or else the file's.
    /// </param>
    /// <returns>The program.</returns>
    public static PascalProgram Analyze(string root, Func<string, string?> read)
    {
        ArgumentNullException.ThrowIfNull(read);
        PascalProgram program = new(root);
        program.Scopes.Add(program.Outer);
        program.Read(root, read(root) ?? "", read, []);
        List<PascalToken> scanned =
        [
            .. program._tokens.Where(token => !token.IsComment || token.Kind == PascalTokenKind.DocComment)
        ];

        new Scanner(program, scanned).Run();
        program.IndexOldNames();
        return program;
    }

    /// <summary>
    ///  Gets a file of the program by path.
    /// </summary>
    /// <param name="path">The path.</param>
    /// <returns>The file, or null.</returns>
    public PascalSourceFile? File(string path) =>
        Files.FirstOrDefault(file => string.Equals(file.Path, path, StringComparison.OrdinalIgnoreCase));

    /// <summary>
    ///  Gets the token at a position in a file.
    /// </summary>
    /// <param name="path">The file.</param>
    /// <param name="line">The line, from 0.</param>
    /// <param name="column">The column, from 0.</param>
    /// <returns>The token, or null.</returns>
    public PascalToken? TokenAt(string path, int line, int column)
    {
        // Where one token ends and the next starts, as in "First.Value", the one that starts there.
        IReadOnlyList<PascalToken> tokens = File(path)?.Tokens ?? [];
        return tokens.FirstOrDefault(StartsHere) ?? tokens.FirstOrDefault(token => token.Contains(line, column));

        bool StartsHere(PascalToken token) =>
            token.Contains(line, column) && (token.EndLine != line || token.EndColumn != column);
    }

    /// <summary>
    ///  Finds the declaration a name at a position means: the one it declares, or the one it refers to, by its current
    ///  name or a historical one.
    /// </summary>
    /// <param name="path">The file.</param>
    /// <param name="line">The line, from 0.</param>
    /// <param name="column">The column, from 0.</param>
    /// <returns>The declaration and whether the name is a historical one; null when there is none.</returns>
    public (PascalDeclaration Declaration, bool Historical)? DeclarationAt(string path, int line, int column)
    {
        if (TokenAt(path, line, column) is not { Kind: PascalTokenKind.Identifier } token) { return null; }
        if (Declarations.FirstOrDefault(declaration => declaration.Token == token) is { } declared)
        {
            return (declared, false);
        }

        return References.FirstOrDefault(reference => reference.Token == token) is { } used ? Resolve(used) : null;
    }

    /// <summary>
    ///  Finds what a name used in the source means.
    /// </summary>
    /// <param name="reference">The name.</param>
    /// <returns>The declaration and whether the name is a historical one; null when there is none.</returns>
    public (PascalDeclaration Declaration, bool Historical)? Resolve(PascalReference reference)
    {
        ArgumentNullException.ThrowIfNull(reference);
        string key = PascalNames.Key(reference.Token.Text);
        PascalDeclaration? found = reference.AfterDot ? null : reference.Scope.Find(reference.Token.Text);

        // A field: after a ".", or inside a WITH, whose record the scan does not follow; any record's field of that
        // name. Elsewhere a bare name is never a field.
        if (reference.AfterDot || reference.InWith)
        {
            found ??= Declarations.FirstOrDefault(
                declaration => declaration.Kind == PascalDeclarationKind.Field && declaration.Key == key);
        }

        if (found is not null) { return (found, false); }
        return OldName(reference.Token.Text) is { } old ? (old, true) : null;
    }

    /// <summary>
    ///  Finds the declaration a historical name belongs to.
    /// </summary>
    /// <param name="name">The historical name.</param>
    /// <returns>The declaration, or null when no declaration, or more than one, gives it.</returns>
    public PascalDeclaration? OldName(string name) =>
        _oldNames.TryGetValue(name.ToUpperInvariant(), out List<PascalDeclaration>? owners) && owners.Count == 1
            ? owners[0]
            : null;

    /// <summary>
    ///  Gets the declarations that give each historical name.
    /// </summary>
    public IReadOnlyDictionary<string, List<PascalDeclaration>> OldNames => _oldNames;

    /// <summary>
    ///  Finds a declaration a link names: a name, or one qualified by the routines and records it is in
    ///  (<c>Outer.Inner</c>), or a historical name.
    /// </summary>
    /// <param name="target">The link's target.</param>
    /// <returns>The declaration, or null.</returns>
    public PascalDeclaration? FindLink(string target)
    {
        ArgumentNullException.ThrowIfNull(target);
        string[] parts = target.Split('.');
        string key = PascalNames.Key(parts[^1]);
        string path = string.Join('.', parts[..^1].Select(PascalNames.Key));
        return Declarations.FirstOrDefault(
                declaration => declaration.Key == key && (parts.Length == 1 || InPath(declaration)))
            ?? (parts.Length == 1 ? OldName(target) : null);

        // Whole names: "port.WriteLine" is not "Report.WriteLine".
        bool InPath(PascalDeclaration declaration)
        {
            string full = PathKey(declaration);
            return full == path || full.EndsWith($".{path}", StringComparison.Ordinal);
        }

        static string PathKey(PascalDeclaration declaration) =>
            string.Join('.', declaration.Scope.Path.Split('.').Select(PascalNames.Key));
    }

    private void Read(string path, string text, Func<string, string?> read, HashSet<string> reading)
    {
        List<PascalToken> tokens = PascalLexer.Tokenize(text, path);
        PascalSourceFile file = new(path, text, tokens);
        Files.Add(file);
        reading.Add(path.ToUpperInvariant());

        // The file's own documentation: its first (** *), after any ordinary comments and options, with a blank line or
        // the end after it.
        PascalToken? fileDoc = null;
        int first = tokens.FindIndex(token => !token.IsComment || token.Kind == PascalTokenKind.DocComment);
        if (first >= 0 && tokens[first].Kind == PascalTokenKind.DocComment)
        {
            bool blankAfter = first + 1 == tokens.Count || tokens[first + 1].Line > tokens[first].EndLine + 1;
            if (blankAfter)
            {
                fileDoc = tokens[first];
                file.Doc = PascalDocComment.Parse(fileDoc);
            }
        }

        foreach (PascalToken token in tokens)
        {
            if (token == fileDoc) { continue; }
            bool option = token.Kind is PascalTokenKind.Option or PascalTokenKind.BraceComment;
            if (option && IncludeName(token.Text) is { } name)
            {
                string? found = Locate(path, name, read);
                Includes.Add(new(token, name, found));
                if (found is not null && !reading.Contains(found.ToUpperInvariant()) && read(found) is { } included)
                {
                    Read(found, included, read, reading);
                }

                continue;
            }

            _tokens.Add(token);
        }

        reading.Remove(path.ToUpperInvariant());
    }

    // The name an include option gives, without its volume: (*$I NAME*), (*$I VOL:NAME.TEXT*) or {$I NAME}, not
    // (*$I+*) or (*$I-*).
    private static string? IncludeName(string text)
    {
        // An option still being typed has no "*)" or "}" yet.
        string body;
        if (text.StartsWith("{$", StringComparison.Ordinal))
        {
            body = text.EndsWith('}') && text.Length >= 3 ? text[2..^1] : text[2..];
        }
        else if (text.StartsWith("(*$", StringComparison.Ordinal))
        {
            body = text.EndsWith("*)", StringComparison.Ordinal) && text.Length >= 5 ? text[3..^2] : text[3..];
        }
        else
        {
            return null;
        }

        body = body.Trim();
        if (body.Length < 2 || char.ToUpperInvariant(body[0]) != 'I' || body[1] is '+' or '-' or ',') { return null; }
        // A name ends at a blank: an option still being typed has the rest of the text after it.
        string name = body[1..].Trim();
        int blank = name.IndexOfAny([' ', '\t', '\n']);
        name = blank >= 0 ? name[..blank] : name;
        int colon = name.IndexOf(':');
        name = colon >= 0 ? name[(colon + 1)..] : name;
        return name.Length > 0 ? name : null;
    }

    // Finds an included file beside the including one, its case left out, with .TEXT added when the name has no dot.
    private static string? Locate(string including, string name, Func<string, string?> read)
    {
        string folder = System.IO.Path.GetDirectoryName(including) ?? "";
        string wanted = name.Contains('.', StringComparison.Ordinal) ? name : name + ".TEXT";
        string direct = System.IO.Path.Join(folder, wanted);
        if (read(direct) is not null) { return direct; }
        try
        {
            if (Directory.Exists(folder))
            {
                foreach (string candidate in Directory.EnumerateFiles(folder))
                {
                    string candidateName = System.IO.Path.GetFileName(candidate);
                    if (string.Equals(candidateName, wanted, StringComparison.OrdinalIgnoreCase))
                    {
                        return candidate;
                    }
                }
            }
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            // A folder that can't be listed has no include to find.
        }

        return null;
    }

    private void IndexOldNames()
    {
        foreach (PascalDeclaration declaration in Declarations)
        {
            if (declaration.Doc is not { } doc) { continue; }
            foreach ((_, var also) in doc.Also)
            {
                if (also is null) { continue; }
                string name = also.Name.ToUpperInvariant();
                if (!_oldNames.TryGetValue(name, out List<PascalDeclaration>? owners))
                {
                    _oldNames[name] = owners = [];
                }

                if (!owners.Contains(declaration)) { owners.Add(declaration); }
            }
        }
    }
}
