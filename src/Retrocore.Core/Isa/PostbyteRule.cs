// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Isa;

/// <summary>
///  How an encoding's postbyte adds to its effects: the operand slots its effects lines name, which take the
///  registers the postbyte names, and where the postbyte is.
/// </summary>
internal readonly record struct PostbyteRule
{
    /// <summary>
    ///  Gets the slots read.
    /// </summary>
    internal byte ReadSlots { get; init; }

    /// <summary>
    ///  Gets the slots written.
    /// </summary>
    internal byte WriteSlots { get; init; }

    /// <summary>
    ///  Gets the slots that may be written.
    /// </summary>
    internal byte MayWriteSlots { get; init; }

    /// <summary>
    ///  Gets the slot, 1 to 8, whose register list gives the bytes pushed, or 0.
    /// </summary>
    internal byte PushSlot { get; init; }

    /// <summary>
    ///  Gets the slot whose register list gives the bytes pulled, or 0.
    /// </summary>
    internal byte PullSlot { get; init; }

    /// <summary>
    ///  Gets the postbyte's field kind.
    /// </summary>
    internal OperandFieldKind Kind { get; init; }

    /// <summary>
    ///  Gets the postbyte's offset in the instruction, after the opcode.
    /// </summary>
    internal byte PostbyteAt { get; init; }

    /// <summary>
    ///  Gets any slot named, nonzero when one is.
    /// </summary>
    internal int Slots => ReadSlots | WriteSlots | MayWriteSlots | PushSlot | PullSlot;

    /// <summary>
    ///  Adds a line's slots.
    /// </summary>
    /// <param name="line">The line.</param>
    /// <returns>The rule with them.</returns>
    internal PostbyteRule With(EffectsLine line) => this with
    {
        ReadSlots = (byte)(ReadSlots | line.ReadSlots),
        WriteSlots = (byte)(WriteSlots | line.WriteSlots),
        MayWriteSlots = (byte)(MayWriteSlots | line.MayWriteSlots),
        PushSlot = line.PushSlot != 0 ? line.PushSlot : PushSlot,
        PullSlot = line.PullSlot != 0 ? line.PullSlot : PullSlot
    };
}
