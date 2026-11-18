// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media.Commodore;

/// <summary>
///  Builds a tape from a program file, as the PET's kernal writes one with SAVE.
/// </summary>
/// <remarks>
///  <para>
///   A file is two blocks, a header and the program, and each block is written twice. A block starts after a
///   leader of short pulses: 27,136 before the header, 5,376 before the program. Its first copy is the sync bytes
///   <c>$89</c> down to <c>$81</c>, the data, a checksum (the XOR of the data), the end marker (long, short) and 79
///   short pulses; its second copy is the sync bytes <c>$09</c> down to <c>$01</c>, the data, the checksum and 80
///   short pulses. A byte is a long and a medium pulse, its 8 bits from the lowest, each a short and a medium for 0
///   or a medium and a short for 1, and an odd parity bit the same way.
///  </para>
///  <para>
///   The header is 192 bytes: the file type (1, a program), the start and end addresses (the end one past the last
///   byte), the name, and spaces. The pulses are 352, 504 and 672 µs, the PET's own to within its timer's jitter.
///  </para>
/// </remarks>
public static class CommodoreTapeBuilder
{
    /// <summary>
    ///  The length of a short pulse, in microseconds.
    /// </summary>
    public const int Short = 352;

    /// <summary>
    ///  The length of a medium pulse, in microseconds.
    /// </summary>
    public const int Medium = 504;

    /// <summary>
    ///  The length of a long pulse, in microseconds.
    /// </summary>
    public const int Long = 672;

    private const int HeaderLength = 192;

    /// <summary>
    ///  Builds a tape from a <c>.prg</c> file: its load address, low byte first, then the program.
    /// </summary>
    /// <param name="name">The name the tape's header gives, at most 16 characters of PETSCII.</param>
    /// <param name="prg">The file's bytes.</param>
    /// <returns>The tape.</returns>
    /// <exception cref="ArgumentException">The file is too short, or would pass <c>$FFFF</c>.</exception>
    public static CommodoreTape FromPrg(string name, ReadOnlySpan<byte> prg)
    {
        if (prg.Length < 3)
        {
            throw new ArgumentException("A program file is its load address and at least a byte.", nameof(prg));
        }

        return FromProgram(name, (ushort)(prg[0] | (prg[1] << 8)), prg[2..]);
    }

    /// <summary>
    ///  Builds a tape holding a program.
    /// </summary>
    /// <param name="name">The name the tape's header gives, at most 16 characters of PETSCII.</param>
    /// <param name="start">The address it loads at.</param>
    /// <param name="program">Its bytes.</param>
    /// <returns>The tape.</returns>
    /// <exception cref="ArgumentException">The name is too long, or the program would pass <c>$FFFF</c>.</exception>
    public static CommodoreTape FromProgram(string name, ushort start, ReadOnlySpan<byte> program)
    {
        ArgumentNullException.ThrowIfNull(name);
        if (name.Length > 16)
        {
            throw new ArgumentException("A tape file's name is at most 16 characters.", nameof(name));
        }

        int end = start + program.Length;
        if (program.IsEmpty || end > 0x10000)
        {
            throw new ArgumentException("The program must fit below $FFFF.", nameof(program));
        }

        byte[] header = new byte[HeaderLength];
        header.AsSpan().Fill(0x20);
        header[0] = 1;
        header[1] = (byte)start;
        header[2] = (byte)(start >> 8);
        header[3] = (byte)end;
        header[4] = (byte)(end >> 8);
        for (int i = 0; i < name.Length; i++)
        {
            char c = char.ToUpperInvariant(name[i]);
            header[5 + i] = c < 0x80 ? (byte)c : (byte)'?';
        }

        List<int> pulses = [];
        Block(pulses, 0x6A00, header);
        Block(pulses, 0x1500, program);
        return new(pulses);
    }

    private static void Block(List<int> pulses, int leader, ReadOnlySpan<byte> data)
    {
        Shorts(pulses, leader);
        Copy(pulses, 0x80, data);
        pulses.Add(Long);
        pulses.Add(Short);
        Shorts(pulses, 79);
        Copy(pulses, 0x00, data);
        Shorts(pulses, 80);
    }

    private static void Copy(List<int> pulses, byte sync, ReadOnlySpan<byte> data)
    {
        for (int count = 9; count >= 1; count--) { Byte(pulses, (byte)(sync | count)); }
        byte checksum = 0;
        foreach (byte value in data)
        {
            Byte(pulses, value);
            checksum ^= value;
        }

        Byte(pulses, checksum);
    }

    private static void Byte(List<int> pulses, byte value)
    {
        pulses.Add(Long);
        pulses.Add(Medium);
        bool parity = true;
        for (int bit = 0; bit < 8; bit++)
        {
            bool one = (value & (1 << bit)) != 0;
            parity ^= one;
            Bit(pulses, one);
        }

        Bit(pulses, parity);
    }

    private static void Bit(List<int> pulses, bool one)
    {
        pulses.Add(one ? Medium : Short);
        pulses.Add(one ? Short : Medium);
    }

    private static void Shorts(List<int> pulses, int count)
    {
        for (int i = 0; i < count; i++) { pulses.Add(Short); }
    }
}
