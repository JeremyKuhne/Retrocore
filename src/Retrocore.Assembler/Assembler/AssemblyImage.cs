// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Isa;

namespace Retrocore.Assembler;

/// <summary>
///  A fully resolved build-time ROM image and its explicitly exported symbols.
/// </summary>
internal sealed class AssemblyImage
{
    /// <summary>
    ///  Creates a compiled ROM result.
    /// </summary>
    /// <param name="sections">The complete padded sections, the options' section first.</param>
    /// <param name="exports">Exported addresses and constants.</param>
    /// <param name="symbols">All resolved symbols.</param>
    /// <param name="definitions">The already validated source definitions, consumed while creating the result.</param>
    /// <param name="statements">Independent layout state.</param>
    /// <param name="statementCount">The populated layout entries.</param>
    /// <param name="project">Transient original syntax, consumed when source maps are copied.</param>
    internal AssemblyImage(
        AssemblySection[] sections,
        Dictionary<string, long> exports,
        Dictionary<string, long> symbols,
        Dictionary<string, AssemblyStatement> definitions,
        LayoutStatement[] statements,
        int statementCount,
        AssemblyProject project)
    {
        Sections = sections;
        Exports = exports;
        Symbols = symbols;
        Definitions = definitions;
        Statements = statements;
        StatementCount = statementCount;
        Project = project;
    }

    /// <summary>
    ///  Gets the instruction sets statements were encoded with, indexed by <see cref="LayoutStatement.CpuIndex"/>.
    /// </summary>
    internal IReadOnlyList<InstructionSet> InstructionSets { get; init; } = [];

    /// <summary>
    ///  Gets all resolved labels and constants.
    /// </summary>
    internal Dictionary<string, long> Symbols { get; }

    /// <summary>
    ///  Gets transient source definitions; the public result copies their metadata rather than retaining nodes.
    /// </summary>
    internal Dictionary<string, AssemblyStatement> Definitions { get; }

    /// <summary>
    ///  Gets the layout storage; only the first <see cref="StatementCount"/> entries are populated.
    /// </summary>
    internal LayoutStatement[] Statements { get; }

    /// <summary>
    ///  Gets the populated layout entry count.
    /// </summary>
    internal int StatementCount { get; }

    /// <summary>
    ///  Gets transient syntax; the public result does not retain the editable project.
    /// </summary>
    internal AssemblyProject Project { get; set; }

    /// <summary>
    ///  Gets or sets resolved symbol names exported through plain public aliases.
    /// </summary>
    internal HashSet<string>? SymbolExports { get; set; }

    /// <summary>
    ///  Gets the assembled sections in declaration order, the options' section first.
    /// </summary>
    internal AssemblySection[] Sections { get; }

    /// <summary>
    ///  Gets exported addresses and constants.
    /// </summary>
    internal Dictionary<string, long> Exports { get; }

    /// <summary>
    ///  Gets or sets linked file images; null for native section-only assembly.
    /// </summary>
    internal Dictionary<string, ReadOnlyMemory<byte>>? Files { get; set; }
}
