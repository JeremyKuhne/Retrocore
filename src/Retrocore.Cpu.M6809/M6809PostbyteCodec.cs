// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Isa;

namespace Retrocore.Cpu.M6809;

/// <summary>
///  The MC6809's postbyte fields: indexed addressing, the <c>TFR</c> and <c>EXG</c> register pair, and the
///  <c>PSHS</c>/<c>PULS</c> and <c>PSHU</c>/<c>PULU</c> register lists.
/// </summary>
internal sealed class M6809PostbyteCodec : PostbyteCodec
{
    // PostbyteOperand.Detail: the indexed kind in bits 0-1, indirection in bit 2, the forced width in bits 4-5.
    private const int IndirectDetail = 0x04;
    private const int WidthShift = 4;

    private const string ByteRange = "Operand is outside the byte range; use < or > for extraction.";
    private const string WordRange = "Operand is outside the 16-bit address range.";

    private M6809PostbyteCodec()
    {
    }

    /// <summary>
    ///  Gets the one instance; the codec holds no state.
    /// </summary>
    internal static M6809PostbyteCodec Instance { get; } = new();

    /// <inheritdoc/>
    public override bool TryGetSize(OperandFieldKind kind, ReadOnlySpan<byte> operand, out int size)
    {
        if (operand.IsEmpty)
        {
            size = 0;
            return false;
        }

        switch (kind)
        {
            case OperandFieldKind.IndexedPostbyte:
                return M6809Postbyte.TryGetIndexedSize(operand[0], out size);
            case OperandFieldKind.RegisterPair:
                size = 1;
                return M6809Postbyte.IsValidRegisterPair(operand[0]);
            default:
                size = 1;
                return true;
        }
    }

    /// <inheritdoc/>
    public override ushort Decode(OperandFieldKind kind, ReadOnlySpan<byte> operand, ushort nextAddress) =>
        kind == OperandFieldKind.IndexedPostbyte
            ? M6809Postbyte.DecodeIndexedValue(operand[0], ByteAt(operand, 1), ByteAt(operand, 2), nextAddress)
            : operand[0];

    /// <inheritdoc/>
    public override PostbyteReference GetReference(OperandFieldKind kind, ReadOnlySpan<byte> operand)
    {
        if (kind != OperandFieldKind.IndexedPostbyte) { return PostbyteReference.None; }
        byte postbyte = operand[0];
        if (M6809Postbyte.IsExtendedIndirect(postbyte)) { return PostbyteReference.Pointer; }
        if (!M6809Postbyte.IsPcRelative(postbyte)) { return PostbyteReference.None; }
        return M6809Postbyte.IsIndirect(postbyte) ? PostbyteReference.Pointer : PostbyteReference.Target;
    }

    /// <inheritdoc/>
    public override void Format(
        OperandFieldKind kind,
        ReadOnlySpan<byte> operand,
        ushort nextAddress,
        Span<char> buffer,
        ref int length)
    {
        switch (kind)
        {
            case OperandFieldKind.IndexedPostbyte:
                M6809Postbyte.FormatIndexed(operand[0], ByteAt(operand, 1), ByteAt(operand, 2), nextAddress, buffer, ref length);
                return;
            case OperandFieldKind.RegisterPair:
                M6809Postbyte.FormatRegisterPair(operand[0], buffer, ref length);
                return;
            default:
                M6809Postbyte.FormatStackMask(operand[0], kind == OperandFieldKind.SystemStackMask, buffer, ref length);
                return;
        }
    }

    /// <inheritdoc/>
    public override bool HasSyntax(OperandFieldKind kind, ReadOnlySpan<char> text) =>
        kind == OperandFieldKind.IndexedPostbyte && M6809Postbyte.HasIndexedSyntax(text);

    /// <inheritdoc/>
    public override bool IsRegisterToken(ReadOnlySpan<char> text, int start, int length) =>
        M6809Postbyte.IsIndexedRegisterToken(text, start, length);

    /// <inheritdoc/>
    public override bool TryParse(
        OperandFieldKind kind,
        ReadOnlyMemory<char> text,
        out PostbyteOperand operand,
        [NotNullWhen(returnValue: false)] out string? error)
    {
        operand = default;
        switch (kind)
        {
            case OperandFieldKind.IndexedPostbyte:
                if (!M6809Postbyte.TryParseIndexed(text, out M6809IndexedOperand indexed, out error))
                {
                    error ??= "Invalid indexed operand.";
                    return false;
                }

                int detail = (int)indexed.Kind | ((int)indexed.Width << WidthShift);
                if (indexed.Indirect) { detail |= IndirectDetail; }
                operand = new()
                {
                    Kind = kind,
                    Code = indexed.Code,
                    Detail = (byte)detail,
                    Expression = indexed.Kind == M6809IndexedKind.Fixed ? default : indexed.Expression
                };

                return true;
            case OperandFieldKind.RegisterPair:
                if (!M6809Postbyte.TryEncodeRegisterPair(text.Span, out byte pair, out error))
                {
                    error ??= "Invalid register pair.";
                    return false;
                }

                operand = new() { Kind = kind, Code = pair };
                return true;
            default:
                if (!M6809Postbyte.TryEncodeStackMask(
                    text,
                    kind == OperandFieldKind.SystemStackMask,
                    out byte mask,
                    out ReadOnlyMemory<char> immediate,
                    out error))
                {
                    error ??= "Invalid stack register list.";
                    return false;
                }

                operand = new() { Kind = kind, Code = mask, Expression = immediate };
                return true;
        }
    }

    /// <inheritdoc/>
    public override int LayoutSize(in PostbyteOperand operand, bool known, long value, int fieldAddress)
    {
        if (operand.Kind != OperandFieldKind.IndexedPostbyte) { return 1; }
        M6809OffsetWidth width = Width(in operand);
        switch (IndexedKind(in operand))
        {
            case M6809IndexedKind.Fixed:
                return 1;
            case M6809IndexedKind.ExtendedIndirect:
                return 3;
            case M6809IndexedKind.ProgramCounterRelative:
                if (width == M6809OffsetWidth.EightBit) { return 2; }
                if (width == M6809OffsetWidth.SixteenBit || !known) { return 3; }
                int displacement = SignedRelativeDelta(value, (fieldAddress + 2) & ushort.MaxValue);
                return displacement is >= sbyte.MinValue and <= sbyte.MaxValue ? 2 : 3;
            default:
                return width switch
                {
                    M6809OffsetWidth.FiveBit => 1,
                    M6809OffsetWidth.EightBit => 2,
                    M6809OffsetWidth.SixteenBit => 3,
                    _ when !known => 3,

                    // A zero offset is no offset, ,R or [,R], as Motorola's assembler and lwasm encode it.
                    _ when value == 0 => 1,
                    _ when !IsIndirect(in operand) && value is >= -16 and <= 15 => 1,
                    _ when value is >= sbyte.MinValue and <= sbyte.MaxValue => 2,
                    _ => 3
                };
        }
    }

    /// <inheritdoc/>
    public override bool TryEncode(
        in PostbyteOperand operand,
        long value,
        int fieldAddress,
        Span<byte> destination,
        [NotNullWhen(returnValue: false)] out string? error)
    {
        error = null;
        if (operand.Kind != OperandFieldKind.IndexedPostbyte)
        {
            if (operand.Expression.IsEmpty)
            {
                destination[0] = operand.Code;
                return true;
            }

            if (value is < 0 or > byte.MaxValue)
            {
                error = ByteRange;
                return false;
            }

            destination[0] = (byte)value;
            return true;
        }

        M6809IndexedKind kind = IndexedKind(in operand);
        if (kind == M6809IndexedKind.Fixed)
        {
            destination[0] = operand.Code;
            return true;
        }

        if (kind == M6809IndexedKind.ExtendedIndirect)
        {
            if (value is < 0 or > ushort.MaxValue)
            {
                error = WordRange;
                return false;
            }

            destination[0] = 0x9F;
            destination[1] = (byte)(value >> 8);
            destination[2] = (byte)value;
            return true;
        }

        byte indirectBit = IsIndirect(in operand) ? (byte)0x10 : (byte)0;
        if (kind == M6809IndexedKind.ProgramCounterRelative)
        {
            if (value is < 0 or > ushort.MaxValue)
            {
                error = WordRange;
                return false;
            }

            int next = (fieldAddress + destination.Length) & ushort.MaxValue;
            if (destination.Length == 2)
            {
                int displacement = SignedRelativeDelta(value, next);
                if (displacement is < sbyte.MinValue or > sbyte.MaxValue)
                {
                    error = "Branch target is outside the signed 8-bit range.";
                    return false;
                }

                destination[0] = (byte)(0x8C | indirectBit);
                destination[1] = unchecked((byte)displacement);
            }
            else
            {
                int relative16 = (int)((value - next) & ushort.MaxValue);
                destination[0] = (byte)(0x8D | indirectBit);
                destination[1] = (byte)(relative16 >> 8);
                destination[2] = (byte)relative16;
            }

            return true;
        }

        byte registerBits = (byte)(operand.Code << 5);
        switch (destination.Length)
        {
            case 1:
                // An unforced zero offset is ,R or [,R]; << keeps the 5-bit form.
                if (value == 0 && Width(in operand) == M6809OffsetWidth.Automatic)
                {
                    destination[0] = (byte)(0x84 | registerBits | indirectBit);
                    return true;
                }

                if (value is < -16 or > 15 || indirectBit != 0)
                {
                    error = "Indexed offset is outside the signed 5-bit range (-16 to 15).";
                    return false;
                }

                destination[0] = (byte)(registerBits | ((int)value & 0x1F));
                return true;
            case 2:
                if (value is < sbyte.MinValue or > sbyte.MaxValue)
                {
                    error = "Indexed offset is outside the signed 8-bit range.";
                    return false;
                }

                destination[0] = (byte)(0x88 | registerBits | indirectBit);
                destination[1] = unchecked((byte)value);
                return true;
            default:
                if (value is < short.MinValue or > ushort.MaxValue)
                {
                    error = "Indexed offset is outside the 16-bit range.";
                    return false;
                }

                ushort word = unchecked((ushort)value);
                destination[0] = (byte)(0x89 | registerBits | indirectBit);
                destination[1] = (byte)(word >> 8);
                destination[2] = (byte)word;
                return true;
        }
    }

    private static M6809IndexedKind IndexedKind(in PostbyteOperand operand) => (M6809IndexedKind)(operand.Detail & 0x03);

    private static bool IsIndirect(in PostbyteOperand operand) => (operand.Detail & IndirectDetail) != 0;

    private static M6809OffsetWidth Width(in PostbyteOperand operand) =>
        (M6809OffsetWidth)((operand.Detail >> WidthShift) & 0x03);

    private static byte ByteAt(ReadOnlySpan<byte> operand, int index) => index < operand.Length ? operand[index] : (byte)0;

    // The signed distance from the next instruction to a target, wrapping across $FFFF/$0000.
    private static int SignedRelativeDelta(long target, int next)
    {
        if (target is < 0 or > ushort.MaxValue)
        {
            return int.MaxValue;
        }

        int displacement = (int)((target - next + 0x10000) & ushort.MaxValue);
        return displacement > short.MaxValue ? displacement - 0x10000 : displacement;
    }
}
