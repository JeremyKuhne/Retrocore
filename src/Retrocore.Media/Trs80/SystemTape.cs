// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media.Trs80;

/// <summary>
///  A Level II <c>SYSTEM</c> tape, the machine-language tape the <c>SYSTEM</c> command loads at its <c>*?</c> prompt,
///  as the bytes of a 500 baud CAS image.
/// </summary>
/// <remarks>
///  <para>
///   The tape is a leader of 255 zero bytes, the <c>$A5</c> sync byte, then <c>$55</c> and the six-character name,
///   padded with spaces. Each data block is <c>$3C</c>, its count of bytes (0 for 256), its load address low byte first,
///   the bytes, and a checksum: the sum of the address's two bytes and the data's, modulo 256. The tape ends with
///   <c>$78</c> and the entry address, low byte first. Level II's loader (<c>ST_SYSTEM</c> in Level2.asm) compares the
///   name typed with the tape's, up to the typed name's length, stores each block where it says, shows a C for a bad
///   checksum, and keeps the entry for a bare <c>/</c> at its next prompt.
///  </para>
/// </remarks>
public static class SystemTape
{
    /// <summary>
    ///  The most characters a tape's name has.
    /// </summary>
    public const int NameLength = 6;

    /// <summary>
    ///  The most bytes a data block holds.
    /// </summary>
    public const int BlockSize = 256;

    // The leader's zero bytes, as Level II's CSAVE writes them.
    private const int LeaderLength = 255;
    private const byte Sync = 0xA5;
    private const byte Header = 0x55;
    private const byte Data = 0x3C;
    private const byte End = 0x78;

    /// <summary>
    ///  Writes a tape of bytes that load at an address.
    /// </summary>
    /// <param name="name">
    ///  The tape's name: 1 to 6 capital letters and digits from a letter, which <c>SYSTEM</c>'s prompt takes.
    /// </param>
    /// <param name="address">Where the bytes load.</param>
    /// <param name="bytes">The bytes, at least one, ending at or below <c>$FFFF</c>.</param>
    /// <param name="entry">Where <c>/</c> at the prompt starts the program.</param>
    /// <returns>The CAS image's bytes.</returns>
    /// <exception cref="ArgumentException">The name, the address or the bytes are not a tape's.</exception>
    public static byte[] Write(string name, int address, ReadOnlySpan<byte> bytes, int entry)
    {
        ArgumentNullException.ThrowIfNull(name);
        if (!IsName(name))
        {
            throw new ArgumentException($"A SYSTEM tape's name is 1 to {NameLength} capital letters and digits from a letter; '{name}' is not.", nameof(name));
        }

        if (bytes.IsEmpty || address < 0 || address + bytes.Length > 0x10000)
        {
            throw new ArgumentException("A SYSTEM tape holds at least one byte, from an address the bytes fit after.", nameof(bytes));
        }

        ArgumentOutOfRangeException.ThrowIfGreaterThan((uint)entry, 0xFFFFu, nameof(entry));
        List<byte> tape = [.. new byte[LeaderLength], Sync, Header, .. name.PadRight(NameLength).Select(character => (byte)character)];
        for (int offset = 0; offset < bytes.Length; offset += BlockSize)
        {
            ReadOnlySpan<byte> block = bytes.Slice(offset, Math.Min(BlockSize, bytes.Length - offset));
            int at = address + offset;
            int sum = (at & 0xFF) + (at >> 8);
            tape.Add(Data);
            tape.Add((byte)block.Length);
            tape.Add((byte)at);
            tape.Add((byte)(at >> 8));
            foreach (byte value in block)
            {
                tape.Add(value);
                sum += value;
            }

            tape.Add((byte)sum);
        }

        tape.Add(End);
        tape.Add((byte)entry);
        tape.Add((byte)(entry >> 8));
        return [.. tape];
    }

    /// <summary>
    ///  Reads a tape back, checking it more strictly than Level II's loader, which passes over bytes between blocks
    ///  and goes on past a bad checksum.
    /// </summary>
    /// <param name="tape">The CAS image's bytes.</param>
    /// <returns>The tape's name, without its padding, its blocks and its entry address.</returns>
    /// <exception cref="InvalidDataException">
    ///  The tape is not a SYSTEM tape, ends early, or a block's checksum is wrong.
    /// </exception>
    public static (string Name, IReadOnlyList<(int Address, byte[] Bytes)> Blocks, int Entry) Read(ReadOnlySpan<byte> tape)
    {
        int at = 0;
        while (at < tape.Length && tape[at] == 0) { at++; }
        if (at + 2 + NameLength > tape.Length || tape[at] != Sync || tape[at + 1] != Header)
        {
            throw new InvalidDataException("A SYSTEM tape starts with its leader, $A5 and $55.");
        }

        string name = new([.. tape.Slice(at + 2, NameLength).ToArray().Select(value => (char)value)]);
        at += 2 + NameLength;
        List<(int Address, byte[] Bytes)> blocks = [];
        while (true)
        {
            byte kind = Byte(tape, at++);
            if (kind == End)
            {
                return (name.TrimEnd(' '), blocks, Byte(tape, at) | (Byte(tape, at + 1) << 8));
            }

            if (kind != Data)
            {
                throw new InvalidDataException($"A SYSTEM tape's block starts with $3C or $78, not ${kind:X2}.");
            }

            int count = Byte(tape, at) == 0 ? BlockSize : Byte(tape, at);
            int address = Byte(tape, at + 1) | (Byte(tape, at + 2) << 8);
            at += 3;
            byte[] bytes = new byte[count];
            int sum = (address & 0xFF) + (address >> 8);
            for (int index = 0; index < count; index++)
            {
                bytes[index] = Byte(tape, at++);
                sum += bytes[index];
            }

            if (Byte(tape, at++) != (byte)sum)
            {
                throw new InvalidDataException($"The block at ${address:X4} has a bad checksum.");
            }

            blocks.Add((address, bytes));
        }
    }

    /// <summary>
    ///  Gets whether a name is a tape's: 1 to 6 capital letters and digits from a letter.
    /// </summary>
    /// <param name="name">The name.</param>
    /// <returns>Whether <c>SYSTEM</c>'s prompt can take it.</returns>
    public static bool IsName(string name) =>
        name is { Length: > 0 and <= NameLength }
            && char.IsAsciiLetterUpper(name[0])
            && name.All(character => char.IsAsciiLetterUpper(character) || char.IsAsciiDigit(character));

    private static byte Byte(ReadOnlySpan<byte> tape, int at) =>
        at < tape.Length ? tape[at] : throw new InvalidDataException("The SYSTEM tape ends inside a block.");
}
