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
        foreach (ushort entry in Hints.Entries.Where(entry => !project.EntryPoints.Contains(entry)))
        {
            project.EntryPoints.Add(entry);
        }

        foreach ((ushort start, int length) in Hints.Data)
        {
            project.Regions.Add(new AnalysisRegion(start, length, AnalysisRegionKind.Data));
        }

        foreach ((ushort address, AnalysisCall call) in Hints.Calls) { project.Calls[address] = call; }
        foreach ((ushort address, string name) in machine) { project.Symbols[address] = name; }
        foreach ((ushort address, string name) in Hints.Names) { project.Symbols[address] = name; }
        foreach ((ushort address, string comment) in Hints.Comments) { project.Comments[address] = comment; }
        return project;
    }
}
