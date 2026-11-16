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

    // How many times targets found in one readable run send analysis back to another before it stops.
    private const int GuessRounds = 8;

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
    ///   Each run of readable bytes is analyzed alone, so a pointer is never read from bytes that cannot be read;
    ///   a call or jump from one run to another starts analysis there, again until no run gains an entry point.
    ///   A Decode from here start is the user's: it is an instruction before anything is inferred, so no inferred
    ///   instruction can claim its bytes. A statement the sources make data, as it applies now, stays data, so
    ///   analysis does not run through it as code, unless a Decode from here start's instruction is in it.
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

        int[] starts = [.. forced.Where(start => memory.Readable(start)).Order()];
        List<AnalysisRegion> startRegions = StartRegions(image, set, starts, out List<int> after);
        List<AnalysisRegion> dataRegions = SourceData(position, startRegions);
        int[] data = [.. dataRegions.SelectMany(region => new[] { (int)region.Address, region.Length })];
        int[] ordered =
        [
            .. entries.Concat(after)
                .Where(entry => entry is >= 0 and <= 0xFFFF && memory.Readable(entry) && !Inside(dataRegions, entry))
                .Distinct()
                .Order()
        ];

        string space = bank?.Name ?? "";
        if (_guesses is { } last
            && ReferenceEquals(last.Target, Target)
            && ReferenceEquals(last.Set, set)
            && last.Space == space
            && last.Entries.AsSpan().SequenceEqual(ordered)
            && last.Starts.AsSpan().SequenceEqual(starts)
            && last.Data.AsSpan().SequenceEqual(data)
            && last.Runs.AsSpan().SequenceEqual(runs.ToArray())
            && last.Image.AsSpan().SequenceEqual(image))
        {
            return last;
        }

        List<AnalysisRegion> regions = [.. startRegions, .. dataRegions];
        GuessKind[] kinds = new GuessKind[0x10000];

        // Targets one run's analysis finds in another start that one's, until no run gains any.
        List<HashSet<int>> found = [.. Enumerable.Range(0, runs.Count / 2).Select(_ => new HashSet<int>())];
        HashSet<int> pending = [.. Enumerable.Range(0, runs.Count / 2)];
        for (int round = 0; round < GuessRounds && pending.Count > 0; round++)
        {
            HashSet<int> next = [];
            foreach (int index in pending.Order())
            {
                int start = runs[index * 2], length = runs[(index * 2) + 1];
                IEnumerable<int> inRun = ordered.Concat(found[index]);
                DisassemblyResult result = AnalyzeRun(image, start, length, set, bank, inRun, starts, regions, kinds);
                foreach (DisassemblyReference reference in result.References)
                {
                    // A jump through a pointer in another run, which this run's analysis cannot read, is followed
                    // here: the pointer is data in its run, and where it points an entry in that one's.
                    // Pointer bytes already data, as a source's .word is, are read as they are; bytes that are code
                    // make the pointer no pointer.
                    if (reference.Kind == DisassemblyReferenceKind.IndirectJump
                        && Pointer(image, runs, set, reference, index) is { } pointer
                        && !IsCode(regions, pointer.Low)
                        && !IsCode(regions, pointer.High))
                    {
                        foreach (int at in (int[])[pointer.Low, pointer.High])
                        {
                            if (Inside(regions, at)) { continue; }
                            regions.Add(new AnalysisRegion(at, 1, AnalysisRegionKind.Data));
                        }

                        next.Add(RunOf(runs, pointer.Low));
                        next.Add(RunOf(runs, pointer.High));
                        int pointed = RunOf(runs, pointer.Target);
                        if (pointed >= 0 && !Inside(regions, pointer.Target) && found[pointed].Add(pointer.Target))
                        {
                            next.Add(pointed);
                        }

                        continue;
                    }

                    if (reference.Kind is not (DisassemblyReferenceKind.Branch
                        or DisassemblyReferenceKind.Jump
                        or DisassemblyReferenceKind.Call
                        or DisassemblyReferenceKind.Vector))
                    {
                        continue;
                    }

                    int target = reference.Target;
                    int other = RunOf(runs, target);
                    if (other >= 0 && other != index && !Inside(dataRegions, target) && found[other].Add(target))
                    {
                        next.Add(other);
                    }
                }
            }

            pending = next;
        }

        // The bytes read become the analysis's, and the last analysis's bytes the next request's scratch.
        _guessScratch = _guesses?.Image ?? new byte[0x10000];
        _guesses = new MemoryGuesses(Target, set, space, image, [.. runs], ordered, starts, data, kinds);
        return _guesses;
    }

    // Analyzes one readable run, marking what it finds in kinds.
    private static DisassemblyResult AnalyzeRun(
        byte[] image,
        int start,
        int length,
        InstructionSet set,
        DebugMemoryBank? bank,
        IEnumerable<int> entries,
        int[] starts,
        List<AnalysisRegion> regions,
        GuessKind[] kinds)
    {
        int end = start + length;

        // The CPU's vectors, such as the 6502's at $FFFA, are its own only where it runs: in memory as it maps it,
        // or a coprocessor's space; a bank of RAM that holds those addresses holds no vectors, though an indirect
        // jump's pointer is followed anywhere.
        AnalysisProject project = new(image.AsSpan(start, length), start, set)
        {
            GenerateLabels = false,
            CpuVectors = bank is null || bank.InstructionSet is not null
        };

        // An entry in data pinned since the entries were chosen, such as a pointer found in another run, would fail
        // the whole run's analysis, so it is left out.
        project.EntryPoints.Clear();
        foreach (int entry in entries.Concat(starts).Distinct())
        {
            bool data = regions.Any(region => region.Kind == AnalysisRegionKind.Data && Overlaps(region, entry, 1));
            if (entry >= start && entry < end && !data) { project.EntryPoints.Add((ushort)entry); }
        }

        foreach (AnalysisRegion region in regions)
        {
            if (region.Address >= start && region.Address + region.Length <= end) { project.Regions.Add(region); }
        }

        DisassemblyResult result = Disassembler.Analyze(project);
        kinds.AsSpan(start, length).Clear();
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

        return result;
    }

    // Each Decode from here start as code one instruction long, which the analysis takes before inferring anything,
    // with after where the instruction goes on to the next, which an explicit region does not follow; a start
    // inside an earlier one's instruction, or that decodes to nothing, is left to the listing.
    private static List<AnalysisRegion> StartRegions(byte[] image, InstructionSet set, int[] starts, out List<int> after)
    {
        List<AnalysisRegion> regions = [];
        after = [];
        int claimed = -1;
        foreach (int start in starts)
        {
            if (start < claimed) { continue; }
            ReadOnlySpan<byte> bytes = image.AsSpan(start, Math.Min(LongestInstruction, 0x10000 - start));
            bool decoded = Disassembler.TryDecode(bytes, (ushort)start, set, out DisassembledInstruction instruction);
            if (!decoded) { continue; }
            claimed = start + instruction.Size;
            regions.Add(new AnalysisRegion(start, instruction.Size, AnalysisRegionKind.Code));
            DisassemblyFlow flow = instruction.Flow;
            bool goesOn = flow is DisassemblyFlow.Next or DisassemblyFlow.ConditionalBranch or DisassemblyFlow.Call or DisassemblyFlow.Wait;
            if (goesOn && claimed <= 0xFFFF) { after.Add(claimed); }
        }

        return regions;
    }

    // The statements the sources make data, as they apply now, which the analysis keeps out of: not one a Decode
    // from here start's instruction overlaps, nor one overlapping another taken first.
    private List<AnalysisRegion> SourceData(Func<int, DebugPosition?> position, List<AnalysisRegion> startRegions)
    {
        List<AnalysisRegion> regions = [];
        IEnumerable<int> candidates = _debug.Modules.SelectMany(module => module.DataStatements).Select(start => (int)start);
        int claimed = -1;
        foreach (int start in candidates.Distinct().Order())
        {
            DebugPosition? statement = start < claimed ? null : position(start);
            int size = statement is not null && statement.Data && statement.Start == start ? statement.Size : 0;
            if (size <= 0) { continue; }
            int end = Math.Min(0x10000, start + size);
            bool overlapped = startRegions.Any(region => region.Address < end && region.Address + region.Length > start);
            if (overlapped) { continue; }
            regions.Add(new AnalysisRegion(start, end - start, AnalysisRegionKind.Data));
            claimed = end;
        }

        return regions;
    }

    // The pointer of a plain indirect jump, such as JMP ($C100), when its bytes are readable but outside the jump's
    // own run; null for a jump through a register or an indexed table, or a pointer the run could read itself.
    private static (int Low, int High, int Target)? Pointer(
        byte[] image,
        List<int> runs,
        InstructionSet set,
        DisassemblyReference reference,
        int run)
    {
        ReadOnlySpan<byte> bytes = image.AsSpan(reference.Source, Math.Min(LongestInstruction, 0x10000 - reference.Source));
        bool decoded = Disassembler.TryDecode(bytes, reference.Source, set, out DisassembledInstruction jump);
        OperandForm form = jump.Form;
        bool plain = decoded && jump.Flow == DisassemblyFlow.IndirectJump && !form.IsIndexed && !form.HasPostbyte;
        if (!plain) { return null; }

        int first = reference.Target;
        int second = (first + 1) & 0xFFFF;
        if (set.IndirectPageWrap && (first & 0xFF) == 0xFF) { second = first & 0xFF00; }
        int lowRun = RunOf(runs, first), highRun = RunOf(runs, second);
        if (lowRun < 0 || highRun < 0 || (lowRun == run && highRun == run)) { return null; }
        (int low, int high) = set.Endianness == Endianness.Big ? (second, first) : (first, second);
        return (low, high, image[low] | (image[high] << 8));
    }

    // Whether a region overlaps a range.
    private static bool Overlaps(AnalysisRegion region, int start, int length) =>
        region.Address < start + length && region.Address + region.Length > start;

    // Whether an address is in one of the code regions.
    private static bool IsCode(List<AnalysisRegion> regions, int address) =>
        regions.Any(region => region.Kind == AnalysisRegionKind.Code && Overlaps(region, address, 1));

    // Whether an address is in one of the regions.
    private static bool Inside(List<AnalysisRegion> regions, int address) =>
        regions.Any(region => address >= region.Address && address < region.Address + region.Length);

    // The index of the readable run an address is in, or -1.
    private static int RunOf(List<int> runs, int address)
    {
        for (int index = 0; index < runs.Count; index += 2)
        {
            if (address >= runs[index] && address < runs[index] + runs[index + 1]) { return index / 2; }
        }

        return -1;
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
