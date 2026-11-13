// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Touki.Text;

namespace Retrocore.Basic;

/// <summary>
///  A BASIC program: its lines in order, as the interpreter stores them.
/// </summary>
/// <remarks>
///  <para>
///   In the Microsoft BASICs' memory and tokenized files each line is a two-byte link to the next line, a two-byte line
///   number, the tokenized statements and a zero byte; a zero link ends the program. Both words are low byte first.
///   Integer BASIC's lines are a length byte, the number, the tokens and $01 (<see cref="BasicDialect.Integer"/>);
///   Business BASIC's are a length byte, the number, the tokens and a zero (<see cref="BasicDialect.BusinessBasic"/>).
///  </para>
/// </remarks>
public sealed partial class BasicProgram
{
    private const int LineOverhead = 5;
    private const int MaximumLines = 0x10000 / 4;

    /// <summary>
    ///  Creates a program.
    /// </summary>
    /// <param name="dialect">Its dialect.</param>
    /// <param name="lines">Its lines, in line number order.</param>
    public BasicProgram(BasicDialect dialect, IEnumerable<BasicLine> lines)
    {
        ArgumentNullException.ThrowIfNull(dialect);
        ArgumentNullException.ThrowIfNull(lines);
        Dialect = dialect;
        Lines = [.. lines];
    }

    /// <summary>
    ///  Gets the program's dialect.
    /// </summary>
    public BasicDialect Dialect { get; }

    /// <summary>
    ///  Gets the program's lines.
    /// </summary>
    public IReadOnlyList<BasicLine> Lines { get; }

    /// <summary>
    ///  Reads a tokenized program, as a file holds it.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   Links are not trusted: lines are read up to each zero byte, and the program ends at a zero link. A Level II
    ///   Disk BASIC file's leading $FF is skipped when the links show it is not part of the first line.
    ///  </para>
    /// </remarks>
    /// <param name="dialect">The dialect.</param>
    /// <param name="bytes">The bytes.</param>
    /// <returns>The program.</returns>
    /// <exception cref="InvalidDataException">The bytes end inside a line, or before the zero link.</exception>
    public static BasicProgram FromImage(BasicDialect dialect, ReadOnlySpan<byte> bytes)
    {
        ArgumentNullException.ThrowIfNull(dialect);
        if (dialect is IntegerBasicDialect integer) { return integer.FromImage(bytes); }
        if (dialect is BusinessBasicDialect business) { return business.FromImage(bytes); }
        if (dialect == BasicDialect.Level2 && bytes.Length > 0 && bytes[0] == 0xFF)
        {
            // A program at $42E9 can begin with $FF too, so the links decide.
            BasicProgram? plain = ParseImage(dialect, bytes, out bool plainLinked);
            if (plain is not null && plainLinked) { return plain; }
            if (ParseImage(dialect, bytes[1..], out _) is { } file) { return file; }
            if (plain is not null) { return plain; }
        }

        return ParseImage(dialect, bytes, out _)
            ?? throw new InvalidDataException("The program ends inside a line or before the zero link that ends it.");
    }

    /// <summary>
    ///  Reads the program in a machine's memory, from the interpreter's program pointer.
    /// </summary>
    /// <param name="dialect">The interpreter.</param>
    /// <param name="memory">The memory.</param>
    /// <returns>The program.</returns>
    /// <exception cref="InvalidDataException">
    ///  The pointers do not describe a program, or a line's link points outside it.
    /// </exception>
    public static BasicProgram Read(BasicDialect dialect, IBasicMemory memory)
    {
        ArgumentNullException.ThrowIfNull(dialect);
        ArgumentNullException.ThrowIfNull(memory);
        if (dialect is IntegerBasicDialect integer) { return integer.Read(memory); }
        if (dialect is BusinessBasicDialect business) { return business.Read(memory); }
        int start = Word(memory, dialect.Pointers.ProgramStart);
        int end = Word(memory, dialect.Pointers.Variables);
        if (start == 0 || end < start + 2)
        {
            throw new InvalidDataException($"BASIC is not set up: its program is at ${start:X4} and its variables at ${end:X4}.");
        }

        List<BasicLine> lines = [];
        int address = start;
        while (true)
        {
            int link = Word(memory, address);
            if (link == 0) { break; }
            if (link < address + LineOverhead || link > end || lines.Count >= MaximumLines)
            {
                throw new InvalidDataException(
                    $"The line at ${address:X4} links to ${link:X4}, outside the program (${start:X4}-${end - 1:X4}).");
            }

            byte[] tokens = new byte[link - address - LineOverhead];
            for (int index = 0; index < tokens.Length; index++) { tokens[index] = memory.Read(address + 4 + index); }
            if (memory.Read(link - 1) != 0 || tokens.Contains((byte)0))
            {
                throw new InvalidDataException($"The line at ${address:X4} does not end where its link says, at ${link - 1:X4}.");
            }

            lines.Add(new(Word(memory, address + 2), tokens));
            address = link;
        }

        return new(dialect, lines);
    }

    /// <summary>
    ///  Gets the program as a tokenized file holds it, linked for an address.
    /// </summary>
    /// <param name="address">Where the first line is to be; by default, the dialect's usual place.</param>
    /// <returns>The bytes, ending with the zero link.</returns>
    public byte[] ToImage(int? address = null)
    {
        if (Dialect is IntegerBasicDialect) { return IntegerBasicDialect.Image(this); }
        if (Dialect is BusinessBasicDialect) { return BusinessBasicDialect.Image(this); }
        int at = address ?? Dialect.DefaultLoadAddress;
        List<byte> bytes = [];
        foreach (BasicLine line in Lines)
        {
            int next = at + bytes.Count + LineOverhead + line.Tokens.Length;
            AddWord(bytes, next);
            AddWord(bytes, line.Number);
            bytes.AddRange(line.Tokens.Span);
            bytes.Add(0);
        }

        AddWord(bytes, 0);
        return [.. bytes];
    }

    /// <summary>
    ///  Writes the program into a machine's memory at the interpreter's program pointer, and clears the variables as
    ///  BASIC does when a line is typed.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   This sets the memory BASIC keeps; it does not reset BASIC's stack or where the CPU is, which only the
    ///   debugger can.
    ///  </para>
    /// </remarks>
    /// <param name="memory">The memory.</param>
    /// <exception cref="InvalidOperationException">
    ///  The program does not fit below the interpreter's memory limit.
    /// </exception>
    public void Write(IBasicMemory memory)
    {
        ArgumentNullException.ThrowIfNull(memory);
        if (Dialect is IntegerBasicDialect integer)
        {
            integer.Write(this, memory);
            return;
        }

        if (Dialect is BusinessBasicDialect business)
        {
            business.Write(this, memory);
            return;
        }

        BasicPointers pointers = Dialect.Pointers;
        int start = Word(memory, pointers.ProgramStart);
        byte[] image = ToImage(start);
        int end = start + image.Length;
        int limit = Dialect.WriteLimit(memory);
        if (start == 0 || end > limit)
        {
            throw new InvalidOperationException(
                $"The program needs {image.Length} bytes from ${start:X4}, but BASIC has room up to ${limit:X4}.");
        }

        for (int index = 0; index < image.Length; index++) { memory.Write(start + index, image[index]); }
        WriteWord(memory, pointers.Variables, end);
        if (pointers.ProgramEnd is int programEnd) { WriteWord(memory, programEnd, end); }
        Dialect.Clear(memory);
    }

    /// <summary>
    ///  Gets the program as text, one line per program line.
    /// </summary>
    /// <param name="pragma">Whether to start with a pragma naming the dialect.</param>
    /// <returns>The text, each line ending in a line feed.</returns>
    public string ToText(bool pragma = false)
    {
        using ValueStringBuilder builder = new(stackalloc char[256]);
        if (pragma)
        {
            builder.Append(Dialect == BasicDialect.Level2 ? "' retrocore " : "REM retrocore ");
            builder.Append(Dialect.Name);
            builder.Append('\n');
        }

        foreach (BasicLine line in Lines)
        {
            builder.Append(Dialect.FormatLine(line));
            builder.Append('\n');
        }

        return builder.ToString();
    }

    /// <summary>
    ///  Reads a two-byte word, low byte first.
    /// </summary>
    /// <param name="memory">The memory.</param>
    /// <param name="address">The word's address.</param>
    /// <returns>The word.</returns>
    internal static int Word(IBasicMemory memory, int address) => memory.Read(address) | (memory.Read((address + 1) & 0xFFFF) << 8);

    /// <summary>
    ///  Writes a two-byte word, low byte first.
    /// </summary>
    /// <param name="memory">The memory.</param>
    /// <param name="address">The word's address.</param>
    /// <param name="value">The word.</param>
    internal static void WriteWord(IBasicMemory memory, int address, int value)
    {
        memory.Write(address, (byte)value);
        memory.Write((address + 1) & 0xFFFF, (byte)(value >> 8));
    }

    private static void AddWord(List<byte> bytes, int value)
    {
        bytes.Add((byte)value);
        bytes.Add((byte)(value >> 8));
    }

    // Reads lines to the zero link, and says whether every link agrees with one load address; null when the bytes
    // end first.
    private static BasicProgram? ParseImage(BasicDialect dialect, ReadOnlySpan<byte> bytes, out bool linked)
    {
        linked = true;
        List<BasicLine> lines = [];
        int offset = 0;
        int? origin = null;
        while (true)
        {
            if (offset + 2 > bytes.Length) { return null; }
            int link = bytes[offset] | (bytes[offset + 1] << 8);
            if (link == 0) { break; }
            if (offset + 4 > bytes.Length) { return null; }
            int end = bytes[(offset + 4)..].IndexOf((byte)0);
            if (end < 0) { return null; }
            int next = offset + 4 + end + 1;
            origin ??= link - next;
            linked &= link - next == origin;
            lines.Add(new(bytes[offset + 2] | (bytes[offset + 3] << 8), bytes.Slice(offset + 4, end).ToArray()));
            offset = next;
        }

        return new(dialect, lines);
    }
}
