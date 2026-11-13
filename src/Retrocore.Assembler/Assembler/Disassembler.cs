// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Cpu.M6502;
using Retrocore.Isa;
using System.Buffers;

namespace Retrocore.Assembler;

/// <summary>
///  Decodes canonical CPU opcode spans and analyzes images without a second instruction table.
/// </summary>
public static partial class Disassembler
{
    /// <summary>
    ///  Bounded scratch storage for the longest supported mnemonic and formatted operands.
    /// </summary>
    internal const int InstructionTextBufferSize = 32;

    /// <summary>
    ///  Decodes one complete instruction without copying or allocating an input buffer.
    /// </summary>
    /// <param name="bytes">Bytes starting at the instruction.</param>
    /// <param name="address">The instruction address; relative targets wrap at 16 bits.</param>
    /// <param name="variant">The CPU encoding set.</param>
    /// <param name="instruction">The decoded value, or default when more bytes are required.</param>
    /// <returns>Whether enough bytes were supplied for a complete instruction.</returns>
    public static bool TryDecode(
        ReadOnlySpan<byte> bytes,
        ushort address,
        ProcessorVariant variant,
        out DisassembledInstruction instruction) =>
            TryDecode(bytes, address, M6502Isa.Get(variant), out instruction);

    /// <summary>
    ///  Decodes one complete instruction of any instruction set without copying or allocating an input buffer.
    /// </summary>
    /// <param name="bytes">Bytes starting at the instruction.</param>
    /// <param name="address">The instruction address; relative targets wrap at 16 bits.</param>
    /// <param name="set">The instruction set.</param>
    /// <param name="instruction">The decoded value, or default when more bytes are required.</param>
    /// <returns>Whether enough bytes were supplied for a complete instruction.</returns>
    public static bool TryDecode(
        ReadOnlySpan<byte> bytes,
        ushort address,
        InstructionSet set,
        out DisassembledInstruction instruction)
    {
        instruction = default;
        if (!set.TryDecode(bytes, out int encoding, out int size) || bytes.Length < size) { return false; }

        instruction = new(address, set.Handle, (ushort)encoding, Pack(bytes, size, out byte fifthByte), (byte)size, fifthByte);
        return true;
    }

    // Packs the original bytes into the value so the decoded instruction never borrows the caller's span.
    private static uint Pack(ReadOnlySpan<byte> bytes, int size, out byte fifthByte)
    {
        uint value = bytes[0];
        int limit = Math.Min(size, sizeof(uint));
        for (int index = 1; index < limit; index++)
        {
            value |= (uint)bytes[index] << (index * InstructionEncoding.BitsPerByte);
        }

        fifthByte = size > sizeof(uint) ? bytes[sizeof(uint)] : (byte)0;
        return value;
    }

    /// <summary>
    ///  Decodes complete instructions into caller storage, reporting truncation and capacity explicitly.
    /// </summary>
    /// <param name="bytes">The encoded stream.</param>
    /// <param name="address">The first address; subsequent addresses wrap at 16 bits.</param>
    /// <param name="variant">The CPU encoding set.</param>
    /// <param name="destination">Storage for decoded values.</param>
    /// <param name="bytesRead">Bytes consumed by complete instructions.</param>
    /// <param name="instructionsWritten">The number of destination entries written.</param>
    /// <returns>Done, NeedMoreData for a truncated tail, or DestinationTooSmall.</returns>
    public static OperationStatus Decode(
        ReadOnlySpan<byte> bytes,
        ushort address,
        ProcessorVariant variant,
        Span<DisassembledInstruction> destination,
        out int bytesRead,
        out int instructionsWritten) =>
            Decode(bytes, address, M6502Isa.Get(variant), destination, out bytesRead, out instructionsWritten);

    /// <summary>
    ///  Decodes consecutive instructions of any CPU until the input or destination ends.
    /// </summary>
    /// <param name="bytes">The input bytes.</param>
    /// <param name="address">The address of the first byte.</param>
    /// <param name="set">The CPU's instruction set.</param>
    /// <param name="destination">Receives the instructions.</param>
    /// <param name="bytesRead">The bytes consumed.</param>
    /// <param name="instructionsWritten">The instructions written.</param>
    /// <returns>
    ///  <see cref="OperationStatus.Done"/>, <see cref="OperationStatus.DestinationTooSmall"/>, or
    ///  <see cref="OperationStatus.NeedMoreData"/> at an undecodable or truncated instruction.
    /// </returns>
    public static OperationStatus Decode(
        ReadOnlySpan<byte> bytes,
        ushort address,
        InstructionSet set,
        Span<DisassembledInstruction> destination,
        out int bytesRead,
        out int instructionsWritten)
    {
        ArgumentNullException.ThrowIfNull(set);

        // The handle and first-byte map are fixed for the whole stream, so they are read once.
        ushort handle = set.Handle;
        ReadOnlySpan<uint> map = set.FirstByteMap;
        bytesRead = 0;
        instructionsWritten = 0;
        while (bytesRead < bytes.Length)
        {
            if (instructionsWritten == destination.Length) { return OperationStatus.DestinationTooSmall; }
            ReadOnlySpan<byte> rest = bytes[bytesRead..];
            uint entry = map[rest[0]];
            int encoding;
            int size;
            if (entry != InstructionSet.NoSingleByteOpcode)
            {
                encoding = (int)(entry & ushort.MaxValue);
                size = (int)(entry >> 16);
            }
            else if (!set.TryDecode(rest, out encoding, out size))
            {
                return OperationStatus.NeedMoreData;
            }

            if (rest.Length < size) { return OperationStatus.NeedMoreData; }
            destination[instructionsWritten++] = new(
                unchecked((ushort)(address + bytesRead)),
                handle,
                (ushort)encoding,
                Pack(rest, size, out byte fifthByte),
                (byte)size,
                fifthByte);

            bytesRead += size;
        }

        return OperationStatus.Done;
    }

    /// <summary>
    ///  Formats a complete instruction without modifying a short destination.
    /// </summary>
    /// <param name="instruction">The decoded value.</param>
    /// <param name="destination">The text destination.</param>
    /// <param name="charsWritten">The complete length, or zero.</param>
    /// <returns>Whether the complete text fit.</returns>
    internal static bool TryFormat(in DisassembledInstruction instruction, Span<char> destination, out int charsWritten)
    {
        if (instruction.Size == 0) { throw new InvalidOperationException("The instruction has not been decoded."); }
        // Scratch output keeps a short destination untouched; no partial instruction text escapes.
        Span<char> buffer = stackalloc char[InstructionTextBufferSize];
        string mnemonic = instruction.Mnemonic;
        mnemonic.CopyTo(buffer);
        int length = mnemonic.Length;
        // The form's first pattern is its canonical syntax. Each hole shows the next field, except that a single
        // hole shows all of a form's fields, comma-separated.
        OperandForm form = instruction.Form;
        string pattern = form.Patterns[0];
        if (pattern.Length != 0)
        {
            buffer[length++] = ' ';
            ReadOnlySpan<int> holes = form.CanonicalHoles;
            bool list = holes.Length == 1;
            int field = 0;
            int start = 0;
            foreach (int hole in holes)
            {
                pattern.AsSpan(start, hole - start).CopyTo(buffer[length..]);
                length += hole - start;
                do
                {
                    if (list && field != 0)
                    {
                        buffer[length++] = ',';
                        buffer[length++] = ' ';
                    }

                    AppendField(in instruction, buffer, ref length, form.Field(field), field);
                    field++;
                }
                while (list && field < form.FieldCount);

                start = hole + 2;
            }

            pattern.AsSpan(start).CopyTo(buffer[length..]);
            length += pattern.Length - start;
        }

        charsWritten = destination.Length >= length ? length : 0;
        if (charsWritten == 0) { return false; }
        buffer[..length].CopyTo(destination);
        return true;
    }

    // Relative fields show their target address, a displacement its sign and a bit number one digit.
    private static void AppendField(
        in DisassembledInstruction instruction,
        Span<char> buffer,
        ref int length,
        OperandFieldKind kind,
        int fieldIndex)
    {
        if (OperandForm.IsPostbyte(kind))
        {
            // The instruction set's codec formats its postbyte fields, such as the MC6809's [5,X] or D,X.
            Span<byte> bytes = stackalloc byte[DisassembledInstruction.MaximumPostbyteField];
            instruction.Postbytes.Format(
                kind,
                instruction.PostbyteBytes(bytes),
                unchecked((ushort)(instruction.Address + instruction.Size)),
                buffer,
                ref length);

            return;
        }

        ushort value = instruction.Field(fieldIndex);
        switch (kind)
        {
            case OperandFieldKind.Byte or OperandFieldKind.Restart:
                AppendHex(buffer, ref length, value, 2);
                break;
            case OperandFieldKind.Displacement8:
                int signed = (short)value;
                buffer[length++] = signed < 0 ? '-' : '+';
                AppendHex(buffer, ref length, (ushort)Math.Abs(signed), 2);
                break;
            case OperandFieldKind.BitNumber:
                buffer[length++] = (char)('0' + value);
                break;
            case OperandFieldKind.RestartNumber:
                // Intel's RST names the restart by number; the field's value is its address.
                buffer[length++] = (char)('0' + (value >> 3));
                break;
            default:
                AppendHex(buffer, ref length, value, 4);
                break;
        }
    }

    /// <summary>
    ///  Appends a fixed-width native hexadecimal operand to an already bounded formatting buffer.
    /// </summary>
    /// <param name="buffer">The instruction scratch buffer.</param>
    /// <param name="length">The next write position, advanced past the complete number.</param>
    /// <param name="value">The address or byte value.</param>
    /// <param name="digits">Two for byte operands or four for addresses.</param>
    private static void AppendHex(Span<char> buffer, ref int length, ushort value, int digits)
    {
        const string HexDigits = "0123456789ABCDEF";
        buffer[length++] = '$';
        for (int shift = (digits - 1) * 4; shift >= 0; shift -= 4)
        {
            buffer[length++] = HexDigits[(value >> shift) & 15];
        }
    }
}
