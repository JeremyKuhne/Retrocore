// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Documentation;
using Retrocore.Isa;

namespace Retrocore.Debug;

/// <summary>
///  Debug information read directly from an assembly's source map, for any dialect.
/// </summary>
/// <remarks>
///  <para>
///   Each emitted statement keeps its full macro chain. A source line applies only while memory holds the bytes
///   that statement assembled to, so a module built from SDK sources can describe a ROM dump wherever the two
///   agree, and RAM code that has since been overwritten shows no stale source.
///  </para>
/// </remarks>
internal sealed partial class SourceMapModule : IDebugModule
{
    // Compiler-generated names: private scope labels, Merlin macro locals and loop counters, and variable versions.
    private static readonly string[] s_internalMarkers = ["__retro_", "__merlin_", "__Merlin", "#"];

    private readonly Statement[] _statements;
    private readonly Dictionary<ushort, int> _byAddress = [];

    // The earlier statements at an address that a later one also covers, as code assembled for where it is copied
    // overlaps code assembled where it is stored; the one whose bytes memory holds applies.
    private readonly Dictionary<ushort, List<int>> _overlapped = [];
    private readonly Dictionary<string, Dictionary<int, List<ushort>>> _entries = [with(StringComparer.OrdinalIgnoreCase)];
    private readonly Dictionary<string, long> _symbols = [with(StringComparer.OrdinalIgnoreCase)];
    private readonly (string Name, long Value)[] _labels;
    private readonly (string Name, long Value, IsaDescription Cpu)[] _addressConstants;
    private readonly Dictionary<string, string[]> _sourceText = [with(StringComparer.OrdinalIgnoreCase)];
    private readonly AssemblyResult _result;
    private readonly int _relocation;
    private readonly bool _wholeImage;
    private DocumentationSet? _documentation;

    /// <summary>
    ///  Reads an assembly's source map.
    /// </summary>
    /// <param name="result">The successful assembly.</param>
    /// <param name="area">The memory area the code runs from, or null for whatever the memory map selects.</param>
    /// <param name="collapseSingleStatementMacros">
    ///  Whether an invocation that emits one statement debugs as its call line rather than stepping into the macro,
    ///  as for MACRO-10 sources that define instructions as macros.
    /// </param>
    /// <param name="relocation">
    ///  How far the code runs from where it was assembled, added to its statements' and labels' addresses but not to
    ///  its constants: for code that uses no absolute address inside itself, such as a slot ROM that works in any slot.
    /// </param>
    /// <param name="wholeImage">
    ///  Whether the module applies only while memory holds every byte it assembled, not just the statement's: for a
    ///  card's firmware, whose first instructions other cards' ROMs share.
    /// </param>
    internal SourceMapModule(
        AssemblyResult result,
        Enum? area,
        bool collapseSingleStatementMacros = false,
        int relocation = 0,
        bool wholeImage = false)
    {
        ArgumentNullException.ThrowIfNull(result);
        Area = area;
        _result = result;
        _relocation = relocation;
        _wholeImage = wholeImage;

        // Statements emit in source order, so each invocation's statements are contiguous.
        List<(ushort Address, byte[] Bytes, List<AssemblyLocation> Levels)> emitted = [];
        Dictionary<AssemblyLocation, int> invocationSizes = [with(ReferenceEqualityComparer.Instance)];
        foreach (AssemblySourceMapEntry entry in result.SourceMap)
        {
            if (entry.Size == 0 || entry.Location is not { } location) { continue; }
            List<AssemblyLocation> levels = [location];
            for (AssemblyLocation level = location; level.IsMacroExpansion && level.ExpandedFrom is { } call; level = call)
            {
                levels.Add(call);
                invocationSizes[call] = invocationSizes.GetValueOrDefault(call) + 1;
            }

            byte[] bytes = result.Sections[entry.Section].Bytes.Slice(entry.Offset, entry.Size).ToArray();
            emitted.Add((checked((ushort)(entry.Address + relocation)), bytes, levels));
        }

        HashSet<AssemblyLocation> started = [with(ReferenceEqualityComparer.Instance)];
        HashSet<AssemblyLocation> previous = [with(ReferenceEqualityComparer.Instance)];
        _statements = new Statement[emitted.Count];
        for (int index = 0; index < emitted.Count; index++)
        {
            (ushort address, byte[] bytes, List<AssemblyLocation> levels) = emitted[index];

            // A single-statement invocation debugs as its call line when collapsing is requested.
            List<AssemblyLocation> kept = [];
            for (int level = 0; level < levels.Count; level++)
            {
                bool macro = level < levels.Count - 1;
                if (!macro || !collapseSingleStatementMacros || invocationSizes[levels[level + 1]] != 1)
                {
                    kept.Add(levels[level]);
                }
            }

            // The invocations this statement starts are the innermost kept levels whose call is new.
            int entryDepth = 0;
            while (entryDepth < kept.Count - 1 && started.Add(Invocation(kept[entryDepth]))) { entryDepth++; }

            SourceLine[] chain = new SourceLine[kept.Count];
            for (int level = 0; level < kept.Count; level++)
            {
                AssemblyLocation location = kept[level];
                string? name = level < kept.Count - 1 ? CallText(Invocation(location)) : null;
                chain[level] = new(Path.GetFullPath(location.Path), location.Line + 1, name);

                // Every statement starts its innermost line; an outer line starts where its occurrence begins.
                if (level == 0 || !previous.Contains(location)) { Entry(chain[level], address); }
            }

            previous.Clear();
            previous.UnionWith(kept);
            _statements[index] = new(address, bytes, chain, entryDepth);
            for (int offset = 0; offset < bytes.Length; offset++)
            {
                ushort at = (ushort)(address + offset);
                if (_byAddress.TryGetValue(at, out int earlier))
                {
                    if (!_overlapped.TryGetValue(at, out List<int>? list)) { _overlapped[at] = list = []; }
                    list.Add(earlier);
                }

                _byAddress[at] = index;
            }
        }

        Dictionary<string, string> sourceNames = [with(StringComparer.Ordinal)];
        foreach (KeyValuePair<string, string> alias in result.SymbolAliases) { sourceNames[alias.Value] = alias.Key; }

        List<(string Name, long Value)> labels = [];
        foreach (AssemblySymbol symbol in result.SymbolDefinitions)
        {
            string name = sourceNames.TryGetValue(symbol.Name, out string? source) ? source : symbol.Name;
            if (s_internalMarkers.Any(marker => name.Contains(marker, StringComparison.Ordinal))) { continue; }

            // A scoped name resolves qualified, and by its plain name when that is unambiguous enough to be first.
            long value = symbol.IsConstant ? symbol.Value : symbol.Value + relocation;
            _symbols[name] = value;
            int separator = name.LastIndexOf("::", StringComparison.Ordinal);
            if (separator >= 0) { _symbols.TryAdd(name[(separator + 2)..], value); }
            if (!symbol.IsConstant) { labels.Add((name, value)); }
        }

        _labels = [.. labels.OrderBy(label => label.Value).ThenBy(label => label.Name, StringComparer.Ordinal)];
        _addressConstants = AddressConstantsOf(result, sourceNames, relocation);
    }

    /// <inheritdoc/>
    public IEnumerable<(string Name, long Value, IsaDescription Cpu)> AddressConstants => _addressConstants;

    // The constants an instruction addresses memory through, as STA CH or LDA (BASL),Y do: a constant the operand
    // names whose value is the address the instruction's bytes encode, its memory operand or pointer, or on the 6809
    // an indirect or PC-relative postbyte's address. Matching the value leaves out an immediate value, an index's
    // offset and a term added to another address, and picks the right one of names that differ only in case or scope.
    private static (string Name, long Value, IsaDescription Cpu)[] AddressConstantsOf(
        AssemblyResult result,
        Dictionary<string, string> sourceNames,
        int relocation)
    {
        // Each constant by the names an operand can spell it with: its own, the source's alias, and the last part of
        // a scoped name.
        Dictionary<string, List<AssemblySymbol>> byName = [with(StringComparer.OrdinalIgnoreCase)];
        void Add(string name, AssemblySymbol symbol)
        {
            if (!byName.TryGetValue(name, out List<AssemblySymbol>? list)) { byName[name] = list = []; }
            if (!list.Contains(symbol)) { list.Add(symbol); }
        }

        foreach (AssemblySymbol symbol in result.SymbolDefinitions)
        {
            if (!symbol.IsConstant || symbol.Value is < 0 or > 0xFFFF) { continue; }
            string display = sourceNames.TryGetValue(symbol.Name, out string? source) ? source : symbol.Name;
            if (s_internalMarkers.Any(marker => display.Contains(marker, StringComparison.Ordinal))) { continue; }
            foreach (string name in (string[])[symbol.Name, display])
            {
                Add(name, symbol);
                int separator = name.LastIndexOf("::", StringComparison.Ordinal);
                if (separator >= 0) { Add(name[(separator + 2)..], symbol); }
            }
        }

        if (byName.Count == 0) { return []; }
        HashSet<(AssemblySymbol Symbol, IsaDescription Cpu)> found = [];
        foreach (AssemblySourceMapEntry entry in result.SourceMap)
        {
            if (entry.Size == 0 || entry.InstructionSet is not { } isa) { continue; }
            ReadOnlySpan<byte> bytes = result.Sections[entry.Section].Bytes.Span.Slice(entry.Offset, entry.Size);
            if (EncodedAddress(bytes, (ushort)(entry.Address + relocation), isa) is not { } address) { continue; }
            foreach (AssemblySymbol symbol in OperandConstants(entry.Operand, byName))
            {
                if (symbol.Value == address) { found.Add((symbol, isa.Description)); }
            }
        }

        return [.. found.Select(item => (
                sourceNames.TryGetValue(item.Symbol.Name, out string? source) ? source : item.Symbol.Name,
                item.Symbol.Value,
                item.Cpu))
            .OrderBy(item => item.Item2)
            .ThenBy(item => item.Item1, StringComparer.Ordinal)];
    }

    // The address an instruction's bytes give it to access: a memory or pointer operand, or a postbyte's pointer or
    // PC-relative target; null for immediate values, registers, offsets from a register and branches.
    private static ushort? EncodedAddress(ReadOnlySpan<byte> bytes, ushort address, InstructionSet isa)
    {
        if (!Disassembler.TryDecode(bytes, address, isa, out DisassembledInstruction instruction)) { return null; }
        OperandForm form = instruction.Form;
        if (form.FieldCount == 0) { return null; }
        if (form.HasPostbyte)
        {
            return instruction.PostbyteReference == PostbyteReference.None ? null : instruction.Field(0);
        }

        return form.Role == OperandRole.None ? null : instruction.Operand;
    }

    // The constants an operand's names can mean.
    private static IEnumerable<AssemblySymbol> OperandConstants(
        string operand,
        Dictionary<string, List<AssemblySymbol>> byName)
    {
        int index = 0;
        while (index < operand.Length)
        {
            char character = operand[index];
            if (character == ';') { yield break; }
            if (character is '\'' or '"')
            {
                int close = operand.IndexOf(character, index + 1);
                index = close < 0 ? operand.Length : close + 1;
                continue;
            }

            if (!(char.IsAsciiLetter(character) || character is '_' or '.' or '@' or '?'))
            {
                // A number's digits, as in $C0E8, are not a name.
                if (character is '$' or '%' || char.IsAsciiDigit(character))
                {
                    index++;
                    while (index < operand.Length && char.IsAsciiLetterOrDigit(operand[index])) { index++; }
                }
                else
                {
                    index++;
                }

                continue;
            }

            int start = index;
            while (index < operand.Length && (char.IsAsciiLetterOrDigit(operand[index]) || operand[index] is '_' or '.' or '@' or '?' or ':'))
            {
                index++;
            }

            string token = operand[start..index];
            if (!byName.TryGetValue(token, out List<AssemblySymbol>? symbols)) { continue; }
            foreach (AssemblySymbol symbol in symbols) { yield return symbol; }
        }
    }

    /// <inheritdoc/>
    public Enum? Area { get; }

    /// <inheritdoc/>
    public DocumentationSet Documentation => _documentation ??= DocumentationSet.Create(
        DebugDocumentation.Parse(_result.SourceMap
            .SelectMany(entry => Levels(entry.Location))
            .Where(path => path.Length != 0)
            .Select(Path.GetFullPath)),
        _result,
        relocation: _relocation);

    /// <inheritdoc/>
    public DebugPosition? Position(IDebugMemory memory, ushort address)
    {
        if (!_byAddress.TryGetValue(address, out int index)) { return null; }
        if (Applies(memory, index)) { return At(index, address); }
        if (!_overlapped.TryGetValue(address, out List<int>? earlier)) { return null; }
        for (int candidate = earlier.Count - 1; candidate >= 0; candidate--)
        {
            if (Applies(memory, earlier[candidate])) { return At(earlier[candidate], address); }
        }

        return null;
    }

    // Whether a statement applies: memory holds its bytes, and for a whole image, every statement's.
    private bool Applies(IDebugMemory memory, int index)
    {
        if (!Holds(memory, _statements[index])) { return false; }
        if (_wholeImage)
        {
            foreach (Statement other in _statements)
            {
                if (!Holds(memory, other)) { return false; }
            }
        }

        return true;
    }

    // A statement's position, entering its macro levels only at its first byte.
    private DebugPosition At(int index, ushort address)
    {
        Statement statement = _statements[index];
        return new(statement.Chain, address == statement.Address ? statement.EntryDepth : 0);
    }

    // Whether memory holds the bytes a statement assembled to, where it runs.
    private static bool Holds(IDebugMemory memory, Statement statement)
    {
        for (int offset = 0; offset < statement.Bytes.Length; offset++)
        {
            if (memory.Peek((ushort)(statement.Address + offset)) != statement.Bytes[offset]) { return false; }
        }

        return true;
    }

    /// <inheritdoc/>
    public IEnumerable<ushort> Entries(string path, int line)
    {
        bool found = _entries.TryGetValue(Path.GetFullPath(path), out Dictionary<int, List<ushort>>? lines);
        return found && lines is not null && lines.TryGetValue(line, out List<ushort>? addresses) ? addresses : [];
    }

    /// <inheritdoc/>
    public IEnumerable<(string Name, long Value)> Labels => _labels;

    /// <inheritdoc/>
    public bool TryResolve(string name, out long value) => _symbols.TryGetValue(name.TrimStart('.'), out value);

    // A location and the macro and include lines it came from.
    private static IEnumerable<string> Levels(AssemblyLocation? location)
    {
        for (AssemblyLocation? level = location; level is not null; level = level.ExpandedFrom)
        {
            yield return level.Path;
        }
    }

    /// <inheritdoc/>
    public string? Label(ushort address)
    {
        string? label = null;
        foreach ((string name, long value) in _labels)
        {
            if (value > address) { break; }
            label = name;
        }

        return label;
    }

    private static AssemblyLocation Invocation(AssemblyLocation body) =>
        body.ExpandedFrom ?? throw new InvalidOperationException("A macro body line has an invocation.");

    private void Entry(SourceLine line, ushort address)
    {
        if (!_entries.TryGetValue(line.Path, out Dictionary<int, List<ushort>>? lines))
        {
            lines = [];
            _entries.Add(line.Path, lines);
        }

        if (!lines.TryGetValue(line.Line, out List<ushort>? addresses))
        {
            addresses = [];
            lines.Add(line.Line, addresses);
        }

        addresses.Add(address);
    }

    /// <summary>
    ///  Gets an invocation's source text as a stack frame name, such as <c>inner 7</c>.
    /// </summary>
    /// <param name="call">The invocation's location.</param>
    /// <returns>The trimmed line without its comment, or the file and line when the source cannot be read.</returns>
    private string CallText(AssemblyLocation call)
    {
        if (!_sourceText.TryGetValue(call.Path, out string[]? lines))
        {
            try
            {
                lines = File.ReadAllLines(call.Path);
            }
            catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or ArgumentException)
            {
                lines = [];
            }

            _sourceText.Add(call.Path, lines);
        }

        if (call.Line >= lines.Length) { return $"{Path.GetFileName(call.Path)}:{call.Line + 1}"; }
        string text = lines[call.Line];
        int comment = text.IndexOf(';');
        return (comment < 0 ? text : text[..comment]).Trim();
    }
}
