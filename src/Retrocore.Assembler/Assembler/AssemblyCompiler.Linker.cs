// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

internal static partial class AssemblyCompiler
{
    /// <summary>
    ///  Declares ld65 SYMBOLS values and the symbols of MEMORY regions marked <c>define = yes</c>.
    /// </summary>
    /// <param name="project">The linked project.</param>
    /// <param name="symbols">The compilation's symbol table.</param>
    /// <param name="declared">Source definitions, which take precedence over weak linker symbols.</param>
    /// <param name="errors">Receives redefinition errors.</param>
    private static void DeclareLinkerSymbols(
        AssemblyProject project,
        AssemblySymbols symbols,
        Dictionary<string, AssemblyStatement> declared,
        List<AssemblyError> errors)
    {
        if (project.LinkerSymbols is { } linked)
        {
            foreach (AssemblyLinkerSymbol symbol in linked)
            {
                if (symbol.Weak && declared.ContainsKey(symbol.Name)) { continue; }
                symbol.Id = DeclareSectionSymbol(symbol.Name, line: 0, symbols, declared, errors);
            }
        }

        if (project.MemoryRegions is not { } regions) { return; }
        foreach (AssemblyMemoryRegion memory in regions)
        {
            if (!memory.Define) { continue; }
            memory.StartSymbol = DeclareSectionSymbol($"__{memory.Name}_START__", line: 0, symbols, declared, errors);
            memory.SizeSymbol = DeclareSectionSymbol($"__{memory.Name}_SIZE__", line: 0, symbols, declared, errors);
            memory.LastSymbol = DeclareSectionSymbol($"__{memory.Name}_LAST__", line: 0, symbols, declared, errors);
            memory.FileOffsetSymbol = DeclareSectionSymbol($"__{memory.Name}_FILEOFFS__", line: 0, symbols, declared, errors);
        }
    }

    /// <summary>
    ///  Evaluates SYMBOLS values, then MEMORY bounds in configuration order, before sections are placed.
    /// </summary>
    /// <param name="project">The linked project.</param>
    /// <param name="symbols">Values from the previous pass, including each region's last address.</param>
    /// <param name="firstPass">
    ///  Whether layout has not run yet, so a region placed after another region's last address is not known.
    /// </param>
    /// <returns>Whether any linker value changed.</returns>
    private static bool EvaluateLinkerValues(AssemblyProject project, AssemblySymbols symbols, bool firstPass)
    {
        bool changed = false;
        if (project.LinkerSymbols is { } linked)
        {
            foreach (AssemblyLinkerSymbol symbol in linked)
            {
                if (symbol.Id == AssemblySymbols.Undeclared) { continue; }
                if (LinkerValue(symbol.Expression, symbols, firstPass, $"linker symbol '{symbol.Name}'") is { } value)
                {
                    changed |= symbols.SetValue(symbol.Id, value);
                }
            }
        }

        if (project.MemoryRegions is not { } regions) { return changed; }
        foreach (AssemblyMemoryRegion memory in regions)
        {
            // As in ld65, __NAME_START__ is defined before the size, so the size expression may read it.
            long? start = LinkerValue(memory.StartExpression, symbols, firstPass, $"MEMORY region '{memory.Name}' start");
            if (memory.Define && start is { } known) { changed |= symbols.SetValue(memory.StartSymbol, known); }
            long? size = LinkerValue(memory.SizeExpression, symbols, firstPass, $"MEMORY region '{memory.Name}' size");
            if (start is not { } first || size is not { } length)
            {
                // Only the first pass reaches here: allow the whole address space until the region is known.
                memory.Start = (int)Math.Max(0, Math.Min(start ?? 0, ushort.MaxValue));
                memory.Size = InstructionEncoding.AddressSpaceSize - memory.Start;
                memory.Resolved = false;
                changed = true;
                continue;
            }

            if (first is < 0 or > ushort.MaxValue || length <= 0 || length > InstructionEncoding.AddressSpaceSize - first)
            {
                throw new AssemblyError(-1, $"MEMORY region '{memory.Name}' must fit within the 64 KiB address space.");
            }

            changed |= memory.Start != (int)first || memory.Size != (int)length || !memory.Resolved;
            memory.Resolved = true;
            memory.Start = (int)first;
            memory.Size = (int)length;
            if (memory.Define) { changed |= symbols.SetValue(memory.SizeSymbol, length); }
        }

        return changed;
    }

    /// <summary>
    ///  Updates each defined region's last address and file offset from the sections laid out this pass.
    /// </summary>
    /// <param name="project">The linked project.</param>
    /// <param name="sections">The laid-out sections.</param>
    /// <param name="symbols">The compilation's symbol table.</param>
    /// <returns>Whether any value changed.</returns>
    private static bool UpdateMemorySymbols(AssemblyProject project, List<LayoutSection> sections, AssemblySymbols symbols)
    {
        if (project.MemoryRegions is not { } regions) { return false; }
        bool changed = false;
        Dictionary<string, int>? offsets = null;
        foreach (AssemblyMemoryRegion memory in regions)
        {
            // As in ld65, uninitialized segments raise the fill level but add file bytes only to a filled region.
            int level = 0;
            int written = 0;
            foreach (LayoutSection section in sections)
            {
                if (!ReferenceEquals(section.Definition?.Memory, memory) || section.UsedSize == 0) { continue; }
                int end = section.Origin + section.UsedSize - memory.Start;
                level = Math.Max(level, end);
                if (!section.NoOutput) { written = Math.Max(written, end); }
            }

            int offset = 0;
            if (memory.File.Length != 0)
            {
                offsets ??= new(StringComparer.Ordinal);
                offsets.TryGetValue(memory.File, out offset);
                offsets[memory.File] = offset + (memory.Fill ? memory.Size : written);
            }

            if (memory.Define)
            {
                changed |= symbols.SetValue(memory.LastSymbol, memory.Start + level);
                changed |= symbols.SetValue(memory.FileOffsetSymbol, offset);
            }
        }

        return changed;
    }

    private static long? LinkerValue(string expression, AssemblySymbols symbols, bool firstPass, string purpose)
    {
        try
        {
            if (TryValue(expression.AsMemory(), symbols, address: 0, line: -1, out long value)) { return value; }
        }
        catch (AssemblyError error) when (firstPass)
        {
            _ = error;
            return null;
        }
        catch (AssemblyError error)
        {
            throw new AssemblyError(-1, $"The {purpose} cannot be evaluated: {error.Message}");
        }

        return firstPass ? null : throw new AssemblyError(-1, $"The {purpose} is not a constant expression.");
    }
}
