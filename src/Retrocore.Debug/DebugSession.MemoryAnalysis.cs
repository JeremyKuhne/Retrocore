// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Isa;

namespace Retrocore.Debug;

// Retrocore Memory's guesses at which bytes no source describes are code and which are data.
internal sealed partial class DebugSession
{
    // The register that holds where the CPU runs, the analysis's first entry point.
    private const string ProgramCounter = "PC";

    // The last analysis, kept while its space's bytes and entry points stay the same, as they do while scrolling.
    private MemoryGuesses? _guesses;

    // Where each request reads the space to compare with the last analysis's bytes; it becomes those bytes when they
    // differ, so a request where nothing changed allocates nothing.
    private byte[] _guessScratch = new byte[0x10000];

    /// <summary>
    ///  Analyzes a space from its entry points, or gives the last analysis where nothing it used has changed.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   Each run of readable bytes is analyzed alone, so a pointer is never read from bytes that cannot be read.
    ///   A Decode from here start is the user's: it is an instruction before anything is inferred, so no inferred
    ///   instruction can claim its bytes. A statement the sources make data stays data, so analysis does not run
    ///   through it as code, unless a Decode from here start is in it.
    ///  </para>
    /// </remarks>
    private MemoryGuesses Guess(
        DebugMemoryBank? bank,
        ListingMemory memory,
        InstructionSet set,
        IEnumerable<int> entries,
        HashSet<int> forced,
        Func<int, DebugPosition?> position)
    {
        byte[] image = _guessScratch;
        image.AsSpan().Clear();
        List<int> runs = [];
        int run = -1;
        for (int address = 0; address <= 0x10000; address++)
        {
            bool readable = address <= 0xFFFF && memory.Readable(address);
            if (readable)
            {
                image[address] = memory.Peek((ushort)address);
                if (run < 0) { run = address; }
            }
            else if (run >= 0)
            {
                runs.Add(run);
                runs.Add(address - run);
                run = -1;
            }
        }

        int[] ordered = [.. entries.Where(entry => entry is >= 0 and <= 0xFFFF && memory.Readable(entry)).Distinct().Order()];
        int[] starts = [.. forced.Where(start => memory.Readable(start)).Order()];
        string space = bank?.Name ?? "";
        int modules = _debug.Modules.Count();
        if (_guesses is { } last
            && last.Space == space
            && last.Modules == modules
            && last.Entries.AsSpan().SequenceEqual(ordered)
            && last.Starts.AsSpan().SequenceEqual(starts)
            && last.Runs.AsSpan().SequenceEqual(runs.ToArray())
            && last.Image.AsSpan().SequenceEqual(image))
        {
            return last;
        }

        List<int> after = [];
        List<AnalysisRegion> regions = [.. StartRegions(image, set, starts, after), .. SourceData(position, starts)];
        int[] inferred = [.. ordered.Concat(after).Distinct()];
        GuessKind[] kinds = new GuessKind[0x10000];
        for (int index = 0; index < runs.Count; index += 2)
        {
            AnalyzeRun(image, runs[index], runs[index + 1], set, bank, inferred, starts, regions, kinds);
        }

        // The bytes read become the analysis's, and the last analysis's bytes the next request's scratch.
        _guessScratch = _guesses?.Image ?? new byte[0x10000];
        _guesses = new MemoryGuesses(space, image, [.. runs], ordered, starts, modules, kinds);
        return _guesses;
    }

    // Analyzes one readable run, marking what it finds in kinds.
    private static void AnalyzeRun(
        byte[] image,
        int start,
        int length,
        InstructionSet set,
        DebugMemoryBank? bank,
        int[] entries,
        int[] starts,
        List<AnalysisRegion> regions,
        GuessKind[] kinds)
    {
        int end = start + length;

        // The CPU's vectors, such as the 6502's at $FFFA, are its own only where it runs: in memory as it maps it,
        // or a coprocessor's space; a bank of RAM that holds those addresses holds no vectors.
        AnalysisProject project = new(image.AsSpan(start, length), start, set)
        {
            GenerateLabels = false,
            FollowVectors = bank is null || bank.InstructionSet is not null
        };

        project.EntryPoints.Clear();
        foreach (int entry in entries.Concat(starts))
        {
            if (entry >= start && entry < end) { project.EntryPoints.Add((ushort)entry); }
        }

        foreach (AnalysisRegion region in regions)
        {
            if (region.Address >= start && region.Address + region.Length <= end) { project.Regions.Add(region); }
        }

        DisassemblyResult result = Disassembler.Analyze(project);
        foreach (AnalysisRegion region in result.Regions)
        {
            if (region.Kind != AnalysisRegionKind.Data) { continue; }
            kinds.AsSpan(region.Address, Math.Min(region.Length, end - region.Address)).Fill(GuessKind.Data);
        }

        foreach (DisassembledInstruction instruction in result.Instructions)
        {
            int address = instruction.Address;
            kinds[address] = GuessKind.Start;
            for (int index = 1; index < instruction.Size && address + index < end; index++)
            {
                kinds[address + index] = GuessKind.Operand;
            }
        }
    }

    // Each Decode from here start as code one instruction long, which the analysis takes before inferring anything,
    // adding to after where the instruction goes on to the next, which an explicit region does not follow; a start
    // inside an earlier one's instruction, or that decodes to nothing, is left to the listing.
    private static List<AnalysisRegion> StartRegions(byte[] image, InstructionSet set, int[] starts, List<int> after)
    {
        List<AnalysisRegion> regions = [];
        int claimed = -1;
        foreach (int start in starts)
        {
            if (start < claimed) { continue; }
            ReadOnlySpan<byte> bytes = image.AsSpan(start, Math.Min(LongestInstruction, 0x10000 - start));
            bool decoded = Disassembler.TryDecode(bytes, (ushort)start, set, out DisassembledInstruction instruction);
            if (!decoded) { continue; }
            claimed = start + instruction.Size;
            regions.Add(new AnalysisRegion(start, instruction.Size, AnalysisRegionKind.Code));
            bool goesOn = instruction.Flow is DisassemblyFlow.Next or DisassemblyFlow.ConditionalBranch or DisassemblyFlow.Call;
            if (goesOn && claimed <= 0xFFFF) { after.Add(claimed); }
        }

        return regions;
    }

    // The statements the sources make data, which the analysis keeps out of, except one a Decode from here start is in.
    private static List<AnalysisRegion> SourceData(Func<int, DebugPosition?> position, int[] starts)
    {
        List<AnalysisRegion> regions = [];
        int address = 0;
        while (address <= 0xFFFF)
        {
            if (position(address) is not { Start: { } start, Size: > 0 } statement || start != address)
            {
                address++;
                continue;
            }

            int end = Math.Min(0x10000, start + statement.Size);
            bool started = starts.Any(at => at >= start && at < end);
            if (statement.Data && !started)
            {
                regions.Add(new AnalysisRegion(start, end - start, AnalysisRegionKind.Data));
            }

            address = end;
        }

        return regions;
    }

    // Where the analysis starts inferring: the PC of the CPU that runs the space, the machine's for memory as it maps
    // it and a coprocessor's for its own, but none for a bank of RAM, which no CPU runs as it stands; and each label
    // the sources give for code, from which the analysis follows calls and jumps into memory no source describes.
    private IEnumerable<int> GuessEntries(DebugMemoryBank? bank, IEnumerable<int> codeLabels)
    {
        IDebugTarget? runner = bank is null ? Target : bank.InstructionSet is not null ? Target.Coprocessor : null;
        if (runner?.Registers.Value(runner.Frame, ProgramCounter) is { } pc) { yield return (int)(pc & 0xFFFF); }
        foreach (int label in codeLabels) { yield return label; }
    }
}
