// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Documentation;

/// <summary>
///  The documentation comments of one source file.
/// </summary>
/// <param name="Path">The source path.</param>
/// <param name="Comments">The comments in source order.</param>
/// <param name="Diagnostics">Placement and syntax problems.</param>
public sealed record DocumentationFile(
    string Path,
    IReadOnlyList<DocumentationComment> Comments,
    IReadOnlyList<DocumentationDiagnostic> Diagnostics)
{
    /// <summary>
    ///  Gets whether the file opts in to the style guide's checks (<c>; retrocore: style=strict</c>).
    /// </summary>
    public bool Strict { get; init; }
}
