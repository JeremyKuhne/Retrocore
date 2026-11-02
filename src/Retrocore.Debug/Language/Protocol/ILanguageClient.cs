// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug.Language;

/// <summary>
///  What the language server tells the client unasked.
/// </summary>
internal interface ILanguageClient
{
    /// <summary>
    ///  Replaces a document's problems in the Problems view.
    /// </summary>
    /// <param name="uri">The document.</param>
    /// <param name="diagnostics">Its problems; none clears them.</param>
    void PublishDiagnostics(DocumentUri uri, IEnumerable<Diagnostic> diagnostics);
}
