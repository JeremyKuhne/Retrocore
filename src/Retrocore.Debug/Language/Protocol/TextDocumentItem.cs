// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug.Language;

/// <summary>
///  A document as a request names it: its URI and, when it opens, its language and text.
/// </summary>
/// <param name="Uri">The document.</param>
/// <param name="LanguageId">Its language, when it opens.</param>
/// <param name="Text">Its text, when it opens.</param>
internal sealed record TextDocumentItem(DocumentUri Uri, string LanguageId, string Text);
