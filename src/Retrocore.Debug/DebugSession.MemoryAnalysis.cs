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

    // Analyzes a space from its entry points, or gives the last analysis where nothing it used has changed.
    private MemoryGuesses Guess(DebugMemoryBank? bank, ListingMemory memory, InstructionSet set, IEnumerable<int> entries)
    {
        byte[] image = new byte[0x10000];
        List<AnalysisRegion> unreadable = [];
        int run = -1;
        for (int address = 0; address <= 0x10000; address++)
        {
            bool readable = address <= 0xFFFF && memory.Readable(address);
            if (readable) { image[address] = memory.Peek((ushort)address); }
            if (!readable && run < 0 && address <= 0xFFFF) { run = address; }
            else if ((readable || address > 0xFFFF) && run >= 0)
            {
                unreadable.Add(new AnalysisRegion(run, address - run, AnalysisRegionKind.Data));
                run = -1;
            }
        }

        int[] ordered = [.. entries.Where(entry => entry is >= 0 and <= 0xFFFF && memory.Readable(entry)).Distinct().Order()];
        string space = bank?.Name ?? "";
        if (_guesses is { } last
            && last.Space == space
            && last.Entries.AsSpan().SequenceEqual(ordered)
            && last.Image.AsSpan().SequenceEqual(image))
        {
            return last;
        }

        AnalysisProject project = new(image, origin: 0, set) { GenerateLabels = false };
        project.EntryPoints.Clear();
        foreach (int entry in ordered) { project.EntryPoints.Add((ushort)entry); }
        foreach (AnalysisRegion region in unreadable) { project.Regions.Add(region); }
        DisassemblyResult result = Disassembler.Analyze(project);

        GuessKind[] kinds = new GuessKind[0x10000];
        foreach (AnalysisRegion region in result.Regions)
        {
            if (region.Kind != AnalysisRegionKind.Data) { continue; }
            kinds.AsSpan(region.Address, Math.Min(region.Length, 0x10000 - region.Address)).Fill(GuessKind.Data);
        }

        foreach (DisassembledInstruction instruction in result.Instructions)
        {
            int start = instruction.Address;
            kinds[start] = GuessKind.Start;
            for (int index = 1; index < instruction.Size && start + index <= 0xFFFF; index++)
            {
                kinds[start + index] = GuessKind.Operand;
            }
        }

        // What cannot be read is no guess.
        foreach (AnalysisRegion region in unreadable)
        {
            kinds.AsSpan(region.Address, region.Length).Clear();
        }

        _guesses = new MemoryGuesses(space, image, ordered, kinds);
        return _guesses;
    }

    // Where the analysis starts: the PC, for the CPU's own memory; each Decode from here start; and each label the
    // sources give for code, from which the analysis follows calls and jumps into memory no source describes.
    private IEnumerable<int> GuessEntries(InstructionSet set, HashSet<int> forced, IEnumerable<int> codeLabels)
    {
        if (ReferenceEquals(set.Description, Target.InstructionSet.Description)
            && Target.Registers.Value(Target.Frame, ProgramCounter) is { } pc)
        {
            yield return (int)(pc & 0xFFFF);
        }

        foreach (int start in forced) { yield return start; }
        foreach (int label in codeLabels) { yield return label; }
    }
}
