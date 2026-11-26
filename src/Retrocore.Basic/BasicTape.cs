// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Basic;

/// <summary>
///  A Level II or Level I BASIC program on a Model I tape (<c>.cas</c>), as CSAVE writes it and CLOAD reads it.
/// </summary>
/// <remarks>
///  <para>
///   Level II's tape holds a leader of zero bytes, the $A5 sync byte, three $D3 bytes, the one-character file name,
///   and the program from its first line through the zero link. CLOAD relinks the lines, so the links may be for any
///   address.
///  </para>
///  <para>
///   Level I's holds 128 zero bytes, the $A5 sync byte, the block's start and end addresses, high bytes first, the
///   program from <c>$4200</c> up to its end, and a byte that makes the program's bytes sum to zero; it has no name
///   (<c>TAPE_WRITE_BLOCK</c> in Level1.asm).
///  </para>
/// </remarks>
public static class BasicTape
{
    private const byte Sync = 0xA5;
    private const byte Header = 0xD3;
    private const int HeaderLength = 3;
    private const int LeaderLength = 255;
    private const int Level1LeaderLength = 128;
    private const int Level1HeaderLength = 4;

    /// <summary>
    ///  Writes a program as CSAVE would.
    /// </summary>
    /// <param name="program">The program, Level II or Level I.</param>
    /// <param name="name">The file name: one character, as CSAVE keeps only the first; Level I's tape has none.</param>
    /// <returns>The tape's bytes.</returns>
    /// <exception cref="ArgumentException">The program is of neither Level, or the name is not printable.</exception>
    public static byte[] Write(BasicProgram program, char name)
    {
        ArgumentNullException.ThrowIfNull(program);
        if (program.Dialect == BasicDialect.Level1) { return WriteLevel1(program); }
        if (program.Dialect != BasicDialect.Level2)
        {
            throw new ArgumentException("Only Level II and Level I programs go on a CSAVE tape.", nameof(program));
        }

        if (name is < ' ' or > '~')
        {
            throw new ArgumentException("The tape's name is one printable character.", nameof(name));
        }

        return
        [
            .. new byte[LeaderLength],
            Sync,
            Header,
            Header,
            Header,
            (byte)name,
            .. program.ToImage()
        ];
    }

    /// <summary>
    ///  Reads the first program on a tape, as CLOAD would.
    /// </summary>
    /// <param name="bytes">The tape's bytes.</param>
    /// <param name="name">The program's one-character name; a space for Level I's, which has none.</param>
    /// <returns>The program, in the dialect of the Level that recorded it.</returns>
    /// <exception cref="InvalidDataException">The tape does not hold a CSAVE program.</exception>
    public static BasicProgram Read(ReadOnlySpan<byte> bytes, out char name)
    {
        int index = bytes.IndexOfAnyExcept((byte)0);
        if (index < 0 || bytes[index] != Sync)
        {
            throw new InvalidDataException("The tape has no leader and sync byte.");
        }

        index++;
        if (ReadLevel1(bytes[index..]) is { } level1)
        {
            name = ' ';
            return level1;
        }

        if (bytes.Length < index + HeaderLength + 1 || bytes.Slice(index, HeaderLength).IndexOfAnyExcept(Header) >= 0)
        {
            throw new InvalidDataException("The tape does not hold a BASIC program: CSAVE's three $D3 bytes are missing.");
        }

        name = (char)bytes[index + HeaderLength];
        return BasicProgram.FromImage(BasicDialect.Level2, bytes[(index + HeaderLength + 1)..]);
    }

    // Level I's block, its bytes summing to zero with the byte after them; null when it is not one. A block that does
    // not start at $4200 is not a program, but memory, such as a machine-code program that starts itself by loading
    // over CLOAD's return address.
    private static BasicProgram? ReadLevel1(ReadOnlySpan<byte> block)
    {
        if (block.Length < Level1HeaderLength) { return null; }
        int start = (block[0] << 8) | block[1];
        int end = (block[2] << 8) | block[3];
        int length = end - start;
        if (length < 0) { return null; }
        if (block.Length < Level1HeaderLength + length + 1)
        {
            return start == Level1Dialect.ProgramStart
                ? throw new InvalidDataException("The Level I tape ends before its program and the checksum after it do.")
                : null;
        }

        ReadOnlySpan<byte> program = block.Slice(Level1HeaderLength, length);
        int sum = block[Level1HeaderLength + length];
        foreach (byte value in program) { sum += value; }
        if ((sum & 0xFF) != 0)
        {
            return start == Level1Dialect.ProgramStart
                ? throw new InvalidDataException("The Level I tape's checksum is wrong: the program did not record or copy whole.")
                : null;
        }

        if (start != Level1Dialect.ProgramStart)
        {
            throw new InvalidDataException(
                $"This Level I tape loads ${start:X4}-${end - 1:X4}, not a BASIC program from $4200: it is memory, such as machine code.");
        }

        return BasicProgram.FromImage(BasicDialect.Level1, program);
    }

    private static byte[] WriteLevel1(BasicProgram program)
    {
        byte[] image = program.ToImage();
        int end = Level1Dialect.ProgramStart + image.Length;
        int sum = 0;
        foreach (byte value in image) { sum += value; }
        return
        [
            .. new byte[Level1LeaderLength],
            Sync,
            Level1Dialect.ProgramStart >> 8,
            Level1Dialect.ProgramStart & 0xFF,
            (byte)(end >> 8),
            (byte)end,
            .. image,
            (byte)-sum
        ];
    }
}
