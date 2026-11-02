// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

/// <summary>
///  Caller-supplied immutable source text; no file I/O or compiler-host dependency.
/// </summary>
public sealed class AssemblySource
{
    /// <summary>
    ///  Creates a source document.
    /// </summary>
    /// <param name="text">The source text.</param>
    /// <param name="path">The source identifier.</param>
    /// <param name="dialect">Optional resolver-supplied syntax metadata.</param>
    public AssemblySource(string text, string path = "", AssemblyDialect? dialect = null)
    {
        Text = text ?? throw new ArgumentNullException(nameof(text));
        Path = path ?? throw new ArgumentNullException(nameof(path));
        if (dialect is { } value && !Enum.IsDefined(value)) { throw new ArgumentOutOfRangeException(nameof(dialect)); }
        Dialect = dialect;
    }

    /// <summary>
    ///  Gets original source text.
    /// </summary>
    public string Text { get; }

    /// <summary>
    ///  Gets the caller's source identifier.
    /// </summary>
    public string Path { get; }

    /// <summary>
    ///  Gets resolver-supplied dialect metadata, below a first-line pragma in precedence.
    /// </summary>
    public AssemblyDialect? Dialect { get; }
}
