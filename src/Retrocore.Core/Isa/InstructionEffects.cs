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
///   Registers are bits by their index in <see cref="IsaDescription.EffectRegisters"/>, which
///   <see cref="IsaDescription.RegisterMask"/> gives for a name: a register with parts, such as the Z80's HL, is
///   its parts' bits. Flags are bits by their bit in the flags register (<see cref="IsaFlag.Bit"/>). Reading or
///   writing the flags register as a whole, as the 6502's <c>PHP</c> and <c>PLP</c> do, sets its register bit and
///   every flag's bit. The program counter is left to <see cref="InstructionFlow"/>, but where a 6809 postbyte
///   names it, as <c>PULS PC</c>, <c>TFR X,PC</c> and a <c>PCR</c> offset do; a memory operand is left to
///   <see cref="MemoryAccess"/>.
///  </para>
///  <para>
///   A written register or flag is assigned on every path through the instruction, so its old value is dead
///   afterwards; one that may be written, as by a conditional call's push, changes on some paths only; the rest
///   keep their values.
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
    ///  Gets whether a postbyte names some of the registers, as the MC6809's <c>PSHS</c>, <c>TFR</c> and indexed
    ///  modes do, and these effects, from <see cref="InstructionSet.Effects(int)"/> without it, leave them out;
    ///  <see cref="InstructionSet.Effects(int, byte)"/> adds them.
    /// </summary>
    public bool DependsOnPostbyte { get; init; }

    /// <summary>
    ///  Gets the registers read, as bits by register index.
    /// </summary>
    public uint RegistersRead { get; init; }

    /// <summary>
    ///  Gets the registers written, as bits by register index.
    /// </summary>
    public uint RegistersWritten { get; init; }

    /// <summary>
    ///  Gets the registers written on some paths only, such as the stack pointer of a conditional call, as bits by
    ///  register index; none of them is in <see cref="RegistersWritten"/>.
    /// </summary>
    public uint RegistersMayWrite { get; init; }

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
    ///  Gets the flags written on some paths only, as bits of the flags register; none of them is in
    ///  <see cref="FlagsWritten"/>.
    /// </summary>
    public byte FlagsMayWrite { get; init; }

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
    ///  Gets the flags written from state the effects leave out, such as the Z80's X and Y after <c>SCF</c>, which
    ///  come from its hidden Q register; running the instruction does not tell their values.
    /// </summary>
    public byte FlagsHidden { get; init; }

    /// <summary>
    ///  Gets the registers written from state the effects leave out, such as the 8085's A after <c>RIM</c>, which
    ///  holds its interrupt masks; running the instruction does not tell their values.
    /// </summary>
    public uint RegistersHidden { get; init; }

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
    ///  Gets the number of bytes pushed on the paths that push, as a conditional call's return address; 0 when
    ///  the pushes are in <see cref="Pushed"/> or there are none.
    /// </summary>
    public byte MayPush { get; init; }

    /// <summary>
    ///  Gets the number of bytes pulled on the paths that pull, as a conditional return's address.
    /// </summary>
    public byte MayPull { get; init; }

    /// <summary>
    ///  Gets the register, by bit, whose stack the pushes and pulls use, or -1 when there are none.
    /// </summary>
    public int StackRegister => StackRegisterPlusOne - 1;

    /// <summary>
    ///  Gets one more than <see cref="StackRegister"/>, so a default value has none.
    /// </summary>
    internal byte StackRegisterPlusOne { get; init; }

    /// <summary>
    ///  Gets the number of register copies, at most four: registers the instruction sets to another's value, as
    ///  TAX sets X to A.
    /// </summary>
    public byte CopyCount { get; init; }

    /// <summary>
    ///  Gets the copies, twelve bits each, the destination's register bit above the source's.
    /// </summary>
    internal ulong Copies { get; init; }

    /// <summary>
    ///  Gets one register copy: the register the instruction sets to the value another had before it.
    /// </summary>
    /// <param name="index">The copy, below <see cref="CopyCount"/>.</param>
    /// <param name="destination">Receives the register set, by bit.</param>
    /// <param name="source">Receives the register whose value it takes, by bit.</param>
    public void GetCopy(int index, out int destination, out int source)
    {
        ulong copy = (Copies >> (index * 12)) & 0xFFF;
        destination = (int)(copy >> 6);
        source = (int)(copy & 0x3F);
    }

    /// <summary>
    ///  Gets these effects with one more copy.
    /// </summary>
    /// <param name="destination">The register set, by bit.</param>
    /// <param name="source">The register whose value it takes, by bit.</param>
    /// <returns>The effects.</returns>
    /// <exception cref="InvalidOperationException">Four copies are already given.</exception>
    internal InstructionEffects WithCopy(int destination, int source) => CopyCount >= 4
        ? throw new InvalidOperationException("An instruction's effects hold at most four copies.")
        : this with
        {
            Copies = Copies | ((ulong)(((destination & 0x3F) << 6) | (source & 0x3F)) << (CopyCount * 12)),
            CopyCount = (byte)(CopyCount + 1)
        };

    /// <summary>
    ///  Gets these effects with another's copies after their own.
    /// </summary>
    /// <param name="other">The other effects.</param>
    /// <returns>The effects.</returns>
    internal InstructionEffects WithCopies(InstructionEffects other)
    {
        InstructionEffects effects = this;
        for (int index = 0; index < other.CopyCount; index++)
        {
            other.GetCopy(index, out int destination, out int source);
            effects = effects.WithCopy(destination, source);
        }

        return effects;
    }

    /// <summary>
    ///  Gets the flags a conditional branch, call or return decides on, as bits of the flags register, at most
    ///  four; 0 when the instruction has no condition on flags.
    /// </summary>
    public byte ConditionFlags { get; init; }

    /// <summary>
    ///  Gets the condition's truth table: bit <c>n</c> is set when the instruction is taken with the condition's
    ///  flags, in bit order, set as the bits of <c>n</c>.
    /// </summary>
    internal ushort ConditionTable { get; init; }

    /// <summary>
    ///  Gets whether the instruction is taken, given some flags' values.
    /// </summary>
    /// <param name="known">The flags whose values are known, as bits of the flags register.</param>
    /// <param name="values">Their values, as bits of the flags register.</param>
    /// <returns>
    ///  True when it is taken whatever the unknown flags are, false when it is not, and null when they decide, or
    ///  the instruction has no condition.
    /// </returns>
    public bool? Taken(byte known, byte values)
    {
        if (ConditionFlags == 0) { return null; }
        bool anyTaken = false, anyNot = false;
        int count = 1 << CountBits(ConditionFlags);
        for (int row = 0; row < count; row++)
        {
            if (!Agrees(row, known, values)) { continue; }
            if ((ConditionTable & (1 << row)) != 0) { anyTaken = true; } else { anyNot = true; }
        }

        return anyTaken == anyNot ? null : anyTaken;
    }

    /// <summary>
    ///  Gets what taking the instruction, or not, says of the condition's flags: those that have one value in
    ///  every case that agrees with what is known, as BNE taken says zero is clear.
    /// </summary>
    /// <param name="taken">Whether the instruction is taken.</param>
    /// <param name="known">The flags whose values are known, as bits of the flags register.</param>
    /// <param name="values">Their values, as bits of the flags register.</param>
    /// <param name="implied">Receives the flags whose values the outcome fixes, as bits of the flags register.</param>
    /// <param name="impliedValues">Receives their values.</param>
    public void Implied(bool taken, byte known, byte values, out byte implied, out byte impliedValues)
    {
        implied = 0;
        impliedValues = 0;
        if (ConditionFlags == 0) { return; }
        byte ones = 0xFF, zeros = 0xFF;
        bool any = false;
        int count = 1 << CountBits(ConditionFlags);
        for (int row = 0; row < count; row++)
        {
            if (!Agrees(row, known, values) || ((ConditionTable & (1 << row)) != 0) != taken) { continue; }
            byte flags = Flags(row);
            ones &= flags;
            zeros &= (byte)~flags;
            any = true;
        }

        if (!any) { return; }
        implied = (byte)((ones | zeros) & ConditionFlags);
        impliedValues = (byte)(ones & ConditionFlags);
    }

    // A truth table row's flags, as bits of the flags register.
    private byte Flags(int row)
    {
        byte flags = 0;
        int index = 0;
        for (int bit = 0; bit < 8; bit++)
        {
            if ((ConditionFlags & (1 << bit)) == 0) { continue; }
            if ((row & (1 << index)) != 0) { flags |= (byte)(1 << bit); }
            index++;
        }

        return flags;
    }

    private bool Agrees(int row, byte known, byte values) => ((Flags(row) ^ values) & known & ConditionFlags) == 0;

    /// <summary>
    ///  Gets whether a register is read.
    /// </summary>
    /// <param name="register">The register's bit in <see cref="IsaDescription.EffectRegisters"/>.</param>
    /// <returns>Whether it is read.</returns>
    public bool Reads(int register) => (uint)register < 32 && (RegistersRead & (1u << register)) != 0;

    /// <summary>
    ///  Gets whether a register is written on every path.
    /// </summary>
    /// <param name="register">The register's bit in <see cref="IsaDescription.EffectRegisters"/>.</param>
    /// <returns>Whether it is written.</returns>
    public bool Writes(int register) => (uint)register < 32 && (RegistersWritten & (1u << register)) != 0;

    /// <summary>
    ///  Gets whether any of some registers is read, as any of a pair's halves.
    /// </summary>
    /// <param name="mask">The registers' bits, from <see cref="IsaDescription.RegisterMask"/>.</param>
    /// <returns>Whether one is read.</returns>
    public bool ReadsAny(uint mask) => (RegistersRead & mask) != 0;

    /// <summary>
    ///  Gets whether any of some registers may change, on every path or some.
    /// </summary>
    /// <param name="mask">The registers' bits, from <see cref="IsaDescription.RegisterMask"/>.</param>
    /// <returns>Whether one may change.</returns>
    public bool ChangesAny(uint mask) => ((RegistersWritten | RegistersMayWrite) & mask) != 0;

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

    // The number of bits set; the generators' netstandard2.0 has no BitOperations.
    private static int CountBits(byte value)
    {
        int count = 0;
        for (; value != 0; value &= (byte)(value - 1)) { count++; }
        return count;
    }
}
