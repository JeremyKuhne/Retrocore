// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Documentation;

namespace Retrocore.Debug;

/// <summary>
///  Debug information from a cc65 <c>.dbg</c> or VICE label file, for programs built by other tools.
/// </summary>
/// <param name="symbols">The loaded file.</param>
/// <param name="area">
///  The memory area the program it describes was loaded into, or null when the debugger did not load it, such as
///  a program a booted disk loads.
/// </param>
internal sealed class DebugFileModule(SymbolTable symbols, Enum? area = null) : IDebugModule
{
    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The file names no memory area: its lines apply where the launch loaded the program, or whatever the
    ///   memory map selects when the launch loaded none.
    ///  </para>
    /// </remarks>
    public Enum? Area => area;

    /// <inheritdoc/>
    public DebugPosition? Position(IDebugMemory memory, ushort address) =>
        symbols.Location(address) is { } location ? new([new(location.Path, location.Line)], EntryDepth: 0) : null;

    /// <inheritdoc/>
    public IEnumerable<ushort> Entries(string path, int line) => symbols.Addresses(path, line);

    /// <inheritdoc/>
    public bool TryResolve(string name, out long value) => symbols.TryResolve(name, out value);

    /// <inheritdoc/>
    public string? Label(ushort address) => symbols.Label(address);

    /// <inheritdoc/>
    public DocumentationSet Documentation => field ??= DocumentationSet.Create(
        DebugDocumentation.Parse(symbols.Paths),
        symbols.Labels);
}
