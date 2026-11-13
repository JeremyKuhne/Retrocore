// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Isa;

/// <summary>
///  Reads and writes an instruction set's postbyte operand fields: the fields after the opcode whose bytes
///  encode registers, modes or a variable number of offset bytes rather than a plain value.
/// </summary>
/// <remarks>
///  <para>
///   The postbyte field kinds are <see cref="OperandFieldKind.IndexedPostbyte"/>,
///   <see cref="OperandFieldKind.RegisterPair"/>, <see cref="OperandFieldKind.SystemStackMask"/> and
///   <see cref="OperandFieldKind.UserStackMask"/>. The instruction-set description names them; the CPU's
///   project supplies the codec that knows their bytes, one per instruction set, so a variant such as the
///   HD6309 can read the same kinds differently.
///  </para>
///  <para>
///   Every member is allocation-free except for the diagnostics of an operand that does not assemble.
///  </para>
/// </remarks>
public abstract class PostbyteCodec
{
    /// <summary>
    ///  Gets the length of a postbyte field, validating its postbyte.
    /// </summary>
    /// <param name="kind">The field kind.</param>
    /// <param name="operand">The bytes from the postbyte to the end of the available input.</param>
    /// <param name="size">Receives the field's length, postbyte included.</param>
    /// <returns>Whether the postbyte is valid for this instruction set.</returns>
    public abstract bool TryGetSize(OperandFieldKind kind, ReadOnlySpan<byte> operand, out int size);

    /// <summary>
    ///  Gets a decoded field's value: its target or pointer address, a constant offset, or the postbyte itself.
    /// </summary>
    /// <param name="kind">The field kind.</param>
    /// <param name="operand">The field's bytes, postbyte first.</param>
    /// <param name="nextAddress">The address after the whole instruction.</param>
    /// <returns>The value.</returns>
    public abstract ushort Decode(OperandFieldKind kind, ReadOnlySpan<byte> operand, ushort nextAddress);

    /// <summary>
    ///  Gets what a decoded field refers to, for flow analysis and symbolic export.
    /// </summary>
    /// <param name="kind">The field kind.</param>
    /// <param name="operand">The field's bytes, postbyte first.</param>
    /// <returns>The kind of address the field holds, if any.</returns>
    public abstract PostbyteReference GetReference(OperandFieldKind kind, ReadOnlySpan<byte> operand);

    /// <summary>
    ///  Formats a decoded field in native syntax that assembles back to the same bytes.
    /// </summary>
    /// <param name="kind">The field kind.</param>
    /// <param name="operand">The field's bytes, postbyte first.</param>
    /// <param name="nextAddress">The address after the whole instruction.</param>
    /// <param name="buffer">The destination.</param>
    /// <param name="length">The write position, advanced past the field.</param>
    public abstract void Format(
        OperandFieldKind kind,
        ReadOnlySpan<byte> operand,
        ushort nextAddress,
        Span<char> buffer,
        ref int length);

    /// <summary>
    ///  Gets whether operand text has a field kind's syntax, to choose between it and the other forms.
    /// </summary>
    /// <param name="kind">The field kind.</param>
    /// <param name="text">The trimmed operand text.</param>
    /// <returns>Whether the text is written as this kind of field.</returns>
    public abstract bool HasSyntax(OperandFieldKind kind, ReadOnlySpan<char> text);

    /// <summary>
    ///  Gets whether a word in operand text is a register in its place in postbyte syntax, and so no symbol.
    /// </summary>
    /// <param name="text">The operand text.</param>
    /// <param name="start">The word's start.</param>
    /// <param name="length">The word's length.</param>
    /// <returns>Whether the word is a register.</returns>
    public abstract bool IsRegisterToken(ReadOnlySpan<char> text, int start, int length);

    /// <summary>
    ///  Parses operand text into its structure and the one expression the assembler must evaluate, if any.
    /// </summary>
    /// <param name="kind">The field kind.</param>
    /// <param name="text">The operand text.</param>
    /// <param name="operand">Receives the parsed operand.</param>
    /// <param name="error">Receives the diagnostic when the text is malformed.</param>
    /// <returns>Whether the text parsed.</returns>
    public abstract bool TryParse(
        OperandFieldKind kind,
        ReadOnlyMemory<char> text,
        out PostbyteOperand operand,
        [NotNullWhen(returnValue: false)] out string? error);

    /// <summary>
    ///  Chooses the length of a parsed field.
    /// </summary>
    /// <param name="operand">The parsed operand.</param>
    /// <param name="known">Whether <paramref name="value"/> is known in this pass.</param>
    /// <param name="value">The expression's value when known.</param>
    /// <param name="fieldAddress">The address of the postbyte.</param>
    /// <returns>The field's length, postbyte included; the widest form when the value is unknown.</returns>
    public abstract int LayoutSize(in PostbyteOperand operand, bool known, long value, int fieldAddress);

    /// <summary>
    ///  Encodes a parsed field at a length chosen by <see cref="LayoutSize"/>.
    /// </summary>
    /// <param name="operand">The parsed operand.</param>
    /// <param name="value">The expression's value, or 0 when there is none.</param>
    /// <param name="fieldAddress">The address of the postbyte.</param>
    /// <param name="destination">The field's bytes, as many as its chosen length.</param>
    /// <param name="error">Receives the diagnostic when the value does not fit.</param>
    /// <returns>Whether the field encoded.</returns>
    public abstract bool TryEncode(
        in PostbyteOperand operand,
        long value,
        int fieldAddress,
        Span<byte> destination,
        [NotNullWhen(returnValue: false)] out string? error);
}
