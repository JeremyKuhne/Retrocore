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
    // An instruction is at most five bytes: the first four packed into _bytes, the fifth in _fifthByte.
    private readonly uint _bytes;
    private readonly ushort _set;
    private readonly ushort _encoding;
    private readonly byte _size;
    private readonly byte _fifthByte;

    /// <summary>
    ///  The most bytes a postbyte field and the bytes it selects take, in an instruction of at most five bytes.
    /// </summary>
    internal const int MaximumPostbyteField = 4;

    /// <summary>
    ///  Creates a complete, validated decoding.
    /// </summary>
    /// <param name="address">The instruction address.</param>
    /// <param name="set">The <see cref="InstructionSet.Handle"/> of the set that decoded it.</param>
    /// <param name="encoding">The encoding's ID in that set.</param>
    /// <param name="bytes">The first four original bytes, first byte in the low eight bits.</param>
    /// <param name="size">The complete encoding length.</param>
    /// <param name="fifthByte">The fifth original byte when <paramref name="size"/> is 5.</param>
    internal DisassembledInstruction(ushort address, ushort set, ushort encoding, uint bytes, byte size, byte fifthByte = 0)
    {
        Address = address;
        _set = set;
        _encoding = encoding;
        _bytes = bytes;
        _size = size;
        _fifthByte = fifthByte;
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
    public DisassemblyFlow Flow
    {
        get
        {
            // A jump through a postbyte that names its target directly, such as JMP Label,PCR, is a direct jump.
            DisassemblyFlow flow = (DisassemblyFlow)InstructionSet.Flow(_encoding);
            return flow == DisassemblyFlow.IndirectJump && PostbyteReference == PostbyteReference.Target
                ? DisassemblyFlow.Jump
                : flow;
        }
    }

    /// <summary>
    ///  Gets a relative branch or PC-relative target, with 16-bit program-counter wrapping.
    /// </summary>
    public ushort? RelativeTarget
    {
        get
        {
            OperandForm form = Form;
            int relative = form.RelativeField;
            if (relative >= 0)
            {
                return Field(relative);
            }

            return PostbyteReference == PostbyteReference.Target ? Field(0) : null;
        }
    }

    /// <summary>
    ///  Gets what the instruction's postbyte field refers to, or <see cref="PostbyteReference.None"/> when its
    ///  form has no postbyte field.
    /// </summary>
    public PostbyteReference PostbyteReference
    {
        get
        {
            OperandForm form = Form;
            if (!form.HasPostbyte) { return PostbyteReference.None; }
            Span<byte> buffer = stackalloc byte[MaximumPostbyteField];
            return Postbytes.GetReference(form.Field(0), PostbyteBytes(buffer));
        }
    }

    /// <summary>
    ///  Gets a direct branch, jump or call target, including one the opcode implies, such as the 8085's
    ///  <c>RSTV</c> to <c>$40</c>; indirect pointers are never resolved.
    /// </summary>
    public ushort? DirectTarget =>
        Flow is DisassemblyFlow.Jump or DisassemblyFlow.Call or DisassemblyFlow.ConditionalBranch
            ? RelativeTarget ?? AbsoluteTarget() ?? Encoding.FixedTarget
            : null;

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
    public byte GetByte(int index) => (uint)index >= (uint)Size
        ? throw new ArgumentOutOfRangeException(nameof(index))
        : index == 4
            ? _fifthByte
            : (byte)(_bytes >> (index * InstructionEncoding.BitsPerByte));

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
            OperandFieldKind.Restart or OperandFieldKind.RestartNumber => (ushort)(LastOpcodeByte(encoding, form) & 0x38),
            OperandFieldKind.IndexedPostbyte
                or OperandFieldKind.RegisterPair
                or OperandFieldKind.SystemStackMask
                or OperandFieldKind.UserStackMask => PostbyteField(form.Field(index)),
            _ => Word(set, offset)
        };
    }

    /// <summary>
    ///  Copies the postbyte field's bytes, postbyte first, from a form whose one field is a postbyte.
    /// </summary>
    /// <param name="buffer">At least <see cref="MaximumPostbyteField"/> bytes.</param>
    /// <returns>The field's bytes.</returns>
    internal ReadOnlySpan<byte> PostbyteBytes(Span<byte> buffer)
    {
        int offset = Encoding.OpcodeBytesBeforeOperands;
        int count = Size - offset;
        for (int index = 0; index < count; index++) { buffer[index] = GetByte(offset + index); }
        return buffer[..count];
    }

    /// <summary>
    ///  Gets the codec of a set that decoded a postbyte field; a set without one decodes no such field.
    /// </summary>
    internal PostbyteCodec Postbytes => InstructionSet.Postbytes
        ?? throw new InvalidOperationException($"Instruction set '{InstructionSet.Name}' has no postbyte codec.");

    private ushort PostbyteField(OperandFieldKind kind)
    {
        Span<byte> buffer = stackalloc byte[MaximumPostbyteField];
        return Postbytes.Decode(kind, PostbyteBytes(buffer), unchecked((ushort)(Address + Size)));
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
        return address || field is OperandFieldKind.Restart or OperandFieldKind.RestartNumber ? Operand : null;
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
