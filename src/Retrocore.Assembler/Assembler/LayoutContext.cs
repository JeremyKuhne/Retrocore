// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

/// <summary>
///  Stack-owned counters and bounds passed together through one layout pass.
/// </summary>
internal struct LayoutContext
{
    /// <summary>
    ///  Gets or sets the logical address.
    /// </summary>
    internal int Address { get; set; }

    /// <summary>
    ///  Gets or sets the output offset.
    /// </summary>
    internal int Offset { get; set; }

    /// <summary>
    ///  Gets or sets the section capacity.
    /// </summary>
    internal int Capacity { get; set; }

    /// <summary>
    ///  Gets or sets the maximum transient width allowance.
    /// </summary>
    internal int ShrinkBudget { get; set; }

    /// <summary>
    ///  Gets or sets the address restored by .dend.
    /// </summary>
    internal int DummyAddress { get; set; }

    /// <summary>
    ///  Gets or sets the open .dum index, or -1.
    /// </summary>
    internal int DummyLine { get; set; }

    /// <summary>
    ///  Gets or sets whether this pass used a transient width allowance.
    /// </summary>
    internal bool RelaxedBounds { get; set; }

    /// <summary>
    ///  Gets or sets whether the selected section emits no file bytes.
    /// </summary>
    internal bool NoOutput { get; set; }

    /// <summary>
    ///  Gets or sets the current section's run address, where an empty .logicalorg returns the location counter.
    /// </summary>
    internal int RunOrigin { get; set; }

    /// <summary>
    ///  Gets or sets whether the current section has a provisional address, so its labels stay unknown this pass.
    /// </summary>
    internal bool SectionProvisional { get; set; }

    /// <summary>
    ///  Gets or sets whether labels at the location counter stay unknown: the section is provisional and no
    ///  .logicalorg has given the counter an absolute value.
    /// </summary>
    internal bool Provisional { get; set; }

    /// <summary>
    ///  Gets or sets whether the current section is a linker segment, whose .align pads relative to its start.
    /// </summary>
    internal bool SegmentRelative { get; set; }

    /// <summary>
    ///  Gets or sets whether a .logicalorg region gives the location counter an absolute value.
    /// </summary>
    internal bool Logical { get; set; }

    /// <summary>
    ///  Gets or sets the .sizeof symbols that receive the size of the statement at a given line, when any exist.
    /// </summary>
    internal Dictionary<int, int>? LabelSizes { get; set; }
}
