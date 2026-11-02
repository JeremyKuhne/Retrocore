// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Isa;

/// <summary>
///  One instruction encoding: a mnemonic in an operand form, and its opcode bytes.
/// </summary>
/// <param name="Mnemonic">The dense mnemonic ID within its instruction set.</param>
/// <param name="Form">The operand form ID.</param>
/// <param name="Opcode">The opcode bytes, first byte in the low eight bits.</param>
/// <param name="OpcodeLength">The number of opcode bytes, 1-4.</param>
/// <param name="Undocumented">Whether the encoding is undocumented, such as an NMOS 6502's illegal opcodes.</param>
/// <param name="SplitAt">
///  The number of opcode bytes before the operand bytes when the rest of the opcode follows them, as in the
///  Z80's <c>DD CB d op</c>; 0 when the operand bytes follow the whole opcode.
/// </param>
public readonly record struct IsaEncoding(
    ushort Mnemonic,
    ushort Form,
    uint Opcode,
    byte OpcodeLength,
    bool Undocumented = false,
    byte SplitAt = 0)
{
    /// <summary>
    ///  Gets the nominal clock cycles, or for a conditional instruction those when it is not taken; 0 when the
    ///  description gives none.
    /// </summary>
    public byte Cycles { get; init; }

    /// <summary>
    ///  Gets the nominal clock cycles of a conditional instruction when it is taken; the same as
    ///  <see cref="Cycles"/> otherwise.
    /// </summary>
    public byte CyclesTaken { get; init; }

    /// <summary>
    ///  Gets the number of opcode bytes before the operand bytes.
    /// </summary>
    public int OpcodeBytesBeforeOperands => SplitAt == 0 ? OpcodeLength : SplitAt;

    /// <summary>
    ///  Gets where an opcode byte sits in the encoded instruction.
    /// </summary>
    /// <param name="index">The opcode byte index, below <see cref="OpcodeLength"/>.</param>
    /// <param name="operandSize">The size of the operand bytes.</param>
    /// <returns>The byte's offset from the start of the instruction.</returns>
    public int OpcodeBytePosition(int index, int operandSize) => index < OpcodeBytesBeforeOperands ? index : index + operandSize;

    /// <summary>
    ///  Gets the opcode byte at an index.
    /// </summary>
    /// <param name="index">The byte index, below <see cref="OpcodeLength"/>.</param>
    /// <returns>The byte.</returns>
    public byte OpcodeByte(int index) => (byte)(Opcode >> (index * 8));
}
