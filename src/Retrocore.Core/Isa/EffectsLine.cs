// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Isa;

/// <summary>
///  One instruction's, or form's, effects from an <c>effects</c> line, and whether an encoding took them.
/// </summary>
/// <param name="Effects">The effects of the registers and flags the line names.</param>
/// <param name="Line">The line that gave them.</param>
/// <remarks>
///  <para>
///   <c>$1</c> to <c>$8</c> name an encoding's operands, the comma-separated parts of its form's name: a register
///   operand is the register itself, and a bracketed one, such as <c>[HL]</c> or <c>[IX+d]</c>, is read for its
///   address wherever it is named. The slots are bits, <c>$1</c> in bit 0, and are resolved per encoding.
///  </para>
/// </remarks>
internal sealed record EffectsLine(InstructionEffects Effects, int Line)
{
    /// <summary>
    ///  Gets the operand slots read.
    /// </summary>
    internal byte ReadSlots { get; init; }

    /// <summary>
    ///  Gets the operand slots written.
    /// </summary>
    internal byte WriteSlots { get; init; }

    /// <summary>
    ///  Gets the operand slots that may be written.
    /// </summary>
    internal byte MayWriteSlots { get; init; }

    /// <summary>
    ///  Gets or sets whether some encoding of some set took these effects, so a line no encoding takes, such as
    ///  a misspelled instruction, can be reported.
    /// </summary>
    internal bool Used { get; set; }
}
