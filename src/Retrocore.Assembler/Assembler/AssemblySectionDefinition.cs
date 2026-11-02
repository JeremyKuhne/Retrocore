// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

/// <summary>
///  Declares a bounded section, optionally placed after its predecessor during layout.
/// </summary>
public sealed class AssemblySectionDefinition
{
    private int _alignment = 1;
    private int? _runOrigin;

    /// <summary>
    ///  Creates a fixed or automatically placed section.
    /// </summary>
    /// <param name="name">An unqualified native section name.</param>
    /// <param name="origin">A fixed load address, or null for automatic placement.</param>
    /// <param name="size">The capacity, or null for the remaining address space.</param>
    public AssemblySectionDefinition(string name, int? origin = null, int? size = null)
    {
        ArgumentNullException.ThrowIfNull(name);
        if (!AssemblySyntax.IsPlainIdentifier(name))
        {
            throw new ArgumentException("Invalid section name.", nameof(name));
        }

        if (origin is < 0 or > ushort.MaxValue) { throw new ArgumentOutOfRangeException(nameof(origin)); }
        if (size is <= 0 or > InstructionEncoding.AddressSpaceSize
            || (origin is { } start && size is { } length && length > InstructionEncoding.AddressSpaceSize - start))
        {
            throw new ArgumentOutOfRangeException(nameof(size));
        }

        Name = name;
        Origin = origin;
        Size = size;
    }

    /// <summary>
    ///  Gets the section name used by .section.
    /// </summary>
    public string Name { get; }

    /// <summary>
    ///  Gets the fixed load address, or null for placement after the preceding section.
    /// </summary>
    public int? Origin { get; }

    /// <summary>
    ///  Gets the maximum size, or null for the remaining address space.
    /// </summary>
    public int? Size { get; }

    /// <summary>
    ///  Gets the alignment for automatic placement; as in ld65, any positive multiple is allowed.
    /// </summary>
    public int Alignment
    {
        get => _alignment;
        init
        {
            if (value <= 0 || value > InstructionEncoding.AddressSpaceSize)
            {
                throw new ArgumentOutOfRangeException(nameof(value));
            }

            _alignment = value;
        }
    }

    /// <summary>
    ///  Gets the logical address of the first byte, defaulting to its load address.
    /// </summary>
    public int? RunOrigin
    {
        get => _runOrigin;
        init
        {
            if (value is < 0 or > ushort.MaxValue) { throw new ArgumentOutOfRangeException(nameof(value)); }
            _runOrigin = value;
        }
    }

    /// <summary>
    ///  Gets the byte used for section gaps and unused tail padding.
    /// </summary>
    public byte FillByte { get; init; }

    /// <summary>
    ///  Gets whether unused tail padding is omitted. Defaults to true for model declarations.
    /// </summary>
    public bool Trim { get; init; } = true;

    /// <summary>
    ///  Gets whether the section occupies memory without producing file bytes, as BSS does.
    /// </summary>
    public bool NoOutput { get; init; }

    /// <summary>
    ///  Gets the owning linker region, if the definition comes from an ld65 configuration.
    /// </summary>
    internal AssemblyMemoryRegion? Memory { get; init; }

    /// <summary>
    ///  Gets whether compiler-defined size/load/run symbols are published for this section.
    /// </summary>
    internal bool DefineSymbols { get; init; } = true;
}
