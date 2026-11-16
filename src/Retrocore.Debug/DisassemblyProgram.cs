// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;

namespace Retrocore.Debug;

/// <summary>
///  A program to disassemble and what is known about it, from which each analysis pass is made.
/// </summary>
/// <param name="Image">The program's bytes.</param>
/// <param name="Origin">Where its first byte loads.</param>
/// <param name="What">What it is, for the source's heading, such as its name and disk.</param>
/// <param name="Cpu">Its instruction set.</param>
/// <param name="Hints">What following its code does not show.</param>
internal sealed record DisassemblyProgram(byte[] Image, int Origin, string What, ProcessorVariant Cpu, DisassemblyHints Hints)
{
    /// <summary>
    ///  Tests whether an address is one of the program's bytes.
    /// </summary>
    /// <param name="address">The address.</param>
    /// <returns>Whether the program holds it.</returns>
    internal bool Contains(ushort address) => address >= Origin && address < Origin + Image.Length;

    /// <summary>
    ///  Makes an analysis project of the program, its hints and the machine's names for addresses it uses.
    /// </summary>
    /// <param name="machine">The machine's names; the hints' names win over them.</param>
    /// <returns>The project.</returns>
    internal AnalysisProject Project(IReadOnlyDictionary<ushort, string> machine)
    {
        AnalysisProject project = new(Image, Origin, Cpu);

        // Marks made while debugging can be anywhere in memory, such as on a ROM routine the program calls; only
        // what falls in the image is the disassembler's.
        foreach ((ushort start, int length) in Hints.Data)
        {
            int from = Math.Max(start, Origin);
            int to = Math.Min(start + length, Origin + Image.Length);
            if (from < to)
            {
                project.Regions.Add(new AnalysisRegion((ushort)from, to - from, AnalysisRegionKind.Data));
            }
        }

        // An origin marked as data is not where code starts.
        if (InData(project, (ushort)Origin)) { project.EntryPoints.Remove((ushort)Origin); }

        // Code marked is one instruction pinned as code, so nothing found automatically, such as a CPU vector, claims
        // its bytes; analysis goes on from where the instruction does.
        List<ushort> entries = [.. Hints.Entries.Where(entry => Contains(entry) && !InData(project, entry)).Distinct().Order()];
        List<ushort> after = [];
        int claimed = -1;
        foreach (ushort entry in entries)
        {
            if (entry < claimed) { continue; }
            int offset = entry - Origin;
            if (!Disassembler.TryDecode(Image.AsSpan(offset), entry, Cpu, out DisassembledInstruction instruction)
                || offset + instruction.Size > Image.Length
                || Enumerable.Range(entry, instruction.Size).Any(address => InData(project, (ushort)address)))
            {
                continue;
            }

            claimed = entry + instruction.Size;
            project.Regions.Add(new AnalysisRegion(entry, instruction.Size, AnalysisRegionKind.Code));
            if (GoesOn(instruction.Flow) && Contains((ushort)claimed) && !InData(project, (ushort)claimed))
            {
                after.Add((ushort)claimed);
            }
        }

        foreach (ushort entry in entries.Concat(after).Where(entry => !project.EntryPoints.Contains(entry)))
        {
            project.EntryPoints.Add(entry);
        }

        foreach ((ushort address, AnalysisCall call) in Hints.Calls) { project.Calls[address] = call; }
        foreach ((ushort address, string name) in machine) { project.Symbols[address] = name; }
        foreach ((ushort address, string name) in Hints.Names) { project.Symbols[address] = name; }
        foreach ((ushort address, string comment) in Hints.Comments.Where(pair => Contains(pair.Key)))
        {
            project.Comments[address] = comment;
        }

        return project;
    }

    // Whether an instruction goes on to the next.
    private static bool GoesOn(DisassemblyFlow flow) =>
        flow is DisassemblyFlow.Next or DisassemblyFlow.ConditionalBranch or DisassemblyFlow.Call or DisassemblyFlow.Wait;

    // Whether the project's pinned data holds an address.
    private static bool InData(AnalysisProject project, ushort address) => project.Regions.Any(region =>
        region.Kind == AnalysisRegionKind.Data && address >= region.Address && address < region.Address + region.Length);
}
