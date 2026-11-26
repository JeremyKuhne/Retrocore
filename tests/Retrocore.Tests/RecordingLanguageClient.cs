// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Collections.Concurrent;
using Retrocore.Debug.Language;

namespace Retrocore.Tests;

/// <summary>
///  A language client that keeps the diagnostics the workspace publishes, by document, with the hints that fade the
///  lines conditional assembly left out kept apart (<see cref="Inactive"/>).
/// </summary>
internal sealed class RecordingLanguageClient : ILanguageClient
{
    private readonly ConcurrentDictionary<string, List<Diagnostic>> _published = new(StringComparer.OrdinalIgnoreCase);
    private readonly ConcurrentDictionary<string, List<Diagnostic>> _inactive = new(StringComparer.OrdinalIgnoreCase);

    /// <inheritdoc/>
    public void PublishDiagnostics(DocumentUri uri, IEnumerable<Diagnostic> diagnostics)
    {
        List<Diagnostic> all = [.. diagnostics];
        _inactive[uri.Text] = [.. all.Where(IsInactive)];
        _published[uri.Text] = [.. all.Where(diagnostic => !IsInactive(diagnostic))];
    }

    /// <summary>
    ///  Gets the hints last published for a document that fade the lines its conditional assembly left out.
    /// </summary>
    /// <param name="uri">The document.</param>
    /// <returns>The hints, none before the document's first diagnostics.</returns>
    public List<Diagnostic> Inactive(DocumentUri uri) => _inactive.TryGetValue(uri.Text, out List<Diagnostic>? found) ? found : [];

    private static bool IsInactive(Diagnostic diagnostic) =>
        diagnostic.IsUnnecessary && diagnostic.Severity == DiagnosticSeverity.Hint;

    /// <summary>
    ///  Waits for a document's diagnostics to meet a condition, for up to a minute.
    /// </summary>
    /// <param name="uri">The document.</param>
    /// <param name="done">The condition.</param>
    /// <returns>The diagnostics that met it, or the last published when none did.</returns>
    public async Task<List<Diagnostic>> Wait(DocumentUri uri, Func<List<Diagnostic>, bool> done)
    {
        for (int attempt = 0; attempt < 1200; attempt++)
        {
            if (_published.TryGetValue(uri.Text, out List<Diagnostic>? found) && done(found)) { return found; }
            await Task.Delay(50);
        }

        return _published.TryGetValue(uri.Text, out List<Diagnostic>? last) ? last : [];
    }
}
