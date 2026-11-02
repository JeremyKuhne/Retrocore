// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

/// <summary>
///  An immutable original source location. Lines and columns are zero-based.
/// </summary>
public sealed partial class AssemblyLocation
{
    private readonly object _source;

    /// <summary>
    ///  Creates a source location.
    /// </summary>
    /// <param name="path">The caller's source identifier.</param>
    /// <param name="line">The zero-based line.</param>
    /// <param name="column">The zero-based column.</param>
    /// <param name="expandedFrom">The enclosing macro invocation or include location.</param>
    public AssemblyLocation(string path, int line, int column = 0, AssemblyLocation? expandedFrom = null)
        : this(path, line, column, expandedFrom, macro: false)
    {
    }

    /// <summary>
    ///  Creates a source location that may be a macro body line.
    /// </summary>
    /// <param name="path">The caller's source identifier.</param>
    /// <param name="line">The zero-based line.</param>
    /// <param name="column">The zero-based column.</param>
    /// <param name="expandedFrom">The enclosing macro invocation or include location.</param>
    /// <param name="macro">Whether this is a macro body line, expanded at <paramref name="expandedFrom"/>.</param>
    internal AssemblyLocation(string path, int line, int column, AssemblyLocation? expandedFrom, bool macro)
    {
        ArgumentNullException.ThrowIfNull(path);
        if (line < 0 || column < 0) { throw new ArgumentOutOfRangeException(nameof(line)); }
        _source = expandedFrom is null ? path : new Expansion(path, expandedFrom, macro);
        Line = line;
        Column = column;
    }

    /// <summary>
    ///  Gets the source identifier.
    /// </summary>
    public string Path => _source switch
    {
        string path => path,
        Expansion expansion => expansion.Path,
        _ => throw new InvalidOperationException("Invalid source-location storage.")
    };

    /// <summary>
    ///  Gets the zero-based source line.
    /// </summary>
    public int Line { get; }

    /// <summary>
    ///  Gets the zero-based column.
    /// </summary>
    public int Column { get; }

    /// <summary>
    ///  Gets the enclosing expansion location, whose own ExpandedFrom continues the chain.
    /// </summary>
    public AssemblyLocation? ExpandedFrom => _source is Expansion expansion ? expansion.From : null;

    /// <summary>
    ///  Gets whether this is a macro body line, whose <see cref="ExpandedFrom"/> is the invocation, rather than a line
    ///  of an included file.
    /// </summary>
    public bool IsMacroExpansion => _source is Expansion { Macro: true };

    /// <summary>
    ///  Creates an equal location with its own identity, so each macro invocation from one line is distinct.
    /// </summary>
    /// <returns>A new location with the same path, line, column and expansion chain.</returns>
    internal AssemblyLocation Occurrence() => new(Path, Line, Column, ExpandedFrom, IsMacroExpansion);
}
