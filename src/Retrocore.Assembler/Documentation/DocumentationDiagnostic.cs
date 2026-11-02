// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Documentation;

/// <summary>
///  A problem found in documentation comments.
/// </summary>
/// <param name="Message">The description.</param>
/// <param name="Path">The source path.</param>
/// <param name="Line">The zero-based line.</param>
/// <param name="Severity">How serious it is.</param>
public sealed record DocumentationDiagnostic(string Message, string Path, int Line, DocumentationSeverity Severity);
