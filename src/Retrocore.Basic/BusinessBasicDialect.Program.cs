// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Basic;

internal sealed partial class BusinessBasicDialect
{
    // A program ends with a zero length and two more bytes, as NEW leaves it: three zeros.
    private const int ProgramEnd = 3;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   From TXTTAB up to ARYTAB, as flat addresses.
    ///  </para>
    /// </remarks>
    internal override (int Start, int End) ProgramBounds(IBasicMemory memory) =>
        (Pointer(memory, Pointers.ProgramStart), Pointer(memory, Pointers.Arrays));

    /// <inheritdoc/>
    internal override IBasicMemory Text(IBasicMemory memory) => new BusinessBasicMemory(memory);

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The lines and the three zeros after them, without the file's two leading bytes.
    ///  </para>
    /// </remarks>
    internal override byte[] MemoryImage(BasicProgram program, int start) => Image(program)[2..];

    /// <summary>
    ///  Writes a program into memory from TXTTAB and clears as BASIC does when a line is typed: the variables, arrays
    ///  and strings (CLEARL), DATA (RESTORE), ON ERR, ON EOF and RESUME (CLEARONS), and CONT.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   ON KBD's console event, which needs a SOS call, is left as it is; RUN turns it off.
    ///  </para>
    /// </remarks>
    /// <param name="program">The program.</param>
    /// <param name="memory">The memory.</param>
    /// <exception cref="InvalidOperationException">The program does not fit below HIMEM.</exception>
    internal void Write(BasicProgram program, IBasicMemory memory)
    {
        int start = Pointer(memory, Pointers.ProgramStart);
        int top = Pointer(memory, Pointers.MemoryTop);
        byte[] image = MemoryImage(program, start);
        int end = start + image.Length;
        if (start < Banked || end > top)
        {
            throw new InvalidOperationException(
                $"The program needs {image.Length} bytes from {Describe(start)}, but BASIC has room up to {Describe(top)}.");
        }

        BusinessBasicMemory flat = new(memory);
        flat.Write(start - 1, 0);
        for (int index = 0; index < image.Length; index++) { flat.Write(start + index, image[index]); }
        SetPointer(memory, Pointers.Arrays, end);
        SetPointer(memory, Pointers.Variables, end);
        SetPointer(memory, Pointers.FreeStart, end);
        SetPointer(memory, Pointers.StringBottom, top);
        SetPointer(memory, Pointers.DataPointer, start - 1);
        memory.Write(Pointers.ContinueText - XByteOffset, 0);
        for (int index = 0; index < EndOfFileHandlers; index++) { memory.Write(EndOfFilePointers + index, 0); }
        memory.Write(ErrorFlag, 0);
        memory.Write(ErrorPosition, 0);
        memory.Write(ErrorNumber, 0);
        memory.Write(ErrorLine, 0);
        memory.Write(ErrorLine + 1, 0);
    }

    // BASIC's ON ERR flag, the bank of RESUME's place (zero for no error to resume), ERR and ERRLIN, and the ON EOF and
    // ON KBD handlers' table.
    private const int ErrorFlag = ZeroPage + 0x96;
    private const int ErrorPosition = 0x1693;
    private const int ErrorNumber = ZeroPage + 0x95;
    private const int ErrorLine = ZeroPage + 0x90;
    private const int EndOfFilePointers = 0x1E2A;
    private const int EndOfFileHandlers = 0x21;

    // Sets one of BASIC's zero-page pointers to a flat address, with its X-byte.
    private static void SetPointer(IBasicMemory memory, int pointer, int flat)
    {
        (byte xByte, int address) = Split(flat);
        memory.Write(pointer, (byte)address);
        memory.Write(pointer + 1, (byte)(address >> 8));
        memory.Write(pointer - XByteOffset, xByte);
    }

    /// <summary>
    ///  Reads the program in memory, from TXTTAB up to ARYTAB, through BASIC's banked pointers.
    /// </summary>
    /// <param name="memory">The memory.</param>
    /// <returns>The program.</returns>
    /// <exception cref="InvalidDataException">The pointers or a line's length do not describe a program.</exception>
    internal BasicProgram Read(IBasicMemory memory)
    {
        int start = Pointer(memory, Pointers.ProgramStart);
        int end = Pointer(memory, Pointers.Arrays);
        if (start < Banked || end < start + ProgramEnd)
        {
            throw new InvalidDataException(
                $"Business BASIC is not set up: its program is at {Describe(start)} and its arrays at {Describe(end)}.");
        }

        BusinessBasicMemory flat = new(memory);
        byte[] bytes = new byte[end - start];
        for (int index = 0; index < bytes.Length; index++) { bytes[index] = flat.Read(start + index); }
        return Lines(bytes, offset: 0, origin: start);
    }

    /// <summary>
    ///  Reads a program as a SOS BASIC file holds it: two bytes BASIC ignores, then the program as it lies in memory.
    /// </summary>
    /// <param name="bytes">The file.</param>
    /// <returns>The program.</returns>
    /// <exception cref="InvalidDataException">
    ///  A line's length runs past the end, or it does not end in a zero.
    /// </exception>
    internal BasicProgram FromImage(ReadOnlySpan<byte> bytes) => Lines(bytes, offset: 2, origin: null);

    /// <summary>
    ///  Gets a program as a SOS BASIC file holds it: two zero bytes, as SAVE writes them, the lines, and the three
    ///  zeros that end the program.
    /// </summary>
    /// <param name="program">The program.</param>
    /// <returns>The file.</returns>
    /// <exception cref="InvalidOperationException">A line is longer than a length byte can say.</exception>
    internal static byte[] Image(BasicProgram program)
    {
        List<byte> bytes = [0, 0];
        foreach (BasicLine line in program.Lines)
        {
            int length = line.Tokens.Length + Instance.LineOverhead;
            if (length > 0xFF)
            {
                throw new InvalidOperationException($"Line {line.Number} is {length} bytes; a line holds at most 255.");
            }

            bytes.Add((byte)length);
            bytes.Add((byte)line.Number);
            bytes.Add((byte)(line.Number >> 8));
            bytes.AddRange(line.Tokens.Span);
            bytes.Add(0);
        }

        bytes.AddRange(new byte[ProgramEnd]);
        return [.. bytes];
    }

    /// <summary>
    ///  Gives a flat address as an X-byte and an address, or the address alone when it is not banked.
    /// </summary>
    /// <param name="flat">The flat address.</param>
    /// <returns>Such as <c>x82:$1234</c>.</returns>
    internal static string Describe(int flat)
    {
        (byte xByte, int address) = Split(flat);
        return xByte == 0 ? $"${address:X4}" : $"x{xByte:X2}:${address:X4}";
    }

    // Reads lines from an offset up to a zero length; a line's place for messages is the flat address it was read
    // from, when there is one.
    private BasicProgram Lines(ReadOnlySpan<byte> bytes, int offset, int? origin)
    {
        List<BasicLine> lines = [];
        int at = offset;
        while (at < bytes.Length && bytes[at] != 0)
        {
            int length = bytes[at];
            if (length < LineOverhead || at + length > bytes.Length || bytes[at + length - 1] != 0)
            {
                string place = origin is int start ? $"at {Describe(start + at)}" : $"at offset {at}";
                throw new InvalidDataException($"The line {place} is not a Business BASIC line.");
            }

            lines.Add(new(bytes[at + 1] | (bytes[at + 2] << 8), bytes.Slice(at + LineHeader, length - LineOverhead).ToArray()));
            at += length;
        }

        if (at >= bytes.Length)
        {
            throw new InvalidDataException("The program ends without the zero length that ends it.");
        }

        return new(this, lines);
    }
}
