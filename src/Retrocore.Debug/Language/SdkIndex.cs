// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Collections.Concurrent;

namespace Retrocore.Debug.Language;

/// <summary>
///  The SDK's ROM sources, each assembled and its documentation parsed, for links to other modules and
///  workspace-wide search.
/// </summary>
/// <remarks>
///  <para>
///   The SDK's sources are read from disk, never from open documents, so one index serves every workspace in the
///   process; it is built once for each ROM directory unless that fails, on a thread of its own, as it takes seconds
///   and would otherwise hold a thread pool thread that a request or an analysis needs. A source changed on disk after it is
///   indexed is not read again until the process restarts.
///  </para>
///  <para>
///   An unreadable source is left out. Any other failure fails the whole index, because otherwise every link to the
///   missing modules would be reported as broken. A workspace given a failed index leaves the documentation checks
///   off, though it still searches what was indexed. A workspace created later builds the index again; the language
///   server has one workspace, so for it that takes a restart.
///  </para>
/// </remarks>
internal sealed class SdkIndex
{
    private static readonly ConcurrentDictionary<string, Lazy<SdkIndex>> s_indexes = new(StringComparer.Ordinal);

    private readonly List<SourceAnalysis> _analyses = [];

    private SdkIndex(string roms) => Completion = Task.Factory.StartNew(
        () => Build(roms),
        CancellationToken.None,
        TaskCreationOptions.LongRunning,
        TaskScheduler.Default);

    /// <summary>
    ///  Gets a task that completes once every source is indexed, or faults when the index failed.
    /// </summary>
    internal Task Completion { get; }

    /// <summary>
    ///  Gets the index of a ROM directory, starting to build it on first use, or again after it failed.
    /// </summary>
    /// <param name="roms">The SDK's ROM source directory.</param>
    /// <returns>The index.</returns>
    internal static SdkIndex For(string roms)
    {
        Lazy<SdkIndex> entry = s_indexes.GetOrAdd(roms, Start);
        if (entry.Value.Completion.IsFaulted)
        {
            // Only the failed entry is replaced, so workspaces asking at once share one new build.
            s_indexes.TryRemove(KeyValuePair.Create(roms, entry));
            entry = s_indexes.GetOrAdd(roms, Start);
        }

        return entry.Value;

        static Lazy<SdkIndex> Start(string directory) => new(() => new(directory));
    }

    /// <summary>
    ///  Gets the sources indexed so far.
    /// </summary>
    /// <returns>Their analyses.</returns>
    internal SourceAnalysis[] Analyses()
    {
        lock (_analyses)
        {
            return [.. _analyses];
        }
    }

    /// <summary>
    ///  Indexes one of the SDK's root sources, from disk: its assembly, and its documentation parsed.
    /// </summary>
    /// <param name="root">The root's full path.</param>
    /// <returns>The analysis.</returns>
    internal static SourceAnalysis Index(string root)
    {
        SourceAnalysis analysis = SourceAnalysis.Assemble(root, _ => null);

        // Parse its documentation now, so the first hover or completion that reaches the SDK isn't slowed.
        _ = analysis.Documentation;
        return analysis;
    }

    private void Build(string roms)
    {
        IEnumerable<string> roots = Directory.Exists(roms) ? SourceIncludes.Roots(roms) : [];
        foreach (string root in roots)
        {
            try
            {
                SourceAnalysis analysis = Index(root);
                lock (_analyses) { _analyses.Add(analysis); }
            }
            catch (IOException exception)
            {
                // An unreadable SDK file leaves its module out of search and of other modules' links.
                Console.Error.WriteLine($"The SDK source {root} could not be read: {exception.Message}");
            }
        }
    }
}
