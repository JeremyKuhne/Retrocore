// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Cpu.M6502;

namespace Retrocore.Assembler;

/// <summary>
///  An editable single-image analysis project. Reanalysis never overwrites caller annotations.
/// </summary>
public sealed class AnalysisProject
{
    /// <summary>
    ///  Creates a project with an owned image and an initial entry point at its origin.
    /// </summary>
    /// <param name="image">The input bytes, copied into project-owned storage.</param>
    /// <param name="origin">The non-wrapping load address.</param>
    /// <param name="variant">The CPU encoding set.</param>
    public AnalysisProject(ReadOnlySpan<byte> image, int origin, ProcessorVariant variant)
        : this(image, origin, Enum.IsDefined(variant) ? M6502Isa.Get(variant) : throw new ArgumentOutOfRangeException(nameof(variant)))
    {
    }

    /// <summary>
    ///  Creates a project for any CPU's instruction set, with the origin as its only entry point.
    /// </summary>
    /// <param name="image">The bytes to analyze, copied.</param>
    /// <param name="origin">The address of the first byte.</param>
    /// <param name="set">The CPU's instruction set, such as one from <see cref="CpuCatalog"/>.</param>
    public AnalysisProject(ReadOnlySpan<byte> image, int origin, Retrocore.Isa.InstructionSet set)
    {
        ArgumentNullException.ThrowIfNull(set);
        if (image.IsEmpty) { throw new ArgumentException("An analysis image cannot be empty.", nameof(image)); }
        ArgumentOutOfRangeException.ThrowIfNegative(origin);
        ArgumentOutOfRangeException.ThrowIfGreaterThan(origin, ushort.MaxValue);
        if (image.Length > InstructionEncoding.AddressSpaceSize - origin)
        {
            throw new ArgumentOutOfRangeException(nameof(image));
        }

        Image = image.ToArray();
        Origin = (ushort)origin;
        InstructionSet = set;
        EntryPoints.Add(Origin);
    }

    /// <summary>
    ///  Gets the owned bytes; callers must not mutate their backing storage.
    /// </summary>
    public ReadOnlyMemory<byte> Image { get; }

    /// <summary>
    ///  Gets the first address.
    /// </summary>
    public ushort Origin { get; }

    /// <summary>
    ///  Gets the CPU encoding set.
    /// </summary>
    public ProcessorVariant Variant => M6502Isa.VariantOf(InstructionSet);

    /// <summary>
    ///  Gets the CPU's instruction set.
    /// </summary>
    public Retrocore.Isa.InstructionSet InstructionSet { get; }

    /// <summary>
    ///  Gets or sets the analysis strategy.
    /// </summary>
    public DisassemblyMode Mode { get; set; } = DisassemblyMode.Flow;

    /// <summary>
    ///  Gets or sets whether flow tracing stops at BRK. When false, tracing resumes after its signature byte.
    /// </summary>
    public bool StopOnBreak { get; set; } = true;

    /// <summary>
    ///  Gets or sets whether reference targets receive generated labels.
    /// </summary>
    public bool GenerateLabels { get; set; } = true;

    /// <summary>
    ///  Gets or sets whether flow analysis follows code addresses stored in the image.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   When true, the NMI, RESET and IRQ vectors at <c>$FFFA</c>-<c>$FFFF</c> that lie inside the image become
    ///   data and their targets become entry points. A <c>JMP (abs)</c> whose pointer lies inside the image
    ///   is followed the same way, including the NMOS page-wrap when the pointer ends a page.
    ///  </para>
    /// </remarks>
    public bool FollowVectors { get; set; } = true;

    /// <summary>
    ///  Gets subroutine hints by entry address, including subroutines outside the image.
    /// </summary>
    public IDictionary<ushort, AnalysisCall> Calls { get; } = new Dictionary<ushort, AnalysisCall>();

    /// <summary>
    ///  Gets editable flow entry points; clear the initial entry when the image starts with data.
    /// </summary>
    public IList<ushort> EntryPoints { get; } = [];

    /// <summary>
    ///  Gets explicit code/data ranges. Explicit code is decoded linearly within its range.
    /// </summary>
    public IList<AnalysisRegion> Regions { get; } = [];

    /// <summary>
    ///  Gets user symbols by address, including external addresses outside the image.
    /// </summary>
    public IDictionary<ushort, string> Symbols { get; } = new Dictionary<ushort, string>();

    /// <summary>
    ///  Gets address-attached comments, which may contain multiple physical lines.
    /// </summary>
    public IDictionary<ushort, string> Comments { get; } = new Dictionary<ushort, string>();
}
