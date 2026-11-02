// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

/// <summary>
///  One section's placement and independent location counter for a compilation.
/// </summary>
internal struct LayoutSection
{
    /// <summary>
    ///  Creates a section.
    /// </summary>
    /// <param name="name">The section name.</param>
    /// <param name="origin">The CPU address of the section's first byte.</param>
    /// <param name="size">The fixed byte count.</param>
    /// <param name="line">The declaring statement index, or zero for the options' first section.</param>
    /// <param name="definition">Optional model placement and output settings.</param>
    /// <param name="nativeStatement">The defining .section statement, or -1 for model/options sections.</param>
    /// <param name="trim">Whether unused tail capacity is omitted.</param>
    internal LayoutSection(
        string name,
        int origin,
        int size,
        int line,
        AssemblySectionDefinition? definition = null,
        int nativeStatement = -1,
        bool trim = false)
    {
        Name = name;
        Origin = origin;
        Capacity = size;
        Line = line;
        RunOrigin = definition?.RunOrigin ?? origin;
        Definition = definition;
        NativeStatement = nativeStatement;
        Trim = definition?.Trim ?? trim;
        FillByte = definition?.FillByte ?? 0;
        SizeSymbol = LoadSymbol = RunSymbol = AssemblySymbols.Undeclared;
    }

    /// <summary>
    ///  Gets the section name.
    /// </summary>
    internal string Name { get; }

    /// <summary>
    ///  Gets the CPU address of the section's first byte.
    /// </summary>
    internal int Origin { get; set; }

    /// <summary>
    ///  Gets the fixed byte count.
    /// </summary>
    internal int Capacity { get; set; }

    /// <summary>
    ///  Gets the declaring statement index used for diagnostics.
    /// </summary>
    internal int Line { get; }

    /// <summary>
    ///  Gets the defining model metadata.
    /// </summary>
    internal AssemblySectionDefinition? Definition { get; }

    /// <summary>
    ///  Gets the defining native statement index, or -1.
    /// </summary>
    internal int NativeStatement { get; }

    /// <summary>
    ///  Gets or sets the initial logical address.
    /// </summary>
    internal int RunOrigin { get; set; }

    /// <summary>
    ///  Gets or sets the saved logical location counter.
    /// </summary>
    internal int Address { get; set; }

    /// <summary>
    ///  Gets or sets the saved section-relative offset.
    /// </summary>
    internal int Offset { get; set; }

    /// <summary>
    ///  Gets or sets used capacity from the current or previous pass.
    /// </summary>
    internal int UsedSize { get; set; }

    /// <summary>
    ///  Gets or sets whether this pass placed the section at a provisional address because its linker region's
    ///  start depends on layout that has not run yet.
    /// </summary>
    internal bool Provisional { get; set; }

    /// <summary>
    ///  Gets or sets the maximum transient bytes removable by address-width shrinking.
    /// </summary>
    internal int ShrinkBudget { get; set; }

    /// <summary>
    ///  Gets or sets whether unused capacity is omitted.
    /// </summary>
    internal bool Trim { get; set; }

    /// <summary>
    ///  Gets or sets the section gap and padding byte.
    /// </summary>
    internal byte FillByte { get; set; }

    /// <summary>
    ///  Gets whether this is a no-output section.
    /// </summary>
    internal readonly bool NoOutput => Definition?.NoOutput ?? false;

    /// <summary>
    ///  Gets the occupied address range.
    /// </summary>
    internal readonly int Size => Trim ? UsedSize : Capacity;

    /// <summary>
    ///  Gets or sets the compiler-defined size symbol ID.
    /// </summary>
    internal int SizeSymbol { get; set; }

    /// <summary>
    ///  Gets or sets the compiler-defined load symbol ID.
    /// </summary>
    internal int LoadSymbol { get; set; }

    /// <summary>
    ///  Gets or sets the compiler-defined run symbol ID.
    /// </summary>
    internal int RunSymbol { get; set; }
}
