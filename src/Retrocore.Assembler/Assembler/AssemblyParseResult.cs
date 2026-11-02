// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

/// <summary>
///  Typed parse output; invalid assembly is represented by diagnostics rather than an empty success.
/// </summary>
public sealed class AssemblyParseResult
{
    /// <summary>
    ///  Creates a parse result.
    /// </summary>
    /// <param name="project">The parsed model.</param>
    /// <param name="diagnostics">Source errors.</param>
    internal AssemblyParseResult(AssemblyProject project, AssemblyDiagnostic[] diagnostics)
    {
        Project = project;
        Diagnostics = diagnostics.Length == 0 ? Array.Empty<AssemblyDiagnostic>() : Array.AsReadOnly(diagnostics);
    }

    /// <summary>
    ///  Gets the editable parsed model.
    /// </summary>
    public AssemblyProject Project { get; }

    /// <summary>
    ///  Gets source diagnostics.
    /// </summary>
    public IReadOnlyList<AssemblyDiagnostic> Diagnostics { get; }

    /// <summary>
    ///  Gets whether parsing succeeded.
    /// </summary>
    public bool Success => Diagnostics.Count == 0;
}
