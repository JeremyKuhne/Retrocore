// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Collections.Concurrent;
using Retrocore.Assembler;

namespace Retrocore.Debug.Language;

/// <summary>
///  The open documents and the assemblies they belong to.
/// </summary>
/// <remarks>
///  <para>
///   Each file is assembled as a root unless a root already assembled includes it (or, for a MACRO-10 base,
///   an overlay beside it names it), in which case the root is assembled instead. Open documents override disk
///   for every include.
///  </para>
/// </remarks>
internal sealed partial class LanguageWorkspace
{
    private static readonly TimeSpan s_settle = TimeSpan.FromMilliseconds(250);

    // The longest a request waits for a file's first assembly.
    private static readonly TimeSpan s_firstAnalysis = TimeSpan.FromSeconds(10);

    private readonly ILanguageClient _server;
    private readonly ConcurrentDictionary<string, string> _open = new(StringComparer.OrdinalIgnoreCase);
    private readonly ConcurrentDictionary<string, SourceAnalysis> _analyses = new(StringComparer.OrdinalIgnoreCase);
    private readonly ConcurrentDictionary<string, SourceAnalysis> _lastGood = new(StringComparer.OrdinalIgnoreCase);
    private readonly ConcurrentDictionary<string, string> _owners = new(StringComparer.OrdinalIgnoreCase);
    private readonly ConcurrentDictionary<string, CancellationTokenSource> _pending = new(StringComparer.OrdinalIgnoreCase);
    private readonly ConcurrentDictionary<string, HashSet<string>> _published = new(StringComparer.OrdinalIgnoreCase);
    private readonly List<SourceAnalysis> _sdk = [];

    // Set once the SDK's ROM sources are indexed; links to other modules resolve only after that.
    private volatile bool _sdkIndexed;

    // Requests waiting for a root's first assembly, completed when it is stored.
    private readonly ConcurrentDictionary<string, TaskCompletionSource> _assembled = new(StringComparer.OrdinalIgnoreCase);

    /// <summary>
    ///  Creates the workspace and starts indexing the SDK's ROM sources.
    /// </summary>
    /// <param name="server">The connection, for publishing diagnostics.</param>
    public LanguageWorkspace(ILanguageClient server)
    {
        _server = server;
        _ = Task.Run(IndexSdk);
    }

    /// <summary>
    ///  Gets the text of an open document.
    /// </summary>
    /// <param name="path">The full path.</param>
    /// <returns>The text, or null when it is not open.</returns>
    internal string? OpenText(string path) => _open.TryGetValue(path, out string? text) ? text : null;

    /// <summary>
    ///  Records a document's text and schedules its assembly.
    /// </summary>
    /// <param name="path">The full path.</param>
    /// <param name="text">The text.</param>
    internal void Update(string path, string text)
    {
        _open[path] = text;
        Schedule(RootOf(path));
    }

    /// <summary>
    ///  Forgets a closed document; disk is used for it from now on.
    /// </summary>
    /// <param name="path">The full path.</param>
    internal void Close(string path)
    {
        _open.TryRemove(path, out _);
        Schedule(RootOf(path));
    }

    /// <summary>
    ///  Gets the analysis a file belongs to, preferring one whose definitions are complete.
    /// </summary>
    /// <param name="path">The full path.</param>
    /// <returns>The analysis, or null before the first assembly finishes.</returns>
    internal SourceAnalysis? AnalysisOf(string path)
    {
        string root = RootOf(path);
        _analyses.TryGetValue(root, out SourceAnalysis? latest);
        if (latest is { Result.Success: true }) { return latest; }
        return _lastGood.TryGetValue(root, out SourceAnalysis? good) ? good : latest;
    }

    /// <summary>
    ///  Gets the analysis a file belongs to, waiting for its first assembly when it has none yet.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   For requests whose empty answer a client keeps, such as VS Code's outline: it asks for a document's
    ///   symbols as the document opens, and asks again only when the document changes.
    ///  </para>
    /// </remarks>
    /// <param name="path">The full path.</param>
    /// <param name="cancellation">Cancels the wait.</param>
    /// <returns>The analysis, or null when none arrives in time.</returns>
    internal async Task<SourceAnalysis?> AnalysisOfAsync(string path, CancellationToken cancellation)
    {
        if (AnalysisOf(path) is { } analysis) { return analysis; }
        TaskCompletionSource assembled = _assembled.GetOrAdd(
            RootOf(path),
            _ => new(TaskCreationOptions.RunContinuationsAsynchronously));

        // The assembly may have finished between the first look and registering the wait.
        if (AnalysisOf(path) is { } finished) { return finished; }
        try
        {
            await assembled.Task.WaitAsync(s_firstAnalysis, cancellation).ConfigureAwait(continueOnCapturedContext: false);
        }
        catch (TimeoutException)
        {
            // Answer with what there is.
        }

        return AnalysisOf(path);
    }

    /// <summary>
    ///  Gets every analysis, including the SDK's ROM sources, for workspace-wide search.
    /// </summary>
    /// <returns>The analyses.</returns>
    internal IEnumerable<SourceAnalysis> AllAnalyses()
    {
        lock (_sdk)
        {
            return [.. _analyses.Values, .. _sdk];
        }
    }

    /// <summary>
    ///  Gets the analyses of the SDK's ROM sources.
    /// </summary>
    /// <returns>The analyses.</returns>
    internal IEnumerable<SourceAnalysis> SdkAnalyses()
    {
        lock (_sdk)
        {
            return [.. _sdk];
        }
    }

    /// <summary>
    ///  Gets a file's lines: the open text, or disk.
    /// </summary>
    /// <param name="path">The full path.</param>
    /// <returns>The lines.</returns>
    internal string[] LinesOf(string path) =>
        SourceText.Lines(OpenText(path) ?? (File.Exists(path) ? File.ReadAllText(path) : ""));

    private string RootOf(string path)
    {
        if (_owners.TryGetValue(path, out string? root)) { return root; }
        return SourceIncludes.RootOf(path);
    }

    private void Schedule(string root)
    {
        CancellationTokenSource next = new();
        if (_pending.TryGetValue(root, out CancellationTokenSource? previous)) { previous.Cancel(); }
        _pending[root] = next;
        _ = Task.Run(async () =>
        {
            try
            {
                await Task.Delay(s_settle, next.Token);
                Analyze(root, next.Token);
            }
            catch (OperationCanceledException)
            {
                // A newer edit replaced this one.
            }
        });
    }

    private void Analyze(string root, CancellationToken cancellation)
    {
        if (OpenText(root) is null && !File.Exists(root)) { return; }
        SourceAnalysis analysis = SourceAnalysis.Assemble(root, OpenText);
        cancellation.ThrowIfCancellationRequested();
        _analyses[root] = analysis;
        if (analysis.Result.Success) { _lastGood[root] = analysis; }
        foreach (string member in analysis.Members) { _owners[member] = root; }
        if (_assembled.TryRemove(root, out TaskCompletionSource? waiting)) { waiting.TrySetResult(); }
        Publish(analysis);
    }

    private void Publish(SourceAnalysis analysis)
    {
        Dictionary<string, List<Diagnostic>> byFile = new(StringComparer.OrdinalIgnoreCase);
        foreach (string member in analysis.Members) { byFile[member] = []; }
        foreach (AssemblyDiagnostic diagnostic in analysis.Result.Diagnostics)
        {
            (string path, Diagnostic item) = Convert(diagnostic, analysis.Root);
            if (!byFile.TryGetValue(path, out List<Diagnostic>? list)) { byFile[path] = list = []; }
            list.Add(item);
        }

        // Before the SDK is indexed, every link to another module would look broken; IndexSdk checks again.
        IEnumerable<KeyValuePair<string, List<Diagnostic>>> documentationDiagnostics = _sdkIndexed
            ? DocumentationDiagnostics(analysis)
            : [];

        foreach ((string path, List<Diagnostic> documentation) in documentationDiagnostics)
        {
            if (!byFile.TryGetValue(path, out List<Diagnostic>? list)) { byFile[path] = list = []; }
            list.AddRange(documentation);
        }

        // Files this root reported before but no longer includes get their diagnostics cleared.
        HashSet<string> previous = _published.GetOrAdd(analysis.Root, _ => new(StringComparer.OrdinalIgnoreCase));
        lock (previous)
        {
            foreach (string stale in previous.Where(path => !byFile.ContainsKey(path)).ToList()) { byFile[stale] = []; }
            previous.Clear();
            previous.UnionWith(byFile.Where(pair => pair.Value.Count != 0).Select(pair => pair.Key));
        }

        foreach ((string path, List<Diagnostic> list) in byFile)
        {
            _server.PublishDiagnostics(DocumentUri.FromFileSystemPath(path), list);
        }
    }

    private (string Path, Diagnostic Diagnostic) Convert(AssemblyDiagnostic diagnostic, string root)
    {
        // Report where the error is; the include and macro chain is the related information.
        AssemblyLocation? location = diagnostic.Location;
        while (location is not null && !Path.IsPathFullyQualified(location.Path) && location.ExpandedFrom is not null)
        {
            location = location.ExpandedFrom;
        }

        string path = location is null || location.Path.Length == 0 ? root : Path.GetFullPath(location.Path);
        int line = location?.Line ?? 0;
        List<DiagnosticRelatedInformation> related = [];
        for (AssemblyLocation? from = location?.ExpandedFrom; from is not null; from = from.ExpandedFrom)
        {
            if (from.Path.Length == 0) { continue; }
            string fromPath = Path.GetFullPath(from.Path);
            related.Add(new()
            {
                Location = new()
                {
                    Uri = DocumentUri.FromFileSystemPath(fromPath),
                    Range = LineRange(fromPath, from.Line, from.Column)
                },
                Message = from.IsMacroExpansion ? "in this macro invocation" : "included here"
            });
        }

        return (path, new Diagnostic
        {
            Range = LineRange(path, line, location?.Column ?? 0),
            Severity = DiagnosticSeverity.Error,
            Code = diagnostic.Code,
            Source = "retrocore",
            Message = diagnostic.Message,
            RelatedInformation = related.Count == 0 ? null : related
        });
    }

    private LspRange LineRange(string path, int line, int column)
    {
        string[] lines = LinesOf(path);
        int length = line < lines.Length ? lines[line].Length : column;
        int start = Math.Min(column, length);
        return new LspRange(line, start, line, Math.Max(length, start));
    }

    private void IndexSdk()
    {
        string roms = SdkModules.RomDirectory;
        IEnumerable<string> roots = Directory.Exists(roms) ? SourceIncludes.Roots(roms) : [];
        foreach (string root in roots)
        {
            try
            {
                SourceAnalysis analysis = SourceAnalysis.Assemble(root, _ => null);

                // Parse its documentation now, so the first hover or completion that reaches the SDK isn't slowed.
                _ = analysis.Documentation;
                lock (_sdk) { _sdk.Add(analysis); }
            }
            catch (IOException)
            {
                // An unreadable SDK file only means fewer search results.
            }
        }

        // Check the documentation of what was analyzed while the index was building.
        _sdkIndexed = true;
        foreach (string root in _pending.Keys) { Schedule(root); }
    }

}
