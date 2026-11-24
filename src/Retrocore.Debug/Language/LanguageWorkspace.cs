// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using System.Collections.Concurrent;

namespace Retrocore.Debug.Language;

/// <summary>
///  The open documents and the assemblies they belong to.
/// </summary>
/// <remarks>
///  <para>
///   Each file is assembled as a root unless a root already assembled includes it (or, for a MACRO-10 base,
///   an overlay names it), in which case the root is assembled instead. Open documents override disk for every
///   include.
///  </para>
/// </remarks>
internal sealed partial class LanguageWorkspace
{
    private static readonly TimeSpan s_settle = TimeSpan.FromMilliseconds(250);

    private readonly ILanguageClient _server;
    private readonly ConcurrentDictionary<string, string> _open = new(StringComparer.OrdinalIgnoreCase);
    private readonly ConcurrentDictionary<string, SourceAnalysis> _analyses = new(StringComparer.OrdinalIgnoreCase);
    private readonly ConcurrentDictionary<string, SourceAnalysis> _lastGood = new(StringComparer.OrdinalIgnoreCase);
    private readonly ConcurrentDictionary<string, string> _owners = new(StringComparer.OrdinalIgnoreCase);
    private readonly ConcurrentDictionary<string, CancellationTokenSource> _pending = new(StringComparer.OrdinalIgnoreCase);
    private readonly ConcurrentDictionary<string, HashSet<string>> _published = new(StringComparer.OrdinalIgnoreCase);
    private readonly SdkIndex _sdk;

    // Set once the SDK's ROM sources are indexed; links to other modules resolve only after that.
    private volatile bool _sdkIndexed;

    // Each root's latest scheduled analysis, from when it is scheduled until it ends: stored, failed, skipped, or
    // replaced by a newer one, which then takes its place.
    private readonly ConcurrentDictionary<string, CancellationTokenSource> _inFlight = new(StringComparer.OrdinalIgnoreCase);
    private readonly Lock _scheduling = new();

    // Requests waiting on a root, released each time an analysis of it is stored and when its latest attempt ends.
    private readonly ConcurrentDictionary<string, TaskCompletionSource> _assembled = new(StringComparer.OrdinalIgnoreCase);

    /// <summary>
    ///  Creates the workspace and starts indexing the SDK's ROM sources, unless another workspace already has.
    /// </summary>
    /// <param name="server">The connection, for publishing diagnostics.</param>
    public LanguageWorkspace(ILanguageClient server)
    {
        _server = server;
        _sdk = SdkIndex.For(SdkModules.RomDirectory);
        // A failed index leaves the documentation checks off, because missing modules would make every link to them
        // look broken. The failure is reported here, so it is observed.
        _ = _sdk.Completion.ContinueWith(
            indexing =>
            {
                if (indexing.Exception is { } failure)
                {
                    Console.Error.WriteLine($"The SDK's ROM sources could not be indexed: {failure.GetBaseException()}");
                    return;
                }

                SdkIndexed();
            },
            CancellationToken.None,
            TaskContinuationOptions.None,
            TaskScheduler.Default);
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
        if (Path.GetExtension(path).Equals(".cfg", StringComparison.OrdinalIgnoreCase))
        {
            ConfigurationChanged(path);
            return;
        }

        Schedule(RootOf(path));
    }

    /// <summary>
    ///  Forgets a closed document; disk is used for it from now on.
    /// </summary>
    /// <param name="path">The full path.</param>
    internal void Close(string path)
    {
        _open.TryRemove(path, out _);
        if (Path.GetExtension(path).Equals(".cfg", StringComparison.OrdinalIgnoreCase))
        {
            ConfigurationChanged(path);
            return;
        }

        Schedule(RootOf(path));
    }

    /// <summary>
    ///  Reanalyzes roots that use a changed companion configuration.
    /// </summary>
    /// <param name="path">The configuration's full path.</param>
    internal void ConfigurationChanged(string path)
    {
        foreach (string root in _analyses.Keys.Concat(_pending.Keys).Distinct(StringComparer.OrdinalIgnoreCase))
        {
            if (string.Equals(Path.ChangeExtension(root, ".cfg"), path, StringComparison.OrdinalIgnoreCase))
            {
                Schedule(root);
            }
        }
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
    ///  <para>
    ///   The wait has no fixed limit: a large root, such as AppleSoft's, takes seconds on a slow or busy machine, and
    ///   an answer given up early stays empty though the analysis goes on. It lasts while an analysis of the root is
    ///   scheduled or running, and ends when one is stored or the latest attempt ends without one, as when it fails
    ///   or the file is gone; with nothing scheduled, it answers at once.
    ///  </para>
    /// </remarks>
    /// <param name="path">The full path.</param>
    /// <param name="cancellation">Cancels the wait.</param>
    /// <returns>The analysis, or null when the file has none and none is coming.</returns>
    internal async Task<SourceAnalysis?> AnalysisOfAsync(string path, CancellationToken cancellation)
    {
        string root = RootOf(path);
        while (true)
        {
            if (AnalysisOf(path) is { } analysis) { return analysis; }
            TaskCompletionSource released = Released(root);

            // The assembly may have finished between the first look and registering the wait.
            if (AnalysisOf(path) is { } finished) { return finished; }
            if (!_inFlight.ContainsKey(root)) { return null; }
            await released.Task.WaitAsync(cancellation).ConfigureAwait(continueOnCapturedContext: false);
        }
    }

    /// <summary>
    ///  Waits until no analysis of a file's root is scheduled or running: every edit made so far is analyzed, or its
    ///  attempt has ended.
    /// </summary>
    /// <param name="path">The full path.</param>
    /// <param name="cancellation">Cancels the wait.</param>
    /// <returns>A task that completes when the root is idle.</returns>
    internal async Task IdleAsync(string path, CancellationToken cancellation)
    {
        string root = RootOf(path);
        while (true)
        {
            TaskCompletionSource released = Released(root);
            if (!_inFlight.ContainsKey(root)) { return; }
            await released.Task.WaitAsync(cancellation).ConfigureAwait(continueOnCapturedContext: false);
        }
    }

    // The task Release completes next for a root. A waiter takes it before checking whether an attempt is in flight,
    // and an attempt leaves _inFlight before it releases, so a waiter that saw one in flight is released.
    private TaskCompletionSource Released(string root) =>
        _assembled.GetOrAdd(root, _ => new(TaskCreationOptions.RunContinuationsAsynchronously));

    /// <summary>
    ///  Gets every analysis, including the SDK's ROM sources, for workspace-wide search.
    /// </summary>
    /// <returns>The analyses.</returns>
    internal IEnumerable<SourceAnalysis> AllAnalyses() => [.. _analyses.Values, .. _sdk.Analyses()];

    /// <summary>
    ///  Gets the analyses of the SDK's ROM sources.
    /// </summary>
    /// <returns>The analyses.</returns>
    internal IEnumerable<SourceAnalysis> SdkAnalyses() => _sdk.Analyses();

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

        // Edits and the reanalysis after the SDK is indexed schedule from different threads; one at a time, each
        // replaces the one before. The new attempt is in flight before the old one is canceled, so the old one's end,
        // which may run inline in Cancel, does not release the waiters.
        lock (_scheduling)
        {
            _inFlight[root] = next;
            if (_pending.TryGetValue(root, out CancellationTokenSource? previous)) { previous.Cancel(); }
            _pending[root] = next;
        }

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
            finally
            {
                // Waiters go on with what there is once the latest attempt ends, whether or not it stored one.
                if (_inFlight.TryRemove(KeyValuePair.Create(root, next))) { Release(root); }
            }
        });
    }

    // Lets the requests waiting on a root look again.
    private void Release(string root)
    {
        if (_assembled.TryRemove(root, out TaskCompletionSource? waiting)) { waiting.TrySetResult(); }
    }

    private void Analyze(string root, CancellationToken cancellation)
    {
        if (OpenText(root) is null && !File.Exists(root)) { return; }
        SourceAnalysis analysis = SourceAnalysis.Assemble(root, OpenText);
        cancellation.ThrowIfCancellationRequested();
        _analyses[root] = analysis;
        if (analysis.Result.Success) { _lastGood[root] = analysis; }
        foreach (string member in analysis.Members) { _owners[member] = root; }
        Release(root);
        Publish(analysis);
    }

    private void Publish(SourceAnalysis analysis)
    {
        Dictionary<string, List<Diagnostic>> byFile = [with(StringComparer.OrdinalIgnoreCase)];
        foreach (string member in analysis.Members) { byFile[member] = []; }
        foreach (AssemblyDiagnostic diagnostic in analysis.Result.Diagnostics)
        {
            (string path, Diagnostic item) = Convert(diagnostic, analysis.Root);
            if (!byFile.TryGetValue(path, out List<Diagnostic>? list)) { byFile[path] = list = []; }
            list.Add(item);
        }

        // Notes that are not errors, such as a .using nothing needs, show as unnecessary code.
        foreach (AssemblyDiagnostic note in analysis.Result.Information)
        {
            (string path, Diagnostic item) = Convert(note, analysis.Root);
            if (!byFile.TryGetValue(path, out List<Diagnostic>? list)) { byFile[path] = list = []; }
            list.Add(item.Unnecessary());
        }

        // Before the SDK is indexed, every link to another module would look broken; SdkIndexed checks again.
        IEnumerable<KeyValuePair<string, List<Diagnostic>>> documentationDiagnostics = _sdkIndexed
            ? DocumentationDiagnostics(analysis)
            : [];

        foreach ((string path, List<Diagnostic> documentation) in documentationDiagnostics)
        {
            if (!byFile.TryGetValue(path, out List<Diagnostic>? list)) { byFile[path] = list = []; }
            list.AddRange(documentation);
        }

        // Files this root reported before but no longer includes get their diagnostics cleared.
        HashSet<string> previous = _published.GetOrAdd(analysis.Root, _ => [with(StringComparer.OrdinalIgnoreCase)]);
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

    private void SdkIndexed()
    {
        // Check the documentation of what was analyzed while the index was building.
        _sdkIndexed = true;
        foreach (string root in _pending.Keys) { Schedule(root); }
    }

}
