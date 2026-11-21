// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Documentation;

/// <summary>
///  One rule an <c>ignore=</c> pragma turns off, perhaps for one name, over a range of lines.
/// </summary>
/// <param name="Path">The source path.</param>
/// <param name="Line">The zero-based line of the pragma.</param>
/// <param name="Scope">Whether it covers the file, a line or a comment block.</param>
/// <param name="FirstLine">The first zero-based line it covers.</param>
/// <param name="LastLine">The last zero-based line it covers.</param>
/// <param name="Rule">The rule's ID.</param>
/// <param name="Name">The one name it covers, or null for all of the rule's diagnostics.</param>
public sealed record DocumentationExclusion(
    string Path,
    int Line,
    DocumentationExclusionScope Scope,
    int FirstLine,
    int LastLine,
    string Rule,
    string? Name)
{
    /// <summary>
    ///  Gets the exclusion as it is written: the rule, and the name after a colon.
    /// </summary>
    public string Written => Name is null ? Rule : $"{Rule}:{Name}";

    /// <summary>
    ///  Gets whether the exclusion turns off a diagnostic.
    /// </summary>
    /// <param name="diagnostic">The diagnostic, already known to be in the same file.</param>
    /// <returns>Whether it covers it.</returns>
    public bool Covers(DocumentationDiagnostic diagnostic) =>
        diagnostic.Rule == Rule
            && (Name is null || string.Equals(diagnostic.Name, Name, StringComparison.Ordinal))
            && diagnostic.Line >= FirstLine
            && diagnostic.Line <= LastLine;
}
