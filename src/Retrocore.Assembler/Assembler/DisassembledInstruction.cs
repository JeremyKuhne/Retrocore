// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Isa;

namespace Retrocore.Assembler;

/// <summary>
///  An owned, allocation-free decoded instruction. A default value is not a decoded instruction.
/// </summary>
/// <remarks>
///  <para>
///   Encoded operands describe static values, bases or pointers, not register-dependent effective addresses.
///   Formatting is a readable view and can hide opcode aliases; use <see cref="DisassemblyResult.ExportSource"/>
///   when source must reproduce the exact original bytes.
///  </para>
/// </remarks>
public readonly struct DisassembledInstruction
{
    private readonly uint _bytes;
    private readonly ushort _set;
    private readonly ushort _encoding;
    private readonly byte _size;

    /// <summary>
    ///  Creates a complete, validated decoding.
    /// </summary>
    /// <param name="address">The instruction address.</param>
    /// <param name="set">The <see cref="InstructionSet.Handle"/> of the set that decoded it.</param>
    /// <param name="encoding">The encoding's ID in that set.</param>
    /// <param name="bytes">The original bytes, first byte in the low eight bits.</param>
    /// <param name="size">The complete encoding length.</param>
    internal DisassembledInstruction(ushort address, ushort set, ushort encoding, uint bytes, byte size)
    {
        Address = address;
        _set = set;
        _encoding = encoding;
        _bytes = bytes;
        _size = size;
    }

    /// <summary>
    ///  Gets the instruction's 16-bit address.
    /// </summary>
    public ushort Address { get; }

    /// <summary>
    ///  Gets the instruction set that decoded it.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   The value holds the set's handle rather than a reference, so it stays unmanaged and can live in
    ///   stack-allocated buffers.
    ///  </para>
    /// </remarks>
    /// <exception cref="ArgumentOutOfRangeException">The value is default, not a decoded instruction.</exception>
    public InstructionSet InstructionSet => InstructionSet.FromHandle(_set);

    /// <summary>
    ///  Gets the encoding's ID in <see cref="InstructionSet"/>.
    /// </summary>
    public int EncodingId => _encoding;

    /// <summary>
    ///  Gets the encoding: mnemonic, form and opcode.
    /// </summary>
    public IsaEncoding Encoding => InstructionSet.GetEncoding(_encoding);

    /// <summary>
    ///  Gets the operand form.
    /// </summary>
    public OperandForm Form
    {
        get
        {
            InstructionSet set = InstructionSet;
            return set.GetForm(set.GetEncoding(_encoding).Form);
        }
    }

    /// <summary>
    ///  Gets the encoded byte count, or zero for a default value.
    /// </summary>
    public int Size => _size;

    /// <summary>
    ///  Gets the mnemonic, including a numbered bit-operation suffix when applicable.
    /// </summary>
    public string Mnemonic => InstructionSet.MnemonicName(Encoding.Mnemonic);

    /// <summary>
    ///  Gets the instruction's name without a bit suffix, such as <c>BBR</c> for <c>BBR3</c>.
    /// </summary>
    public string InstructionName => InstructionSet.InstructionName(Encoding.Mnemonic);

    /// <summary>
    ///  Gets the first operand field: the immediate value, encoded address, base address or indirect pointer.
    /// </summary>
    public ushort Operand => Form.FieldCount == 0 ? (ushort)0 : Field(0);

    /// <summary>
    ///  Gets the zero-page address tested by a bit branch.
    /// </summary>
    public byte ZeroPageOperand => (byte)Operand;

    /// <summary>
    ///  Gets the statically described control-flow effect.
    /// </summary>
    public DisassemblyFlow Flow => (DisassemblyFlow)InstructionSet.Flow(_encoding);

    /// <summary>
    ///  Gets a relative branch target, with 16-bit program-counter wrapping.
    /// </summary>
    public ushort? RelativeTarget
    {
        get
        {
            int relative = Form.RelativeField;
            return relative < 0 ? null : Field(relative);
        }
    }

    /// <summary>
    ///  Gets a direct branch, jump or call target; indirect pointers are never resolved.
    /// </summary>
    public ushort? DirectTarget => RelativeTarget ?? AbsoluteTarget();

    /// <summary>
    ///  Gets whether this is an undocumented encoding, such as an NMOS 6502's illegal opcodes and alternate
    ///  NOP/SBC encodings.
    /// </summary>
    public bool IsUndocumented => Encoding.Undocumented;

    /// <summary>
    ///  Gets an original encoding byte without retaining caller-owned storage.
    /// </summary>
    /// <param name="index">The zero-based encoding-byte index.</param>
    /// <returns>The byte.</returns>
    public byte GetByte(int index) => (uint)index < (uint)Size
        ? (byte)(_bytes >> (index * InstructionEncoding.BitsPerByte)) : throw new ArgumentOutOfRangeException(nameof(index));

    /// <summary>
    ///  Gets an operand field's value; a relative field's value is its target address.
    /// </summary>
    /// <param name="index">The field index in <see cref="Form"/>.</param>
    /// <returns>The value.</returns>
    public ushort Field(int index)
    {
        InstructionSet set = InstructionSet;
        IsaEncoding encoding = set.GetEncoding(_encoding);
        OperandForm form = set.GetForm(encoding.Form);
        int offset = encoding.OpcodeBytesBeforeOperands + form.FieldOffset(index);
        return form.Field(index) switch
        {
            OperandFieldKind.Byte => GetByte(offset),
            OperandFieldKind.Relative8 => unchecked((ushort)(Address + Size + (sbyte)GetByte(offset))),
            OperandFieldKind.Relative16 => unchecked((ushort)(Address + Size + Word(set, offset))),
            OperandFieldKind.Displacement8 => unchecked((ushort)(sbyte)GetByte(offset)),
            OperandFieldKind.BitNumber => (ushort)((LastOpcodeByte(encoding, form) >> 3) & 7),
            OperandFieldKind.Restart => (ushort)(LastOpcodeByte(encoding, form) & 0x38),
            _ => Word(set, offset)
        };
    }

    // A field held in the opcode is in bits 3-5 of its last byte, which a split opcode puts after the operands.
    private byte LastOpcodeByte(IsaEncoding encoding, OperandForm form) =>
        GetByte(encoding.OpcodeBytePosition(encoding.OpcodeLength - 1, form.Size));

    // An absolute jump, call or branch to an encoded address, or a restart's fixed one.
    private ushort? AbsoluteTarget()
    {
        if (Flow is not (DisassemblyFlow.Jump or DisassemblyFlow.Call or DisassemblyFlow.ConditionalBranch))
        {
            return null;
        }

        OperandForm form = Form;
        if (form.FieldCount != 1) { return null; }
        OperandFieldKind field = form.Field(0);
        bool address = form is { Role: OperandRole.Memory, IsIndexed: false } && field == OperandFieldKind.Word;
        return address || field == OperandFieldKind.Restart ? Operand : null;
    }

    /// <summary>
    ///  Formats an instruction into caller storage without allocations.
    /// </summary>
    /// <param name="destination">The text destination.</param>
    /// <param name="charsWritten">The complete text length, or zero if the destination is too small.</param>
    /// <returns>Whether the complete instruction fit.</returns>
    public bool TryFormat(Span<char> destination, out int charsWritten) =>
        Disassembler.TryFormat(in this, destination, out charsWritten);

    /// <inheritdoc/>
    public override string ToString()
    {
        Span<char> text = stackalloc char[Disassembler.InstructionTextBufferSize];
        return TryFormat(text, out int length) ? text[..length].ToString()
            : throw new InvalidOperationException("The instruction formatting buffer was too small.");
    }

    // A word in the CPU's byte order.
    private ushort Word(InstructionSet set, int offset) => set.Endianness == Endianness.Little
        ? (ushort)(GetByte(offset) | (GetByte(offset + 1) << InstructionEncoding.BitsPerByte))
        : (ushort)((GetByte(offset) << InstructionEncoding.BitsPerByte) | GetByte(offset + 1));
}
