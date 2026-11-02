// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Basic;

namespace Retrocore.Debug.Language;

/// <summary>
///  An open BASIC document and what it holds.
/// </summary>
/// <param name="Uri">The document.</param>
/// <param name="LanguageId">Its VS Code language.</param>
/// <param name="Text">Its text.</param>
/// <param name="Source">Its analysis.</param>
/// <param name="Note">Why the document is not analyzed, such as an unsupported dialect; null when it is.</param>
internal sealed record BasicDocument(DocumentUri Uri, string LanguageId, string Text, BasicSource Source, string? Note);
