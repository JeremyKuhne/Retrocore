// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Isa;

/// <summary>
///  The registers and flags one encoding reads and writes, and what it does to the stack, from the description's
///  <c>effects</c> lines.
/// </summary>
/// <remarks>
///  <para>
///   Registers are bits by their index in <see cref="IsaDescription.Registers"/>; flags are bits by their bit in
///   the flags register (<see cref="IsaFlag.Bit"/>). Reading or writing the flags register as a whole, as the
///   6502's <c>PHP</c> and <c>PLP</c> do, sets its register bit and every flag's bit. The program counter is left
///   to <see cref="InstructionFlow"/>, and a memory operand to <see cref="MemoryAccess"/>.
///  </para>
///  <para>
///   A written register or flag is assigned on every path through the instruction, so its old value is dead
///   afterwards; one not written keeps its value.
///  </para>
/// </remarks>
public readonly record struct InstructionEffects
{
    /// <summary>
    ///  Gets whether the description says what the encoding does; when false, every other property is empty and
    ///  means nothing.
    /// </summary>
    public bool IsKnown { get; init; }

    /// <summary>
    ///  Gets the registers read, as bits by register index.
    /// </summary>
    public uint RegistersRead { get; init; }

    /// <summary>
    ///  Gets the registers written, as bits by register index.
    /// </summary>
    public uint RegistersWritten { get; init; }

    /// <summary>
    ///  Gets the flags read, as bits of the flags register.
    /// </summary>
    public byte FlagsRead { get; init; }

    /// <summary>
    ///  Gets the flags written, as bits of the flags register, including those in <see cref="FlagsSet"/>,
    ///  <see cref="FlagsCleared"/> and <see cref="FlagsFromOperand"/>.
    /// </summary>
    public byte FlagsWritten { get; init; }

    /// <summary>
    ///  Gets the flags always set to 1, such as the carry after <c>SEC</c>.
    /// </summary>
    public byte FlagsSet { get; init; }

    /// <summary>
    ///  Gets the flags always cleared to 0, such as the carry after <c>CLC</c>.
    /// </summary>
    public byte FlagsCleared { get; init; }

    /// <summary>
    ///  Gets the flags that become a copy of a bit of the memory operand, as <c>BIT</c> copies bits 7 and 6;
    ///  <see cref="OperandBit(int)"/> says which bit.
    /// </summary>
    public byte FlagsFromOperand { get; init; }

    /// <summary>
    ///  Gets, four bits per flag bit, one more than the operand bit each flag in <see cref="FlagsFromOperand"/>
    ///  copies.
    /// </summary>
    internal uint OperandBits { get; init; }

    /// <summary>
    ///  Gets the number of bytes pushed onto the stack.
    /// </summary>
    public byte Pushed { get; init; }

    /// <summary>
    ///  Gets the number of bytes pulled from the stack.
    /// </summary>
    public byte Pulled { get; init; }

    /// <summary>
    ///  Gets whether a register is read.
    /// </summary>
    /// <param name="register">The register's index in <see cref="IsaDescription.Registers"/>.</param>
    /// <returns>Whether it is read.</returns>
    public bool Reads(int register) => (uint)register < 32 && (RegistersRead & (1u << register)) != 0;

    /// <summary>
    ///  Gets whether a register is written.
    /// </summary>
    /// <param name="register">The register's index in <see cref="IsaDescription.Registers"/>.</param>
    /// <returns>Whether it is written.</returns>
    public bool Writes(int register) => (uint)register < 32 && (RegistersWritten & (1u << register)) != 0;

    /// <summary>
    ///  Gets whether a flag is read.
    /// </summary>
    /// <param name="bit">The flag's bit in the flags register.</param>
    /// <returns>Whether it is read.</returns>
    public bool ReadsFlag(int bit) => (uint)bit < 8 && (FlagsRead & (1 << bit)) != 0;

    /// <summary>
    ///  Gets whether a flag is written.
    /// </summary>
    /// <param name="bit">The flag's bit in the flags register.</param>
    /// <returns>Whether it is written.</returns>
    public bool WritesFlag(int bit) => (uint)bit < 8 && (FlagsWritten & (1 << bit)) != 0;

    /// <summary>
    ///  Gets the bit of the memory operand a flag becomes a copy of.
    /// </summary>
    /// <param name="bit">The flag's bit in the flags register.</param>
    /// <returns>The operand bit, or -1 when the flag is not a copy of one.</returns>
    public int OperandBit(int bit) => (uint)bit < 8 ? (int)((OperandBits >> (bit * 4)) & 0xF) - 1 : -1;
}
