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
    /// <remarks>
    ///  <para>
    ///   A position's statement is the smallest debug span covering the address; the file does not say which bytes
    ///   are data, so none are.
    ///  </para>
    /// </remarks>
    public DebugPosition? Position(IDebugMemory memory, ushort address)
    {
        if (symbols.Location(address) is not { } location) { return null; }
        (ushort Start, int Size)? span = symbols.Span(address);
        return new([new(location.Path, location.Line)], EntryDepth: 0, span?.Start, span?.Size ?? 0);
    }

    /// <inheritdoc/>
    public IEnumerable<ushort> Entries(string path, int line) => symbols.Addresses(path, line);

    /// <inheritdoc/>
    public bool TryResolve(string name, out long value) => symbols.TryResolve(name, out value);

    /// <inheritdoc/>
    public string? Label(ushort address) => symbols.Label(address);

    /// <inheritdoc/>
    public IEnumerable<(string Name, long Value)> Labels =>
        symbols.AddressLabels.Select(pair => (pair.Key, pair.Value));

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   A debug file's labels apply wherever the module does: it does not check memory's bytes, and a VICE label
    ///   file has labels without source lines.
    ///  </para>
    /// </remarks>
    public bool LabelApplies(IDebugMemory memory, ushort address) => true;

    /// <inheritdoc/>
    public DocumentationSet Documentation => field ??= DocumentationSet.Create(
        DebugDocumentation.Parse(symbols.Paths),
        symbols.Labels);
}
