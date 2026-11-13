// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

/// <summary>
///  A decoded p-code.
/// </summary>
/// <param name="Offset">Where it is, from the start of its segment.</param>
/// <param name="Opcode">Its opcode.</param>
/// <param name="Length">Its length in bytes, with its operands.</param>
/// <param name="Operands">
///  Its operand values: the numbers after the opcode, or for <c>XJP</c> the lowest and highest index; a string's or
///  constant's bytes are in <paramref name="Data"/>.
/// </param>
/// <param name="Data">
///  A string's characters, a packed array's bytes, or a constant's words, least significant first.
/// </param>
/// <param name="Targets">
///  Where it can jump: one offset for a jump, or for <c>XJP</c> the target taken outside the range then one for each
///  index; an offset of -1 is a jump the decoder could not follow.
/// </param>
public sealed record PcodeInstruction(
    int Offset,
    PcodeOpcode Opcode,
    int Length,
    IReadOnlyList<int> Operands,
    byte[] Data,
    IReadOnlyList<int> Targets)
{
    /// <summary>
    ///  Gets the offset of the p-code after it.
    /// </summary>
    public int Next => Offset + Length;

    /// <inheritdoc/>
    public override string ToString() => PcodeDisassembler.Format(this);
}
