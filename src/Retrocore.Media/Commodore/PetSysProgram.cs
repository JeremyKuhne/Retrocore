// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media.Commodore;

/// <summary>
///  Builds a PET program file that starts machine code from BASIC: a one-line BASIC program at <c>$0401</c>, such as
///  <c>10 SYS1037</c>, and the code, so that <c>LOAD</c> then <c>RUN</c> runs it.
/// </summary>
/// <remarks>
///  <para>
///   The line is stored as BASIC stores a typed one: the address of the next line, the line number, the token for
///   <c>SYS</c> (<c>$9E</c>, the same in BASIC 1, 2 and 4), the address in ASCII digits, and a zero; then a next-line
///   address of zero ends the program. The code follows, at its address, with zeros filling any gap, so the file is
///   one run of bytes from <c>$0401</c>. BASIC's variables start past the file's end, so they do not overwrite the
///   code.
///  </para>
/// </remarks>
public static class PetSysProgram
{
    /// <summary>
    ///  Where a PET's BASIC program starts, in every BASIC.
    /// </summary>
    public const ushort BasicStart = 0x0401;

    /// <summary>
    ///  BASIC's token for <c>SYS</c>, in BASIC 1, 2 and 4.
    /// </summary>
    public const byte SysToken = 0x9E;

    /// <summary>
    ///  The highest line number BASIC accepts.
    /// </summary>
    public const int MaximumLineNumber = 63999;

    /// <summary>
    ///  Builds a program file with the code at an address, which the BASIC line starts.
    /// </summary>
    /// <param name="code">The machine code, which starts at its first byte.</param>
    /// <param name="address">
    ///  Where the code loads, at or past <see cref="StubEnd(int, int)"/>; null for right after the line, at
    ///  <see cref="CodeAddress(int)"/>.
    /// </param>
    /// <param name="lineNumber">The BASIC line's number, 0-63999.</param>
    /// <returns>The file's bytes: the load address, <c>$0401</c>, low byte first, then the program.</returns>
    /// <exception cref="ArgumentException">
    ///  The code is empty, would overlap the BASIC line, or would pass <c>$FFFF</c>.
    /// </exception>
    /// <exception cref="ArgumentOutOfRangeException">The address or line number is out of range.</exception>
    public static byte[] Build(ReadOnlySpan<byte> code, int? address = null, int lineNumber = 10)
    {
        if (code.IsEmpty) { throw new ArgumentException("There is no code to run.", nameof(code)); }
        int start = address ?? CodeAddress(lineNumber);
        int stubEnd = StubEnd(start, lineNumber);
        if (start < stubEnd)
        {
            throw new ArgumentException(
                $"The code at ${start:X4} would overlap the BASIC program, which ends at ${stubEnd - 1:X4}.",
                nameof(address));
        }

        if (start + code.Length > 0x10000)
        {
            throw new ArgumentException("The code must end by $FFFF.", nameof(code));
        }

        byte[] prg = new byte[2 + start + code.Length - BasicStart];
        WriteStub(prg, start, lineNumber);
        code.CopyTo(prg.AsSpan(2 + start - BasicStart));
        return prg;
    }

    /// <summary>
    ///  Builds a program file of the BASIC line alone, for code that loads separately.
    /// </summary>
    /// <param name="address">The address the line's <c>SYS</c> calls, 0-65535.</param>
    /// <param name="lineNumber">The BASIC line's number, 0-63999.</param>
    /// <returns>The file's bytes: the load address, <c>$0401</c>, low byte first, then the program.</returns>
    /// <exception cref="ArgumentOutOfRangeException">The address or line number is out of range.</exception>
    public static byte[] Stub(int address, int lineNumber = 10)
    {
        byte[] prg = new byte[2 + StubEnd(address, lineNumber) - BasicStart];
        WriteStub(prg, address, lineNumber);
        return prg;
    }

    /// <summary>
    ///  Gets where the code goes when it follows the BASIC line, as <see cref="Build(ReadOnlySpan{byte}, int?, int)"/>
    ///  places it.
    /// </summary>
    /// <param name="lineNumber">The BASIC line's number, 0-63999.</param>
    /// <returns>
    ///  The address, <c>$040D</c> (1037): the line number is stored in two bytes whatever its digits, and the address
    ///  has four digits.
    /// </returns>
    /// <exception cref="ArgumentOutOfRangeException">The line number is out of range.</exception>
    public static int CodeAddress(int lineNumber = 10) => StubEnd(1037, lineNumber);

    /// <summary>
    ///  Gets the address one past the program's end when the line calls an address: the line, then the two zeros
    ///  that end the program.
    /// </summary>
    /// <param name="address">The address the line's <c>SYS</c> calls, 0-65535.</param>
    /// <param name="lineNumber">The BASIC line's number, 0-63999.</param>
    /// <returns>The address.</returns>
    /// <exception cref="ArgumentOutOfRangeException">The address or line number is out of range.</exception>
    public static int StubEnd(int address, int lineNumber = 10)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(address);
        ArgumentOutOfRangeException.ThrowIfGreaterThan(address, 0xFFFF);
        ArgumentOutOfRangeException.ThrowIfNegative(lineNumber);
        ArgumentOutOfRangeException.ThrowIfGreaterThan(lineNumber, MaximumLineNumber);

        // The next-line address, the line number, SYS, the digits, the line's zero, and the program's two zeros.
        return BasicStart + 2 + 2 + 1 + Digits(address) + 1 + 2;
    }

    /// <summary>
    ///  Builds a tape holding a program file, as <c>SAVE</c> would write it.
    /// </summary>
    /// <param name="name">The name the tape's header gives, at most 16 characters of PETSCII.</param>
    /// <param name="prg">The file's bytes.</param>
    /// <returns>The tape.</returns>
    /// <exception cref="ArgumentException">
    ///  The name is too long, or the file is too short or would pass <c>$FFFF</c>.
    /// </exception>
    public static CommodoreTape ToTape(string name, ReadOnlySpan<byte> prg) => CommodoreTapeBuilder.FromPrg(name, prg);

    /// <summary>
    ///  Builds a TAP image of a tape holding a program file.
    /// </summary>
    /// <param name="name">The name the tape's header gives, at most 16 characters of PETSCII.</param>
    /// <param name="prg">The file's bytes.</param>
    /// <returns>The image, a version 1 TAP image for the PET.</returns>
    /// <exception cref="ArgumentException">
    ///  The name is too long, or the file is too short or would pass <c>$FFFF</c>.
    /// </exception>
    public static byte[] ToTap(string name, ReadOnlySpan<byte> prg) => TapFormat.Write(ToTape(name, prg).Pulses);

    private static void WriteStub(Span<byte> prg, int address, int lineNumber)
    {
        string digits = address.ToString(System.Globalization.CultureInfo.InvariantCulture);
        int next = BasicStart + 2 + 2 + 1 + digits.Length + 1;
        prg[0] = BasicStart & 0xFF;
        prg[1] = BasicStart >> 8;
        prg[2] = (byte)next;
        prg[3] = (byte)(next >> 8);
        prg[4] = (byte)lineNumber;
        prg[5] = (byte)(lineNumber >> 8);
        prg[6] = SysToken;
        for (int i = 0; i < digits.Length; i++) { prg[7 + i] = (byte)digits[i]; }

        // The line's zero and the zero next-line address that ends the program are already there.
    }

    private static int Digits(int value) => value switch
    {
        < 10 => 1,
        < 100 => 2,
        < 1000 => 3,
        < 10000 => 4,
        _ => 5
    };
}
