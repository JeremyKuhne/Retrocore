// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media.Trs80;

/// <summary>
///  A Color Computer cassette of one machine-language file, the kind Color BASIC's <c>CLOADM</c> loads and
///  <c>EXEC</c> starts, as the bytes of a <c>.cas</c> image.
/// </summary>
/// <remarks>
///  <para>
///   Each block is <c>$55</c>, the <c>$3C</c> sync byte, its type (0 the name file, 1 data, <c>$FF</c> the end of the
///   file), its length, its data, a checksum and <c>$55</c> again; the checksum is the sum of the type, the length and
///   the data, modulo 256 (<c>SNDBLK</c> and <c>GETBLK</c> in ColorBasic.asm). The tape is a leader of 128 <c>$55</c>
///   bytes and the name file block, then another leader and the data in blocks of 255, then the end block. The name
///   file's 15 bytes are the name, padded to eight with spaces; the file type, 2 for machine language; the ASCII flag,
///   0; the gap flag, 0, for a file written without gaps, whose data blocks <c>CLOADM</c> stores where the file loads;
///   the address <c>EXEC</c> starts and the address the file loads at, each high byte first. <c>CLOADM</c> stores the
///   data blocks one after another from the load address.
///  </para>
/// </remarks>
public static class CocoTape
{
    /// <summary>
    ///  The most characters a file's name has.
    /// </summary>
    public const int NameLength = 8;

    /// <summary>
    ///  The most bytes a data block holds.
    /// </summary>
    public const int BlockSize = 255;

    /// <summary>
    ///  The file type of a machine-language file, which <c>CLOADM</c> loads.
    /// </summary>
    public const byte MachineLanguage = 2;

    // The leader's $55 bytes, as CSAVEM writes them.
    private const int LeaderLength = 128;
    private const byte Leader = 0x55;
    private const byte Sync = 0x3C;
    private const byte NameBlock = 0x00;
    private const byte DataBlock = 0x01;
    private const byte EndBlock = 0xFF;

    /// <summary>
    ///  Writes a tape of a machine-language file.
    /// </summary>
    /// <param name="name">
    ///  The file's name: 1 to 8 capital letters and digits from a letter, which CLOADM's quotes take.
    /// </param>
    /// <param name="address">Where the bytes load.</param>
    /// <param name="bytes">The bytes, at least one, ending at or below <c>$FFFF</c>.</param>
    /// <param name="entry">Where <c>EXEC</c> starts the program.</param>
    /// <returns>The <c>.cas</c> image's bytes.</returns>
    /// <exception cref="ArgumentException">The name, the address or the bytes are not a tape's.</exception>
    public static byte[] Write(string name, int address, ReadOnlySpan<byte> bytes, int entry)
    {
        ArgumentNullException.ThrowIfNull(name);
        if (!IsName(name))
        {
            throw new ArgumentException($"A cassette file's name is 1 to {NameLength} capital letters and digits from a letter; '{name}' is not.", nameof(name));
        }

        if (bytes.IsEmpty || address < 0 || address + bytes.Length > 0x10000)
        {
            throw new ArgumentException("A cassette file holds at least one byte, from an address the bytes fit after.", nameof(bytes));
        }

        ArgumentOutOfRangeException.ThrowIfGreaterThan((uint)entry, 0xFFFFu, nameof(entry));
        List<byte> tape = [];
        tape.AddRange(Enumerable.Repeat(Leader, LeaderLength));
        byte[] header =
        [
            .. name.PadRight(NameLength).Select(character => (byte)character),
            MachineLanguage, 0, 0,
            (byte)(entry >> 8), (byte)entry,
            (byte)(address >> 8), (byte)address
        ];

        Block(tape, NameBlock, header);
        tape.AddRange(Enumerable.Repeat(Leader, LeaderLength));
        for (int offset = 0; offset < bytes.Length; offset += BlockSize)
        {
            Block(tape, DataBlock, bytes.Slice(offset, Math.Min(BlockSize, bytes.Length - offset)));
        }

        Block(tape, EndBlock, []);
        return [.. tape];
    }

    /// <summary>
    ///  Reads a tape of a machine-language file back, checking each block's checksum.
    /// </summary>
    /// <param name="tape">The <c>.cas</c> image's bytes.</param>
    /// <returns>The file's name, without its padding, its load address, its bytes and its entry address.</returns>
    /// <exception cref="InvalidDataException">
    ///  The tape is not one machine-language file, ends early, or a block's checksum is wrong.
    /// </exception>
    public static (string Name, int Address, byte[] Bytes, int Entry) Read(ReadOnlySpan<byte> tape)
    {
        int at = 0;
        (byte type, byte[] header) = NextBlock(tape, ref at);
        if (type != NameBlock || header.Length != 15 || header[8] != MachineLanguage)
        {
            throw new InvalidDataException("The tape does not start with a machine-language file's name block.");
        }

        string name = new([.. header[..NameLength].Select(value => (char)value)]);
        int entry = (header[11] << 8) | header[12];
        int address = (header[13] << 8) | header[14];
        List<byte> bytes = [];
        while (true)
        {
            (type, byte[] data) = NextBlock(tape, ref at);
            if (type == EndBlock) { return (name.TrimEnd(' '), address, [.. bytes], entry); }
            if (type != DataBlock)
            {
                throw new InvalidDataException($"A data block's type is 1 or $FF, not ${type:X2}.");
            }

            bytes.AddRange(data);
        }
    }

    /// <summary>
    ///  Gets whether a name is a cassette file's: 1 to 8 capital letters and digits from a letter.
    /// </summary>
    /// <param name="name">The name.</param>
    /// <returns>Whether CLOADM can take it.</returns>
    public static bool IsName(string name) =>
        name is { Length: > 0 and <= NameLength }
            && char.IsAsciiLetterUpper(name[0])
            && name.All(character => char.IsAsciiLetterUpper(character) || char.IsAsciiDigit(character));

    private static void Block(List<byte> tape, byte type, ReadOnlySpan<byte> data)
    {
        int sum = type + data.Length;
        tape.Add(Leader);
        tape.Add(Sync);
        tape.Add(type);
        tape.Add((byte)data.Length);
        foreach (byte value in data)
        {
            tape.Add(value);
            sum += value;
        }

        tape.Add((byte)sum);
        tape.Add(Leader);
    }

    // The next block from the sync byte on: its type and data, its checksum checked.
    private static (byte Type, byte[] Data) NextBlock(ReadOnlySpan<byte> tape, ref int at)
    {
        while (at < tape.Length && tape[at] != Sync) { at++; }
        if (at + 3 > tape.Length) { throw new InvalidDataException("The tape ends before a block."); }
        byte type = tape[at + 1];
        int length = tape[at + 2];
        at += 3;
        if (at + length + 1 > tape.Length) { throw new InvalidDataException("The tape ends inside a block."); }
        byte[] data = tape.Slice(at, length).ToArray();
        int sum = type + length + data.Sum(value => value);
        if (tape[at + length] != (byte)sum)
        {
            throw new InvalidDataException($"A block of type ${type:X2} has a bad checksum.");
        }

        at += length + 1;
        return (type, data);
    }
}
