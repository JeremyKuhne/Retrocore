// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

/// <summary>
///  What a routine does to its caller's registers and flags on every return the analysis followed: which it keeps,
///  which it changes, with an instruction that changes each, and which are unknown, as after a call the analysis
///  could not follow.
/// </summary>
/// <remarks>
///  <para>
///   Registers are bits of <see cref="Isa.IsaDescription.EffectRegisters"/> without parts; flags are bits of the
///   flags register. A register is kept when, on every return, it holds the value it had on entry, as one saved
///   with a push and restored with a pull does.
///  </para>
/// </remarks>
internal sealed record AnalysisRoutineSummary
{
    /// <summary>
    ///  Gets the registers kept, as bits.
    /// </summary>
    public uint KeptRegisters { get; init; }

    /// <summary>
    ///  Gets the flags kept, as bits of the flags register.
    /// </summary>
    public byte KeptFlags { get; init; }

    /// <summary>
    ///  Gets the registers whose value at a return is not known, as bits: neither kept nor surely changed.
    /// </summary>
    public uint UnknownRegisters { get; init; }

    /// <summary>
    ///  Gets the flags whose value at a return is not known.
    /// </summary>
    public byte UnknownFlags { get; init; }

    /// <summary>
    ///  Gets whether the routine does to the stack what the analysis cannot follow, as pulling its own return
    ///  address, as one that reads inline data after its call does, or moving the stack pointer, as one that saves
    ///  its caller's registers under the return address does; its callers cannot be followed past the call.
    /// </summary>
    public bool ChangesCallerStack { get; init; }

    /// <summary>
    ///  Gets, for each register and flag some path to a return surely changes, the address of an instruction that
    ///  changes it: registers by bit, then flags at 32 plus their bit; one missing is changed where the paths disagree.
    /// </summary>
    public IReadOnlyDictionary<int, ushort> ChangedAt { get; init; } = new Dictionary<int, ushort>();

    /// <summary>
    ///  Gets whether the analysis reached a return.
    /// </summary>
    public bool Returns { get; init; }

    /// <summary>
    ///  Gets why some path could not be followed, such as an indirect jump, or null when every path was; the
    ///  summary then describes only the returns it reached.
    /// </summary>
    public string? Incomplete { get; init; }

    /// <summary>
    ///  Gets where the first path that could not be followed stopped.
    /// </summary>
    public ushort IncompleteAt { get; init; }

    /// <summary>
    ///  Gets whether the summary comes from the routine's documentation rather than its code.
    /// </summary>
    public bool Documented { get; init; }
}
