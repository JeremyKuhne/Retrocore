// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using System.Globalization;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace Retrocore.Debug;

// retro/memory/export: a range of memory as native assembly, for Retrocore Memory's Save as .asm.
internal sealed partial class DebugSession
{
    // How many times an analysis that fails drops the entry points its errors are at and runs again.
    private const int ExportRetries = 4;

    // A name the native assembler takes as a label: scoped and local names, such as Main::@1loop, are left out.
    [GeneratedRegex("^[A-Za-z_][A-Za-z0-9_]*$")]
    private static partial Regex ExportName();

    /// <summary>
    ///  Answers retro/memory/export: a range of a memory view's space as native assembly that assembles back to the
    ///  same bytes.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   For a <c>memoryReference</c>, an <c>address</c> and a <c>count</c>, with the editor's Decode from here
    ///   <c>starts</c>: the <c>source</c>, through the disassembler's exporter. What the listing knows decides what is
    ///   code: the sources' statements, the hints file's marks, the starts and the analysis's guesses; the session's
    ///   labels name the range's addresses, and those outside it it refers to, as equates; the hints file's comments
    ///   go above their lines. The source is assembled again, and <c>exact</c> says it gave the same bytes; where it
    ///   would not, the range is saved as <c>.byte</c> lines, which always do, and <c>exact</c> is false.
    ///  </para>
    /// </remarks>
    private JsonObject MemoryExport(JsonObject args)
    {
        MemoryReference(Required(args, "memoryReference"), out DebugMemoryBank? bank);
        int from = args.Int("address") ?? throw new ArgumentException("address is required.");
        int count = args.Int("count") ?? throw new ArgumentException("count is required.");
        if (from is < 0 or > 0xFFFF || count is < 1 or > 0x10000 || from + count > 0x10000)
        {
            throw new ArgumentOutOfRangeException(nameof(args), "A range to save is in $0000-$FFFF.");
        }

        SpaceAnalysis analysis = AnalyzeSpace(bank, args);
        ListingMemory memory = analysis.Memory;
        byte[] image = new byte[count];
        for (int index = 0; index < count; index++)
        {
            int address = from + index;
            if (!memory.Readable(address))
            {
                throw new InvalidOperationException($"There is no byte at ${address:X4} to save.");
            }

            image[index] = memory.Peek((ushort)address);
        }

        // Every byte of a Decode from here start's instruction, which the listing decodes even in data.
        HashSet<int> forcedBytes = [];
        foreach (int start in analysis.Forced)
        {
            int size = analysis.MarkedCode.TryGetValue(start, out int marked) ? marked : InstructionSize(bank, start);
            for (int index = 0; index < size && start + index <= 0xFFFF; index++) { forcedBytes.Add(start + index); }
        }

        // What the listing shows as data, and where it shows instructions start.
        bool Data(int address)
        {
            if (forcedBytes.Contains(address)) { return false; }
            if (analysis.Marked(address)) { return true; }
            DebugPosition? position = analysis.Position(address);
            return position is null ? analysis.Guesses.Kinds[address] == GuessKind.Data : position.Data;
        }

        List<AnalysisRegion> regions = [];
        int run = -1;
        for (int address = from; address <= from + count; address++)
        {
            bool data = address < from + count && Data(address);
            if (data && run < 0) { run = address; }
            if (!data && run >= 0)
            {
                regions.Add(new AnalysisRegion(run, address - run, AnalysisRegionKind.Data));
                run = -1;
            }
        }

        HashSet<ushort> entries = [];
        for (int address = from; address < from + count; address++)
        {
            if (Data(address)) { continue; }
            DebugPosition? position = analysis.Position(address);
            bool start = analysis.Forced.Contains(address)
                || (position is { Data: false, Start: { } statement } && statement == address)
                || (position is null && analysis.Guesses.Kinds[address] == GuessKind.Start);

            if (start) { entries.Add((ushort)address); }
        }

        // The session's names that the native assembler takes, each once, the first address's winning; names are
        // case-sensitive, so TABLE and table are two.
        Dictionary<ushort, string> names = [];
        HashSet<string> used = [with(StringComparer.Ordinal)];
        foreach ((int address, string name) in analysis.Labels.Concat(analysis.Names))
        {
            if (names.ContainsKey((ushort)address) || !ExportName().IsMatch(name) || !used.Add(name)) { continue; }
            names[(ushort)address] = name;
        }

        Dictionary<ushort, string> comments = [];
        foreach ((int address, string comment) in MarkHints.Comments(HintSpace(bank)))
        {
            if (address >= from && address < from + count) { comments[(ushort)address] = comment; }
        }

        bool vectors = bank is null || bank.InstructionSet is not null;
        DisassemblyResult? result = ExportAnalysis(image, from, analysis, regions, entries, names, comments, vectors);
        string? source = result?.ExportSource();
        bool exact = result is not null && source is not null && AssemblesTo(source, result, image);
        if (!exact)
        {
            // Bytes, which assemble to themselves, with the names and comments the range has.
            result = ExportAnalysis(
                image,
                from,
                analysis,
                [new AnalysisRegion(from, count, AnalysisRegionKind.Data)],
                [],
                names,
                comments,
                vectors);

            source = result?.ExportSource()
                ?? throw new InvalidOperationException($"${from:X4}-${from + count - 1:X4} could not be saved as assembly.");
        }

        string what = bank?.Label ?? "Memory";
        string heading = string.Create(
            CultureInfo.InvariantCulture,
            $"; {what}: ${from:X4}-${from + count - 1:X4}, {count} bytes, saved from Retrocore Memory.\n");

        if (!exact)
        {
            heading += "; Its instructions would not assemble back to the same bytes, so it is saved as bytes.\n";
        }

        return new JsonObject { ["source"] = heading + "\n" + source, ["exact"] = exact };
    }

    // Analyzes the range for export, leaving out the names the disassembler refuses and the outside names the code
    // never refers to, and dropping the entry points an error is at; null if it still fails.
    private static DisassemblyResult? ExportAnalysis(
        byte[] image,
        int from,
        SpaceAnalysis analysis,
        List<AnalysisRegion> regions,
        HashSet<ushort> entries,
        Dictionary<ushort, string> names,
        Dictionary<ushort, string> comments,
        bool vectors)
    {
        HashSet<ushort> starts = [.. entries];
        Dictionary<ushort, string> symbols = [];
        foreach ((ushort address, string name) in names)
        {
            if (address >= from && address < from + image.Length) { symbols[address] = name; }
        }

        for (int attempt = 0; attempt <= ExportRetries; attempt++)
        {
            DisassemblyResult result = Disassembler.Analyze(ExportProject(image, from, analysis, regions, starts, symbols, comments, vectors));

            // The outside names the code refers to become equates; those the analysis refuses come out.
            bool changed = false;
            foreach (DisassemblyReference reference in result.References)
            {
                ushort target = reference.Target;
                if (!symbols.ContainsKey(target) && names.TryGetValue(target, out string? name))
                {
                    symbols[target] = name;
                    changed = true;
                }
            }

            foreach (DisassemblyDiagnostic diagnostic in result.Diagnostics.Where(diagnostic => diagnostic.Code == "RCDIS002"))
            {
                changed |= symbols.Remove(diagnostic.Address);
            }

            if (changed) { continue; }
            if (result.Success) { return result; }
            int before = starts.Count;
            foreach (DisassemblyDiagnostic diagnostic in result.Diagnostics.Where(diagnostic => diagnostic.IsError))
            {
                starts.Remove(diagnostic.Address);
            }

            if (starts.Count == before) { return null; }
        }

        return null;
    }

    private static AnalysisProject ExportProject(
        byte[] image,
        int from,
        SpaceAnalysis analysis,
        List<AnalysisRegion> regions,
        HashSet<ushort> starts,
        Dictionary<ushort, string> symbols,
        Dictionary<ushort, string> comments,
        bool vectors)
    {
        AnalysisProject project = new(image, from, analysis.Set) { CpuVectors = vectors };
        project.EntryPoints.Clear();
        foreach (ushort start in starts.Order()) { project.EntryPoints.Add(start); }
        foreach (AnalysisRegion region in regions) { project.Regions.Add(region); }
        foreach ((ushort address, string name) in symbols) { project.Symbols[address] = name; }
        foreach ((ushort address, string comment) in comments) { project.Comments[address] = comment; }
        return project;
    }

    // Whether exported source assembles to the bytes it came from.
    private static bool AssemblesTo(string source, DisassemblyResult result, byte[] image)
    {
        AssemblyResult assembled = new Assembler.Assembler().Assemble(new AssemblySource(source, "memory.asm"), result.Options);
        return assembled.Success
            && assembled.Sections.Count > 0
            && assembled.Sections[0].Bytes.Span.SequenceEqual(image);
    }
}
