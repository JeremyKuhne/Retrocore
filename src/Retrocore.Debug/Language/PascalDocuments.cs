// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Documentation;
using Retrocore.Pascal.Source;

namespace Retrocore.Debug.Language;

/// <summary>
///  The open Apple Pascal documents, each read as part of its program: the file in its folder that starts
///  <c>PROGRAM</c>, <c>UNIT</c> or <c>SEPARATE UNIT</c> and includes it. The lint's problems are published for each
///  open file.
/// </summary>
internal sealed class PascalDocuments
{
    // The suffixes of the files the extension opens as Pascal.
    private static readonly string[] s_suffixes = [".TEXT", ".PAS", ".PASCAL"];

    private readonly ILanguageClient _server;
    private readonly Lock _lock = new();
    private readonly Dictionary<string, string> _open = [with(StringComparer.OrdinalIgnoreCase)];
    private readonly Dictionary<string, PascalAnalysis> _programs = [with(StringComparer.OrdinalIgnoreCase)];

    /// <summary>
    ///  Creates the store.
    /// </summary>
    /// <param name="server">The server, to publish diagnostics.</param>
    public PascalDocuments(ILanguageClient server) => _server = server;

    /// <summary>
    ///  Gets whether a document is an open Pascal document.
    /// </summary>
    /// <param name="uri">The document.</param>
    /// <returns>Whether it is.</returns>
    internal bool IsOpen(DocumentUri uri)
    {
        string path = LanguageHost.PathOf(uri);
        lock (_lock)
        {
            return _open.ContainsKey(path);
        }
    }

    /// <summary>
    ///  Gets the program an open Pascal document is part of.
    /// </summary>
    /// <param name="uri">The document.</param>
    /// <returns>The program and the document's path, or null when it is not an open Pascal document.</returns>
    internal (PascalProgram Program, string Path)? Get(DocumentUri uri)
    {
        string path = LanguageHost.PathOf(uri);
        lock (_lock)
        {
            return _open.ContainsKey(path) ? (ProgramOf(path), path) : null;
        }
    }

    /// <summary>
    ///  Opens or updates a document.
    /// </summary>
    /// <param name="uri">The document.</param>
    /// <param name="text">Its text.</param>
    internal void Update(DocumentUri uri, string text)
    {
        string path = LanguageHost.PathOf(uri);
        lock (_lock)
        {
            _open[path] = text;
            _programs.Clear();
        }

        Publish(path);
    }

    /// <summary>
    ///  Updates an open document's text.
    /// </summary>
    /// <param name="uri">The document.</param>
    /// <param name="text">Its text.</param>
    /// <returns>Whether it is an open Pascal document.</returns>
    internal bool Change(DocumentUri uri, string text)
    {
        if (!IsOpen(uri)) { return false; }
        Update(uri, text);
        return true;
    }

    /// <summary>
    ///  Closes a document and clears its problems; the other open files of its program are checked again, with the
    ///  closed file as it is on disk.
    /// </summary>
    /// <param name="uri">The document.</param>
    /// <returns>Whether it was an open Pascal document.</returns>
    internal bool Close(DocumentUri uri)
    {
        string path = LanguageHost.PathOf(uri);
        List<string> others;
        lock (_lock)
        {
            if (!_open.ContainsKey(path)) { return false; }
            PascalProgram before = ProgramOf(path);
            _open.Remove(path);
            _programs.Clear();
            others = [.. _open.Keys.Where(file => before.File(file) is not null)];
        }

        _server.PublishDiagnostics(uri, []);
        foreach (string other in others)
        {
            Publish(other);
        }

        return true;
    }

    /// <summary>
    ///  Checks the open documents again after a file changed on disk, if one of their programs read it.
    /// </summary>
    internal void FilesChanged()
    {
        List<string> open;
        lock (_lock)
        {
            if (_programs.Values.All(analysis => analysis.IsCurrent())) { return; }
            open = [.. _open.Keys];
        }

        foreach (string path in open)
        {
            Publish(path);
        }
    }

    // Lints a file's program and publishes the problems of each of its open files.
    private void Publish(string path)
    {
        PascalProgram program;
        List<string> open;
        lock (_lock)
        {
            program = ProgramOf(path);
            open = [.. _open.Keys.Where(file => program.File(file) is not null)];
        }

        // A bibliography that can't be read leaves the Also: keys unchecked, rather than every one unknown.
        DocumentationBibliography? bibliography;
        try
        {
            bibliography = SourceBibliography.For(program.Root, program.Files.Select(file => file.Path));
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            bibliography = null;
        }

        List<PascalDiagnostic> problems = PascalLint.Check(program, bibliography);
        foreach (string file in open)
        {
            _server.PublishDiagnostics(
                DocumentUri.FromFileSystemPath(file),
                problems.Where(problem => string.Equals(problem.File, file, StringComparison.OrdinalIgnoreCase))
                    .Select(Convert));
        }
    }

    // The program a file is part of: the first main file in its folder that reads it, or else the file alone. An
    // analysis is kept until a document changes, or a file it read from disk does.
    private PascalProgram ProgramOf(string path)
    {
        foreach (string root in Roots(path))
        {
            if (!_programs.TryGetValue(root, out PascalAnalysis? analysis) || !analysis.IsCurrent())
            {
                analysis = Analyze(root);
                _programs[root] = analysis;
            }

            if (analysis.Program.File(path) is not null)
            {
                // Read by a main file now, it is no longer a program of its own.
                if (!string.Equals(root, path, StringComparison.OrdinalIgnoreCase)) { _programs.Remove(path); }
                return analysis.Program;
            }
        }

        // A file no main file reads is its own program, kept by its own path.
        if (!_programs.TryGetValue(path, out PascalAnalysis? alone) || !alone.IsCurrent())
        {
            alone = Analyze(path);
            _programs[path] = alone;
        }

        return alone.Program;
    }

    private PascalAnalysis Analyze(string root)
    {
        PascalProgram program = PascalProgram.Analyze(root, Read);

        // The files read from disk; the folders an include was looked for in, whose times change as a file in them
        // is added or removed; and the Pascal files beside them, any of which may become a main file that reads one.
        Dictionary<string, DateTime> stamps = [with(StringComparer.OrdinalIgnoreCase)];
        foreach (PascalSourceFile file in program.Files)
        {
            if (!_open.ContainsKey(file.Path)) { stamps[file.Path] = PascalAnalysis.Stamp(file.Path); }
            string folder = Path.GetDirectoryName(file.Path) ?? "";
            if (stamps.TryAdd(folder, PascalAnalysis.Stamp(folder)))
            {
                foreach (string beside in Beside(folder).Where(beside => !_open.ContainsKey(beside)))
                {
                    stamps.TryAdd(beside, PascalAnalysis.Stamp(beside));
                }
            }
        }

        return new(program, stamps);
    }

    // The Pascal files beside a file, itself first, that start a program or unit.
    private List<string> Roots(string path)
    {
        string folder = Path.GetDirectoryName(path) ?? "";
        IEnumerable<string> candidates = Beside(folder)
            .Concat(_open.Keys.Where(file => string.Equals(
                Path.GetDirectoryName(file),
                folder,
                StringComparison.OrdinalIgnoreCase)))
            .Prepend(path)
            .Distinct(StringComparer.OrdinalIgnoreCase);

        return [.. candidates.Where(file => Read(file) is { } text && IsMain(text))];
    }

    // The Pascal files in a folder; none when it can't be listed, which leaves only its open files.
    private static List<string> Beside(string folder)
    {
        try
        {
            return Directory.Exists(folder) ? [.. Directory.EnumerateFiles(folder).Where(IsPascal)] : [];
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            return [];
        }
    }

    private static bool IsPascal(string file) =>
        s_suffixes.Any(suffix => file.EndsWith(suffix, StringComparison.OrdinalIgnoreCase));

    // Whether a file's first word is PROGRAM, UNIT or SEPARATE.
    private static bool IsMain(string text) =>
        PascalLexer.Tokenize(text, "").FirstOrDefault(token => !token.IsComment) is { } first
            && (first.Is("PROGRAM") || first.Is("UNIT") || first.Is("SEPARATE"));

    // An open document's text, or else the file's; null for a file that isn't there or can't be read.
    private string? Read(string path)
    {
        if (_open.TryGetValue(path, out string? text)) { return text; }
        try
        {
            return File.Exists(path) ? File.ReadAllText(path) : null;
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            return null;
        }
    }

    private static Diagnostic Convert(PascalDiagnostic problem) => new()
    {
        Range = new LspRange(problem.Line, problem.Column, problem.Line, problem.EndColumn),
        Severity = problem.IsError ? DiagnosticSeverity.Error : DiagnosticSeverity.Warning,
        Source = "retrocore",
        Code = problem.Rule,
        Message = problem.Message
    };
}
