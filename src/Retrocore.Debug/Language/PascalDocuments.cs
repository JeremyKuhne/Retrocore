// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Documentation;
using Retrocore.Pascal.Source;

namespace Retrocore.Debug.Language;

/// <summary>
///  The open Apple Pascal documents, each read as part of its program: the file in its folder that starts
///  <c>PROGRAM</c> or <c>UNIT</c> and includes it. The lint's problems are published for each open file.
/// </summary>
internal sealed class PascalDocuments
{
    private readonly ILanguageClient _server;
    private readonly Lock _lock = new();
    private readonly Dictionary<string, string> _open = [with(StringComparer.OrdinalIgnoreCase)];
    private readonly Dictionary<string, PascalProgram> _programs = [with(StringComparer.OrdinalIgnoreCase)];

    /// <summary>
    ///  Creates the store.
    /// </summary>
    /// <param name="server">The server, to publish diagnostics.</param>
    public PascalDocuments(ILanguageClient server) => _server = server;

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
        PascalProgram program;
        List<string> open;
        lock (_lock)
        {
            _open[path] = text;
            _programs.Clear();
            program = ProgramOf(path);
            open = [.. _open.Keys.Where(file => program.File(file) is not null)];
        }

        DocumentationBibliography bibliography = SourceBibliography.For(
            program.Root,
            program.Files.Select(file => file.Path));

        List<PascalDiagnostic> problems = PascalLint.Check(program, bibliography);
        foreach (string file in open)
        {
            _server.PublishDiagnostics(
                DocumentUri.FromFileSystemPath(file),
                problems.Where(problem => string.Equals(problem.File, file, StringComparison.OrdinalIgnoreCase))
                    .Select(Convert));
        }
    }

    /// <summary>
    ///  Updates an open document's text.
    /// </summary>
    /// <param name="uri">The document.</param>
    /// <param name="text">Its text.</param>
    /// <returns>Whether it is an open Pascal document.</returns>
    internal bool Change(DocumentUri uri, string text)
    {
        bool open;
        lock (_lock)
        {
            open = _open.ContainsKey(LanguageHost.PathOf(uri));
        }

        if (open)
        {
            Update(uri, text);
        }

        return open;
    }

    /// <summary>
    ///  Closes a document and clears its problems.
    /// </summary>
    /// <param name="uri">The document.</param>
    /// <returns>Whether it was an open Pascal document.</returns>
    internal bool Close(DocumentUri uri)
    {
        lock (_lock)
        {
            if (!_open.Remove(LanguageHost.PathOf(uri))) { return false; }
            _programs.Clear();
        }

        _server.PublishDiagnostics(uri, []);
        return true;
    }

    // The program a file is part of: the first main file in its folder that reads it, or else the file alone.
    private PascalProgram ProgramOf(string path)
    {
        foreach (string root in Roots(path))
        {
            if (!_programs.TryGetValue(root, out PascalProgram? program))
            {
                program = PascalProgram.Analyze(root, Read);
                _programs[root] = program;
            }

            if (program.File(path) is not null) { return program; }
        }

        return PascalProgram.Analyze(path, Read);
    }

    // The files beside a file, itself first, that start PROGRAM or UNIT.
    private IEnumerable<string> Roots(string path)
    {
        string folder = Path.GetDirectoryName(path) ?? "";
        IEnumerable<string> beside = Directory.Exists(folder)
            ? Directory.EnumerateFiles(folder).Where(file => file.EndsWith(".TEXT", StringComparison.OrdinalIgnoreCase))
            : [];

        IEnumerable<string> candidates = beside
            .Concat(_open.Keys.Where(file => string.Equals(Path.GetDirectoryName(file), folder, StringComparison.OrdinalIgnoreCase)))
            .Prepend(path)
            .Distinct(StringComparer.OrdinalIgnoreCase);

        return candidates.Where(file => Read(file) is { } text && IsMain(text));
    }

    // Whether a file's first word is PROGRAM or UNIT.
    private static bool IsMain(string text) =>
        PascalLexer.Tokenize(text, "").FirstOrDefault(token => !token.IsComment) is { } first
            && (first.Is("PROGRAM") || first.Is("UNIT"));

    private string? Read(string path) => _open.TryGetValue(path, out string? text)
        ? text
        : File.Exists(path) ? File.ReadAllText(path) : null;

    private static Diagnostic Convert(PascalDiagnostic problem) => new()
    {
        Range = new LspRange(problem.Line, problem.Column, problem.Line, problem.EndColumn),
        Severity = problem.IsError ? DiagnosticSeverity.Error : DiagnosticSeverity.Warning,
        Source = "retrocore",
        Code = problem.Rule,
        Message = problem.Message
    };
}
