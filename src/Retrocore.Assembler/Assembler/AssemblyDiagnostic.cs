// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

/// <summary>
///  An immutable assembly-source/model error with an optional real source location.
/// </summary>
public sealed class AssemblyDiagnostic
{
    /// <summary>
    ///  Creates an actionable diagnostic.
    /// </summary>
    /// <param name="message">The error.</param>
    /// <param name="location">A real source location, or null for a programmatic node.</param>
    /// <param name="statementIndex">The affected model node, or -1 for a project-wide error.</param>
    internal AssemblyDiagnostic(string message, AssemblyLocation? location, int statementIndex = -1)
    {
        Message = message;
        Location = location;
        StatementIndex = statementIndex;
    }

    /// <summary>
    ///  Gets a stable diagnostic family.
    /// </summary>
    public string Code { get; } = "RETROCOREASM001";

    /// <summary>
    ///  Gets the actionable error.
    /// </summary>
    public string Message { get; }

    /// <summary>
    ///  Gets the original location, when present.
    /// </summary>
    public AssemblyLocation? Location { get; }

    /// <summary>
    ///  Gets the offending model index, when identifiable.
    /// </summary>
    public int StatementIndex { get; }
}
