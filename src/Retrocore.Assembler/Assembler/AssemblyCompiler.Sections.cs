// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

internal static partial class AssemblyCompiler
{
    private static List<LayoutSection> CollectSections(
        AssemblyProject project,
        LayoutStatement[] statements,
        int statementCount,
        int sectionCount,
        int shrinkBudget,
        AssemblyOptions options,
        AssemblySymbols symbols,
        Dictionary<string, AssemblyStatement> declared,
        List<AssemblyError> errors)
    {
        List<LayoutSection> sections = new(capacity: 1);
        bool configured = project.DeclaredSections is { Count: > 0 };
        sections.Add(new(DefaultSectionName, options.Origin, options.ImageSize, line: 0, trim: configured));
        if (sectionCount == 0 && !configured)
        {
            LayoutSection section = sections[0];
            section.ShrinkBudget = shrinkBudget;
            sections[0] = section;
            return sections;
        }

        if (project.DeclaredSections is { } definitions)
        {
            foreach (AssemblySectionDefinition definition in definitions)
            {
                if (definition is null)
                {
                    throw new ArgumentException("Section definitions cannot contain null.", nameof(project));
                }

                if (FindSection(sections, definition.Name) >= 0)
                {
                    errors.Add(new(line: 0, $"Duplicate section '{definition.Name}'."));
                    continue;
                }

                LayoutSection section = new(
                    definition.Name,
                    definition.Origin ?? options.Origin,
                    definition.Size ?? 0,
                    line: 0,
                    definition);

                if (definition.DefineSymbols) { DeclareSectionSymbols(ref section, symbols, declared, errors); }
                sections.Add(section);
            }
        }

        int current = project.InitialSection is { } initial ? FindSection(sections, initial) : 0;
        if (current < 0) { current = 0; }
        for (int index = 0; index < statementCount; index++)
        {
            ref LayoutStatement statement = ref statements[index];
            if (statement.Kind == LayoutOperation.Section)
            {
                try
                {
                    AssemblyOperands operands = new(statement.EncodingOperand, statement.Line);
                    operands.MoveNext();
                    string name = operands.Current.ToString();
                    bool definition = operands.MoveNext();
                    int found = FindSection(sections, name);
                    if (found < 0 && definition && AssemblySyntax.IsPlainIdentifier(name))
                    {
                        LayoutSection section = new(name, origin: 0, size: 0, statement.Line, nativeStatement: statement.Line);
                        DeclareSectionSymbols(ref section, symbols, declared, errors);
                        found = sections.Count;
                        sections.Add(section);
                    }

                    statement.Section = found;
                    if (found >= 0) { current = found; }
                }
                catch (AssemblyError)
                {
                    // Layout reports malformed operands in source order alongside other pass-zero errors.
                    statement.Section = -1;
                }
            }
            else
            {
                statement.Section = current;
                if (CanShrinkSyntax(in statement))
                {
                    LayoutSection section = sections[current];
                    section.ShrinkBudget++;
                    sections[current] = section;
                }
            }
        }

        return sections;
    }

    private static bool CanShrinkSyntax(in LayoutStatement statement) =>
        statement.Kind == LayoutOperation.Instruction
            && statement.HasNarrowForm
            && !statement.ForcesAbsolute
            && !statement.ForcesZeroPage
            && !statement.SourceOrder;

    private static void CheckStatementBounds(
        LayoutStatement[] statements,
        int count,
        List<LayoutSection> sections,
        List<AssemblyError> errors)
    {
        foreach (LayoutStatement statement in statements.AsSpan(0, count))
        {
            if (statement.Size == 0) { continue; }
            if (statement.Address < 0
                || statement.Size > InstructionEncoding.AddressSpaceSize - statement.Address
                || (!statement.IsDummy && statement.Size > sections[statement.Section].Capacity - statement.Offset))
            {
                errors.Add(new(statement.Line, "Statement exceeds the current section."));
            }
        }
    }

    private static int FindSection(List<LayoutSection> sections, string name)
    {
        for (int index = 0; index < sections.Count; index++)
        {
            if (sections[index].Name.Equals(name, StringComparison.Ordinal)) { return index; }
        }

        return -1;
    }

    private static void DeclareSectionSymbols(
        ref LayoutSection section,
        AssemblySymbols symbols,
        Dictionary<string, AssemblyStatement> declared,
        List<AssemblyError> errors)
    {
        section.SizeSymbol = DeclareSectionSymbol($"__{section.Name}_SIZE__", section.Line, symbols, declared, errors);
        section.LoadSymbol = DeclareSectionSymbol($"__{section.Name}_LOAD__", section.Line, symbols, declared, errors);
        section.RunSymbol = DeclareSectionSymbol($"__{section.Name}_RUN__", section.Line, symbols, declared, errors);
    }

    private static int DeclareSectionSymbol(
        string name,
        int line,
        AssemblySymbols symbols,
        Dictionary<string, AssemblyStatement> declared,
        List<AssemblyError> errors)
    {
        if (!declared.TryAdd(name, new(AssemblyStatementKind.Constant, ".equ", label: name)))
        {
            errors.Add(new(line, $"Compiler-defined symbol '{name}' cannot be redefined."));
        }

        return symbols.Declare(name);
    }

    private static bool PlaceSections(List<LayoutSection> sections)
    {
        bool changed = false;
        int precedingEnd = sections[0].Origin;
        for (int index = 0; index < sections.Count; index++)
        {
            LayoutSection section = sections[index];
            int previousSize = section.Size;
            if (section.Definition is { } definition)
            {
                int preceding = precedingEnd;
                if (definition.Memory is { } memory)
                {
                    preceding = memory.Start;
                    for (int prior = index - 1; prior >= 0; prior--)
                    {
                        if (ReferenceEquals(sections[prior].Definition?.Memory, memory))
                        {
                            preceding = sections[prior].Origin + sections[prior].Size;
                            break;
                        }
                    }
                }

                int origin = definition.Origin ?? AlignAddress(preceding, definition.Alignment);
                int bound = definition.Memory?.End ?? InstructionEncoding.AddressSpaceSize;
                int capacity = definition.Size ?? bound - origin;
                bool emptyEnd = definition.Memory is not null && capacity == 0 && origin == bound && previousSize == 0;
                if (origin < 0
                    || (origin > ushort.MaxValue && !emptyEnd)
                    || capacity < 0
                    || (capacity == 0 && definition.Memory is null)
                    || capacity > InstructionEncoding.AddressSpaceSize - origin)
                {
                    throw new AssemblyError(section.Line, $"Section '{section.Name}' must fit within the 64 KiB address space.");
                }

                changed |= section.Origin != origin;
                section.Origin = origin;
                section.RunOrigin = definition.RunOrigin ?? origin;
                section.Capacity = capacity;
                section.Provisional = definition.Memory is { Resolved: false };
            }

            precedingEnd = section.Origin + (section.Trim ? previousSize : section.Capacity);
            sections[index] = section;
        }

        for (int index = 0; index < sections.Count; index++)
        {
            LayoutSection section = sections[index];
            section.Address = section.RunOrigin;
            section.Offset = 0;
            section.UsedSize = 0;
            sections[index] = section;
        }

        return changed;
    }

    private static int AlignAddress(int address, int alignment) => checked((address + alignment - 1) / alignment * alignment);

    private static void SaveSection(List<LayoutSection> sections, int index, int address, int offset)
    {
        LayoutSection section = sections[index];
        section.Address = address;
        section.Offset = offset;
        section.UsedSize = Math.Max(section.UsedSize, offset);
        sections[index] = section;
    }

    private static bool UpdateSectionSymbols(List<LayoutSection> sections, AssemblySymbols symbols)
    {
        bool changed = false;
        foreach (LayoutSection section in sections)
        {
            if (section.SizeSymbol == AssemblySymbols.Undeclared) { continue; }
            changed |= symbols.SetValue(section.SizeSymbol, section.UsedSize);
            changed |= symbols.SetValue(section.LoadSymbol, section.Origin);
            changed |= symbols.SetValue(section.RunSymbol, section.RunOrigin);
        }

        return changed;
    }

    private static void SelectSection(
        ref LayoutStatement statement,
        AssemblySymbols symbols,
        List<LayoutSection> sections,
        ref int current,
        ref LayoutContext context)
    {
        AssemblyOperands operands = new(statement.EncodingOperand, statement.Line);
        operands.MoveNext();
        ReadOnlyMemory<char> name = operands.Current;
        bool defining = operands.MoveNext();
        if (!AssemblySyntax.IsPlainIdentifier(name.Span) && !name.Span.SequenceEqual(DefaultSectionName))
        {
            throw new AssemblyError(statement.Line, ".section requires a name, origin and size.");
        }

        if (statement.Section < 0)
        {
            throw new AssemblyError(statement.Line, $"Unknown section '{name}'.");
        }

        LayoutSection selected = sections[statement.Section];
        if (defining)
        {
            if (selected.NativeStatement != statement.Line)
            {
                throw new AssemblyError(statement.Line, $"Duplicate section '{name}'.");
            }

            LayoutSection definition = SectionOperands(in statement, symbols, context.Address);
            selected.Origin = definition.Origin;
            selected.RunOrigin = definition.RunOrigin;
            selected.Capacity = definition.Capacity;
            selected.FillByte = definition.FillByte;
            selected.Trim = definition.Trim;
            selected.Address = selected.RunOrigin;
            sections[statement.Section] = selected;
        }
        else if (selected.NativeStatement >= 0 && selected.Capacity == 0)
        {
            throw new AssemblyError(statement.Line, $"Section '{name}' has not been defined yet.");
        }

        SaveSection(sections, current, context.Address, context.Offset);
        current = statement.Section;
        selected = sections[current];
        context.Address = selected.Address;
        context.Offset = selected.Offset;
        context.Capacity = selected.Capacity;
        context.ShrinkBudget = selected.ShrinkBudget;
        context.NoOutput = selected.NoOutput;
        context.RunOrigin = selected.RunOrigin;
        context.SectionProvisional = selected.Provisional;
        context.Provisional = selected.Provisional;
        context.SegmentRelative = selected.Definition?.Memory is not null;
        context.Logical = false;
        statement.NoOutput = selected.NoOutput;
    }
}
