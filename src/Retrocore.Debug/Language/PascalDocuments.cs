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
        if (PathOf(uri) is not { } path) { return false; }
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
        if (PathOf(uri) is not { } path) { return null; }
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
        if (PathOf(uri) is not { } path) { return; }
        lock (_lock)
        {
            _open[path] = text;
            _programs.Clear();
        }

        // Every open file: one this changes may have joined or left this file's program.
        PublishAll();
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
    ///  Closes a document and clears its problems; the other open files are checked again, with the closed file as it
    ///  is on disk.
    /// </summary>
    /// <param name="uri">The document.</param>
    /// <returns>Whether it was an open Pascal document.</returns>
    internal bool Close(DocumentUri uri)
    {
        if (PathOf(uri) is not { } path) { return false; }
        lock (_lock)
        {
            if (!_open.Remove(path)) { return false; }
            _programs.Clear();
        }

        _server.PublishDiagnostics(uri, []);
        PublishAll();
        return true;
    }

    /// <summary>
    ///  Checks the open documents again after a file changed on disk, if one of their programs read it or a file
    ///  beside it.
    /// </summary>
    internal void FilesChanged()
    {
        // Each open file's program is kept from when it was last published, so a current set has nothing new.
        lock (_lock)
        {
            if (_programs.Values.All(analysis => analysis.IsCurrent())) { return; }
        }

        PublishAll();
    }

    // Lints each open file's program, once for each, and publishes each open file's problems.
    private void PublishAll()
    {
        List<(PascalProgram Program, List<string> Files)> programs = [];
        lock (_lock)
        {
            foreach (string path in _open.Keys)
            {
                PascalProgram program = ProgramOf(path);
                int index = programs.FindIndex(entry => entry.Program == program);
                if (index < 0) { programs.Add((program, [path])); }
                else { programs[index].Files.Add(path); }
            }
        }

        foreach ((PascalProgram program, List<string> files) in programs)
        {
            List<PascalDiagnostic> problems = PascalLint.Check(program, Bibliography(program));
            foreach (string file in files)
            {
                _server.PublishDiagnostics(
                    DocumentUri.FromFileSystemPath(file),
                    problems.Where(problem => string.Equals(problem.File, file, StringComparison.OrdinalIgnoreCase))
                        .Select(Convert));
            }
        }
    }

    /// <summary>
    ///  Gets the documents a program's <c>Also:</c> sections may cite, or null when they can't be read, which leaves
    ///  the keys unchecked rather than every one unknown.
    /// </summary>
    /// <param name="program">The program.</param>
    /// <returns>The bibliography, or null.</returns>
    internal static DocumentationBibliography? Bibliography(PascalProgram program)
    {
        try
        {
            return SourceBibliography.For(program.Root, program.Files.Select(file => file.Path));
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            return null;
        }
    }

    // A file document's path; null for one that is not a file.
    private static string? PathOf(DocumentUri uri)
    {
        try
        {
            return LanguageHost.PathOf(uri);
        }
        catch (ArgumentException)
        {
            return null;
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
            // In name order, so that the main file a shared include is read with is the same everywhere.
            return Directory.Exists(folder)
                ? [.. Directory.EnumerateFiles(folder).Where(IsPascal).Order(StringComparer.OrdinalIgnoreCase)]
                : [];
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
