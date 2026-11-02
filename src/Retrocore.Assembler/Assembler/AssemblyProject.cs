// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

/// <summary>
///  Editable input to the assembler: an ordered sequence of statements and optional original source documents.
/// </summary>
/// <remarks>
///  The assembler compiles <see cref="Statements"/>. Documents in <see cref="Sources"/> retain the original text
///  and are not reparsed when assembling this model.
/// </remarks>
public sealed class AssemblyProject
{
    private List<AssemblySectionDefinition>? _sectionDefinitions;

    /// <summary>
    ///  Creates an empty project.
    /// </summary>
    public AssemblyProject() => Statements = [];

    /// <summary>
    ///  Creates an empty project whose statement list starts with the given capacity.
    /// </summary>
    /// <param name="statementCapacity">The expected statement count.</param>
    internal AssemblyProject(int statementCapacity) => Statements = new List<AssemblyStatement>(statementCapacity);

    /// <summary>
    ///  Gets the editable collection of original source documents retained alongside the statements.
    /// </summary>
    public IList<AssemblySource> Sources { get; } = [];

    /// <summary>
    ///  Gets the statements in assembly order. Add, remove or edit statements to change the assembler input.
    /// </summary>
    public IList<AssemblyStatement> Statements { get; }

    /// <summary>
    ///  Gets section declarations in placement order. Statements select them with .section Name.
    /// </summary>
    public IList<AssemblySectionDefinition> SectionDefinitions => _sectionDefinitions ??= [];

    /// <summary>
    ///  Gets declarations without allocating the optional collection for native fixed-image projects.
    /// </summary>
    internal IReadOnlyList<AssemblySectionDefinition>? DeclaredSections => _sectionDefinitions;

    /// <summary>
    ///  Gets or sets the linker's implicit starting segment.
    /// </summary>
    internal string? InitialSection { get; set; }

    /// <summary>
    ///  Gets or sets the linker's MEMORY regions in configuration order.
    /// </summary>
    internal IReadOnlyList<AssemblyMemoryRegion>? MemoryRegions { get; set; }

    /// <summary>
    ///  Gets or sets the linker's SYMBOLS definitions in configuration order.
    /// </summary>
    internal IReadOnlyList<AssemblyLinkerSymbol>? LinkerSymbols { get; set; }

    /// <summary>
    ///  Gets or sets the private symbols that hold a label's statement size for .sizeof, keyed to the statement.
    /// </summary>
    internal Dictionary<string, int>? LabelSizes { get; set; }

    /// <summary>
    ///  Gets or sets Merlin source-name aliases without exposing mutable preprocessing state.
    /// </summary>
    internal Dictionary<string, string>? SymbolAliases { get; set; }

    /// <summary>
    ///  Gets or sets the in-memory Merlin output name.
    /// </summary>
    internal string? MerlinOutput { get; set; }
}
