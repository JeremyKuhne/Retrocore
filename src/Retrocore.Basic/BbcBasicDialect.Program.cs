// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Basic;

internal sealed partial class BbcBasicDialect
{
    /// <summary>
    ///  LOMEM: the start of the variables' heap.
    /// </summary>
    internal const int Lomem = 0x00;

    /// <summary>
    ///  The top of the heap: the first free byte above the variables.
    /// </summary>
    internal const int Heap = 0x02;

    /// <summary>
    ///  BASIC's stack pointer, which grows down from HIMEM.
    /// </summary>
    internal const int BasicStack = 0x04;

    /// <summary>
    ///  HIMEM.
    /// </summary>
    internal const int Himem = 0x06;

    /// <summary>
    ///  PTRA's offset: where in the text at PTRA BASIC reads.
    /// </summary>
    internal const int PtrAOffset = 0x0A;

    /// <summary>
    ///  PTRA: the base of the text being run, a line of the program or the line typed.
    /// </summary>
    internal const int PtrA = 0x0B;

    /// <summary>
    ///  TOP: the byte after the program's end marker.
    /// </summary>
    internal const int Top = 0x12;

    /// <summary>
    ///  ON ERROR's text: the default handler in the ROM, or a program's.
    /// </summary>
    internal const int OnError = 0x16;

    /// <summary>
    ///  PAGE's high byte; its low byte is always zero.
    /// </summary>
    internal const int PageHigh = 0x18;

    /// <summary>
    ///  DATA's pointer.
    /// </summary>
    internal const int DataPointerAddress = 0x1C;

    /// <summary>
    ///  The number of REPEATs open.
    /// </summary>
    internal const int RepeatLevel = 0x24;

    /// <summary>
    ///  The number of GOSUBs open.
    /// </summary>
    internal const int GosubLevel = 0x25;

    /// <summary>
    ///  The bytes the FOR stack holds: 15 for each FOR open.
    /// </summary>
    internal const int ForLevel = 0x26;

    /// <summary>
    ///  The resident integers, @% then A% to Z%, four bytes each.
    /// </summary>
    internal const int ResidentIntegers = 0x0400;

    /// <summary>
    ///  The base the heads of the variable lists are indexed from: the names starting with C are listed from
    ///  ListHeads + 2 * C.
    /// </summary>
    internal const int ListHeads = 0x0400;

    /// <summary>
    ///  The first variable list's head, @'s, which the variable lists, then the PROC and FN lists, follow to &amp;04FF.
    /// </summary>
    internal const int VariableLists = 0x0480;

    /// <summary>
    ///  The FOR stack.
    /// </summary>
    internal const int ForStack = 0x0500;

    /// <summary>
    ///  The GOSUB stack: the low bytes of the places RETURN goes back to.
    /// </summary>
    internal const int GosubStackLow = 0x05CC;

    /// <summary>
    ///  The GOSUB stack: the high bytes.
    /// </summary>
    internal const int GosubStackHigh = 0x05E6;

    /// <summary>
    ///  The size of a FOR entry.
    /// </summary>
    internal const int ForEntrySize = 15;

    /// <summary>
    ///  The page of the line buffer, where PTRA is while a typed line runs.
    /// </summary>
    internal const int LineBufferPage = 0x07;

    // The end of the program: a line number whose high byte has bit 7 set.
    private const byte EndMarker = 0xFF;

    /// <summary>
    ///  Gets PAGE, where the program starts.
    /// </summary>
    /// <param name="memory">The memory.</param>
    /// <returns>The address of the carriage return before the first line.</returns>
    internal static int Page(IBasicMemory memory) => memory.Read(PageHigh) << 8;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   BASIC is in direct mode while PTRA is in the line buffer, page seven.
    ///  </para>
    /// </remarks>
    public override bool InDirectMode(IBasicMemory memory) => memory.Read(PtrA + 1) == LineBufferPage;

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   From the first line's number, after PAGE's carriage return, to TOP.
    ///  </para>
    /// </remarks>
    internal override (int Start, int End) ProgramBounds(IBasicMemory memory) =>
        (Page(memory) + 1, BasicProgram.Word(memory, Top));

    /// <inheritdoc/>
    internal override int WriteLimit(IBasicMemory memory) => BasicProgram.Word(memory, Himem);

    /// <inheritdoc/>
    internal override int VariableLimit(IBasicMemory memory) => BasicProgram.Word(memory, BasicStack);

    /// <inheritdoc/>
    internal override int StringFloorOf(IBasicMemory memory) => BasicProgram.Word(memory, Heap);

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   The lines without PAGE's carriage return, which <see cref="ProgramBounds"/> starts after.
    ///  </para>
    /// </remarks>
    internal override byte[] MemoryImage(BasicProgram program, int start) => Image(program)[1..];

    /// <inheritdoc/>
    /// <remarks>
    ///  <para>
    ///   As the ROM's <c>CLEAR_VARIABLES</c> does: LOMEM and the heap's top go to TOP, the stacks are emptied, DATA
    ///   goes back to PAGE, and the variable, PROC and FN lists are emptied. The resident integers are kept.
    ///  </para>
    /// </remarks>
    internal override void Clear(IBasicMemory memory)
    {
        int top = BasicProgram.Word(memory, Top);
        BasicProgram.WriteWord(memory, Lomem, top);
        BasicProgram.WriteWord(memory, Heap, top);
        BasicProgram.WriteWord(memory, BasicStack, BasicProgram.Word(memory, Himem));
        memory.Write(RepeatLevel, 0);
        memory.Write(ForLevel, 0);
        memory.Write(GosubLevel, 0);
        memory.Write(DataPointerAddress, 0);
        memory.Write(DataPointerAddress + 1, memory.Read(PageHigh));
        for (int at = VariableLists; at < VariableLists + 0x80; at++) { memory.Write(at, 0); }
    }

    /// <summary>
    ///  Gets the number of the line an address is in: from its number to the carriage return that ends it.
    /// </summary>
    /// <param name="memory">The memory.</param>
    /// <param name="address">The address.</param>
    /// <returns>The line's number, or null when the address is in no line of the program.</returns>
    internal static int? LineAt(IBasicMemory memory, int address)
    {
        int at = Page(memory);
        for (int count = 0; count < 0x8000 && at < 0x10000; count++)
        {
            int high = memory.Read(at + 1);
            int length = memory.Read(at + 3);
            if ((high & 0x80) != 0 || length < 4) { return null; }
            if (address > at && address <= at + length) { return (high << 8) | memory.Read(at + 2); }
            at += length;
        }

        return null;
    }

    /// <summary>
    ///  Reads the program in memory, from PAGE to the end marker.
    /// </summary>
    /// <param name="memory">The memory.</param>
    /// <returns>The program.</returns>
    /// <exception cref="InvalidDataException">The memory at PAGE is not a program.</exception>
    internal BasicProgram Read(IBasicMemory memory)
    {
        int page = Page(memory);
        int top = BasicProgram.Word(memory, Top);
        if (page == 0 || top <= page || top - page > 0x8000)
        {
            throw new InvalidDataException($"BBC BASIC is not set up: PAGE is &{page:X4} and TOP &{top:X4}.");
        }

        byte[] bytes = new byte[top - page];
        for (int index = 0; index < bytes.Length; index++) { bytes[index] = memory.Read(page + index); }
        return Lines(bytes, page);
    }

    /// <summary>
    ///  Reads a program as a BASIC file holds it: what SAVE wrote, the memory from PAGE to TOP.
    /// </summary>
    /// <param name="bytes">The file.</param>
    /// <returns>The program.</returns>
    /// <exception cref="InvalidDataException">
    ///  The bytes are not a program, as BASIC's "Bad program" would say.
    /// </exception>
    internal BasicProgram FromImage(ReadOnlySpan<byte> bytes) => Lines(bytes, origin: null);

    /// <summary>
    ///  Gets a program as SAVE writes it: a carriage return, each line's number, length, text and carriage return,
    ///  and the end marker.
    /// </summary>
    /// <param name="program">The program.</param>
    /// <returns>The bytes.</returns>
    /// <exception cref="InvalidOperationException">A line is longer than a length byte can say.</exception>
    internal static byte[] Image(BasicProgram program)
    {
        List<byte> bytes = [CarriageReturn];
        foreach (BasicLine line in program.Lines)
        {
            int length = line.Tokens.Length + Instance.LineOverhead;
            if (length > 0xFF)
            {
                throw new InvalidOperationException($"Line {line.Number} is {length} bytes; a line holds at most 255.");
            }

            bytes.Add((byte)(line.Number >> 8));
            bytes.Add((byte)line.Number);
            bytes.Add((byte)length);
            bytes.AddRange(line.Tokens.Span);
            bytes.Add(CarriageReturn);
        }

        bytes.Add(EndMarker);
        return [.. bytes];
    }

    /// <summary>
    ///  Writes a program into memory at PAGE, sets TOP, and clears as BASIC does when a line is typed.
    /// </summary>
    /// <param name="program">The program.</param>
    /// <param name="memory">The memory.</param>
    /// <exception cref="InvalidOperationException">The program does not fit below HIMEM.</exception>
    internal void Write(BasicProgram program, IBasicMemory memory)
    {
        int page = Page(memory);
        byte[] image = Image(program);
        int end = page + image.Length;
        int limit = WriteLimit(memory);
        if (page == 0 || end > limit)
        {
            throw new InvalidOperationException(
                $"The program needs {image.Length} bytes from PAGE, &{page:X4}, but BASIC has room up to HIMEM, "
                    + $"&{limit:X4}.");
        }

        for (int index = 0; index < image.Length; index++) { memory.Write(page + index, image[index]); }
        BasicProgram.WriteWord(memory, Top, end);
        Clear(memory);
    }

    // Reads lines from the carriage return at the start up to the end marker; a line's place for messages is its
    // address when it was read from memory.
    private BasicProgram Lines(ReadOnlySpan<byte> bytes, int? origin)
    {
        string Place(int at) => origin is int page ? $"at &{page + at:X4}" : $"at offset {at}";
        if (bytes.Length < 2 || bytes[0] != CarriageReturn)
        {
            throw new InvalidDataException("A BBC BASIC program starts with a carriage return.");
        }

        List<BasicLine> lines = [];
        int at = 0;
        while (true)
        {
            if (at + 1 >= bytes.Length)
            {
                throw new InvalidDataException("The program ends without its end marker.");
            }

            if ((bytes[at + 1] & 0x80) != 0) { break; }
            if (at + 3 >= bytes.Length)
            {
                throw new InvalidDataException($"The line {Place(at + 1)} runs past the end.");
            }

            int length = bytes[at + 3];
            if (length < LineOverhead || at + length >= bytes.Length || bytes[at + length] != CarriageReturn)
            {
                throw new InvalidDataException($"The line {Place(at + 1)} is not a BBC BASIC line: Bad program.");
            }

            int number = (bytes[at + 1] << 8) | bytes[at + 2];
            lines.Add(new(number, bytes.Slice(at + 4, length - LineOverhead).ToArray()));
            at += length;
        }

        return new(this, lines);
    }
}
