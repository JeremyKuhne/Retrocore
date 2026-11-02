// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Basic;

/// <summary>
///  A Level II BASIC program on a Model I tape (<c>.cas</c>), as CSAVE writes it and CLOAD reads it.
/// </summary>
/// <remarks>
///  <para>
///   The tape holds a leader of zero bytes, the $A5 sync byte, three $D3 bytes, the one-character file name, and
///   the program from its first line through the zero link. CLOAD relinks the lines, so the links may be for any
///   address.
///  </para>
/// </remarks>
public static class BasicTape
{
    private const byte Sync = 0xA5;
    private const byte Header = 0xD3;
    private const int HeaderLength = 3;
    private const int LeaderLength = 255;

    /// <summary>
    ///  Writes a program as CSAVE would.
    /// </summary>
    /// <param name="program">The program, which must be Level II.</param>
    /// <param name="name">The file name: one character, as CSAVE keeps only the first.</param>
    /// <returns>The tape's bytes.</returns>
    /// <exception cref="ArgumentException">The program is not Level II, or the name is not printable.</exception>
    public static byte[] Write(BasicProgram program, char name)
    {
        ArgumentNullException.ThrowIfNull(program);
        if (program.Dialect != BasicDialect.Level2)
        {
            throw new ArgumentException("Only Level II programs go on a CSAVE tape.", nameof(program));
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
    /// <param name="name">The program's one-character name.</param>
    /// <returns>The program.</returns>
    /// <exception cref="InvalidDataException">The tape does not hold a CSAVE program.</exception>
    public static BasicProgram Read(ReadOnlySpan<byte> bytes, out char name)
    {
        int index = bytes.IndexOfAnyExcept((byte)0);
        if (index < 0 || bytes[index] != Sync)
        {
            throw new InvalidDataException("The tape has no leader and sync byte.");
        }

        index++;
        if (bytes.Length < index + HeaderLength + 1 || bytes.Slice(index, HeaderLength).IndexOfAnyExcept(Header) >= 0)
        {
            throw new InvalidDataException("The tape does not hold a BASIC program: CSAVE's three $D3 bytes are missing.");
        }

        name = (char)bytes[index + HeaderLength];
        return BasicProgram.FromImage(BasicDialect.Level2, bytes[(index + HeaderLength + 1)..]);
    }
}
