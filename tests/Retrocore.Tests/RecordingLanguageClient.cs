// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Collections.Concurrent;
using Retrocore.Debug.Language;

namespace Retrocore.Tests;

/// <summary>
///  A language client that keeps the diagnostics the workspace publishes, by document.
/// </summary>
internal sealed class RecordingLanguageClient : ILanguageClient
{
    private readonly ConcurrentDictionary<string, List<Diagnostic>> _published = new(StringComparer.OrdinalIgnoreCase);

    /// <inheritdoc/>
    public void PublishDiagnostics(DocumentUri uri, IEnumerable<Diagnostic> diagnostics) =>
        _published[uri.Text] = [.. diagnostics];

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
