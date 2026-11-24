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
///   process; it is built once for each ROM directory, on a thread of its own, as it takes seconds and would
///   otherwise hold a thread pool thread that a request or an analysis needs.
///  </para>
/// </remarks>
internal sealed class SdkIndex
{
    private static readonly ConcurrentDictionary<string, Lazy<SdkIndex>> s_indexes = new(StringComparer.OrdinalIgnoreCase);

    private readonly List<SourceAnalysis> _analyses = [];

    private SdkIndex(string roms) => Completion = Task.Factory.StartNew(
        () => Build(roms),
        CancellationToken.None,
        TaskCreationOptions.LongRunning,
        TaskScheduler.Default);

    /// <summary>
    ///  Gets a task that completes once every source is indexed.
    /// </summary>
    internal Task Completion { get; }

    /// <summary>
    ///  Gets the index of a ROM directory, starting to build it on first use.
    /// </summary>
    /// <param name="roms">The SDK's ROM source directory.</param>
    /// <returns>The index.</returns>
    internal static SdkIndex For(string roms) =>
        s_indexes.GetOrAdd(roms, directory => new(() => new(directory))).Value;

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

    private void Build(string roms)
    {
        IEnumerable<string> roots = Directory.Exists(roms) ? SourceIncludes.Roots(roms) : [];
        foreach (string root in roots)
        {
            try
            {
                SourceAnalysis analysis = SourceAnalysis.Assemble(root, _ => null);

                // Parse its documentation now, so the first hover or completion that reaches the SDK isn't slowed.
                _ = analysis.Documentation;
                lock (_analyses) { _analyses.Add(analysis); }
            }
            catch (IOException)
            {
                // An unreadable SDK file only means fewer search results.
            }
        }
    }
}
