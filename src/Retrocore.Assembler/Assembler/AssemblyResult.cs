// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Isa;
using System.Collections.ObjectModel;

namespace Retrocore.Assembler;

/// <summary>
///  An immutable snapshot of output, symbols, layout mappings and assembly diagnostics.
/// </summary>
public sealed class AssemblyResult
{
    /// <summary>
    ///  Creates successful resolved output.
    /// </summary>
    /// <param name="image">The independent compiler output.</param>
    internal AssemblyResult(AssemblyImage image)
    {
        Sections = Array.AsReadOnly(image.Sections);
        Symbols = new ReadOnlyDictionary<string, long>(image.Symbols);
        Exports = new ReadOnlyDictionary<string, long>(image.Exports);
        HistoricalNames = HistoricalNamesOf(image);
        Files = image.Files is { } files ? new ReadOnlyDictionary<string, ReadOnlyMemory<byte>>(files) : EmptyFiles;
        SymbolAliases = image.Project.SymbolAliases is { } aliases
            ? new ReadOnlyDictionary<string, string>(new Dictionary<string, string>(aliases, StringComparer.Ordinal))
            : EmptyAliases;

        AssemblySymbol[] symbols = new AssemblySymbol[image.Symbols.Count];
        int symbolIndex = 0;
        foreach (KeyValuePair<string, long> pair in image.Symbols)
        {
            AssemblyStatement definition = image.Definitions[pair.Key];
            symbols[symbolIndex++] = new(
                pair.Key,
                pair.Value,
                definition.Kind is AssemblyStatementKind.Constant or AssemblyStatementKind.Variable,
                image.SymbolExports is { } exportedNames ? exportedNames.Contains(pair.Key) : image.Exports.ContainsKey(pair.Key),
                definition.Location);
        }

        SymbolDefinitions = Array.AsReadOnly(symbols);
        Diagnostics = [];
        Information = image.Information is { } information ? information.AsReadOnly() : [];
        Usings = image.Usings is { } usings ? usings.AsReadOnly() : [];
        // Copy final values rather than retaining editable nodes or pass state for later model edits to change.
        AssemblySourceMapEntry[] mappings = new AssemblySourceMapEntry[image.StatementCount];
        for (int index = 0; index < mappings.Length; index++)
        {
            ref LayoutStatement statement = ref image.Statements[index];
            mappings[index] = new(
                in statement,
                image.Project.Statements[statement.Line],
                FormName(image, in statement),
                statement.CpuIndex < image.InstructionSets.Count ? image.InstructionSets[statement.CpuIndex] : null);
        }

        SourceMap = Array.AsReadOnly(mappings);
    }

    /// <summary>
    ///  Creates failed output without pretending bytes were emitted.
    /// </summary>
    /// <param name="diagnostics">The errors.</param>
    internal AssemblyResult(AssemblyDiagnostic[] diagnostics)
    {
        Diagnostics = Array.AsReadOnly(diagnostics);
        Information = [];
        Usings = [];
        Sections = Array.AsReadOnly(Array.Empty<AssemblySection>());
        SourceMap = Array.AsReadOnly(Array.Empty<AssemblySourceMapEntry>());
        Symbols = new ReadOnlyDictionary<string, long>(new Dictionary<string, long>());
        Exports = Symbols;
        HistoricalNames = EmptyHistoricalNames;
        SymbolDefinitions = Array.AsReadOnly(Array.Empty<AssemblySymbol>());
        Files = EmptyFiles;
        SymbolAliases = EmptyAliases;
    }

    /// <summary>
    ///  Gets whether valid bytes were emitted.
    /// </summary>
    public bool Success => Diagnostics.Count == 0;

    /// <summary>
    ///  Gets absolute output sections.
    /// </summary>
    public IReadOnlyList<AssemblySection> Sections { get; }

    /// <summary>
    ///  Gets resolved labels and constants.
    /// </summary>
    public IReadOnlyDictionary<string, long> Symbols { get; }

    /// <summary>
    ///  Gets typed resolved symbol metadata.
    /// </summary>
    public IReadOnlyList<AssemblySymbol> SymbolDefinitions { get; }

    /// <summary>
    ///  Gets explicitly exported symbols.
    /// </summary>
    public IReadOnlyDictionary<string, long> Exports { get; }

    /// <summary>
    ///  Gets the definitions that the historical names in <c>;; Also:</c> sections reach, by historical name, each
    ///  with the value the name has; a name two definitions give is not here.
    /// </summary>
    public IReadOnlyDictionary<string, AssemblySymbol> HistoricalNames { get; }

    private static IReadOnlyDictionary<string, AssemblySymbol> EmptyHistoricalNames { get; } =
        new ReadOnlyDictionary<string, AssemblySymbol>(new Dictionary<string, AssemblySymbol>());

    private static IReadOnlyDictionary<string, AssemblySymbol> HistoricalNamesOf(AssemblyImage image) =>
        image.HistoricalNames is null
            ? EmptyHistoricalNames
            : new ReadOnlyDictionary<string, AssemblySymbol>(image.HistoricalNames);

    /// <summary>
    ///  Gets immutable output/source mappings.
    /// </summary>
    public IReadOnlyList<AssemblySourceMapEntry> SourceMap { get; }

    /// <summary>
    ///  Gets assembly errors.
    /// </summary>
    public IReadOnlyList<AssemblyDiagnostic> Diagnostics { get; }

    /// <summary>
    ///  Gets notes about a successful assembly that are not errors, such as a <c>.using</c> whose scopes give the
    ///  code no name, which an editor shows as unnecessary.
    /// </summary>
    public IReadOnlyList<AssemblyDiagnostic> Information { get; }

    /// <summary>
    ///  Gets the <c>.using</c> directives a successful assembly took, so documentation follows the same ones.
    /// </summary>
    public IReadOnlyList<AssemblyUsing> Usings { get; }

    private static IReadOnlyDictionary<string, ReadOnlyMemory<byte>> EmptyFiles { get; } =
        new ReadOnlyDictionary<string, ReadOnlyMemory<byte>>(new Dictionary<string, ReadOnlyMemory<byte>>());

    /// <summary>
    ///  Gets owned linked file images by configured filename; empty for native assembly or failed output.
    /// </summary>
    public IReadOnlyDictionary<string, ReadOnlyMemory<byte>> Files { get; }

    private static IReadOnlyDictionary<string, string> EmptyAliases { get; } =
        new ReadOnlyDictionary<string, string>(new Dictionary<string, string>());

    /// <summary>
    ///  Gets original Merlin names mapped to their collision-checked compiler identifiers.
    /// </summary>
    public IReadOnlyDictionary<string, string> SymbolAliases { get; }

    // The encoding's form name, as the source map reports it.
    private static string FormName(AssemblyImage image, in LayoutStatement statement)
    {
        if (statement.Encoding is not { } encoding) { return ""; }
        InstructionSet set = image.InstructionSets[statement.CpuIndex];
        return set.Forms[set.Encodings[encoding].Form].Name;
    }
}
