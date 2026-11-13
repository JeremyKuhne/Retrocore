// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Globalization;

namespace Retrocore.Debug;

/// <summary>
///  The Apple III's SOS calls: a program makes one with <c>BRK</c>, the call's number and its parameter list's
///  address.
/// </summary>
/// <remarks>
///  <para>
///   The numbers are SOS 1.3's call manager's: it takes a call only from a caller whose zero page is
///   <c>$1A00</c>, and only a number in its tables, failing others with <c>BADCZPAGE</c> and <c>BADSCNUM</c>.
///   The names are the SOS Reference Manual's.
///  </para>
/// </remarks>
internal static class SosCalls
{
    /// <summary>
    ///  The zero page register's value in a program that calls SOS.
    /// </summary>
    public const byte CallerZeroPage = 0x1A;

    /// <summary>
    ///  SOS's debug call: a program makes it to be stopped in a debugger.
    /// </summary>
    public const byte DebugCall = 0xFE;

    private static readonly string[] s_memory = ["REQUEST_SEG", "FIND_SEG", "CHANGE_SEG", "GET_SEG_INFO", "GET_SEG_NUM", "RELEASE_SEG"];
    private static readonly string[] s_utility = ["SET_FENCE", "GET_FENCE", "SET_TIME", "GET_TIME", "GET_ANALOG", "TERMINATE"];
    private static readonly string[] s_device = ["D_READ", "D_WRITE", "D_STATUS", "D_CONTROL", "GET_DEV_NUM", "D_INFO"];

    private static readonly string[] s_file =
    [
        "CREATE", "DESTROY", "RENAME", "SET_FILE_INFO", "GET_FILE_INFO", "VOLUME", "SET_PREFIX", "GET_PREFIX", "OPEN",
        "NEWLINE", "READ", "WRITE", "CLOSE", "FLUSH", "SET_MARK", "GET_MARK", "SET_EOF", "GET_EOF", "SET_LEVEL",
        "GET_LEVEL"
    ];

    /// <summary>
    ///  Gets an SOS call's name.
    /// </summary>
    /// <param name="number">The call's number.</param>
    /// <returns>Its name, or null when SOS has no such call.</returns>
    public static string? Name(byte number)
    {
        (string[] calls, int first) = (number & 0xE0) switch
        {
            0x40 => (s_memory, 0x40),
            0x60 => (s_utility, 0x60),
            0x80 => (s_device, 0x80),
            0xC0 => (s_file, 0xC0),
            _ => ([], 0)
        };

        int index = number - first;
        return index >= 0 && index < calls.Length ? calls[index] : null;
    }

    /// <summary>
    ///  Describes an SOS call with its main parameters, such as <c>OPEN ".CONSOLE"</c> or <c>READ ref 2, 512
    ///  bytes</c>, as SOS will read them.
    /// </summary>
    /// <param name="number">The call's number.</param>
    /// <param name="address">The call's BRK.</param>
    /// <param name="read">
    ///  Reads a byte: through an X-byte from <c>$80</c> up, or with X-byte 0 as the caller's memory is mapped.
    /// </param>
    /// <returns>The description, or null when SOS has no such call.</returns>
    /// <remarks>
    ///  <para>
    ///   The parameter list starts with its parameters' count, then holds each in the call's order: a value, or a
    ///   two-byte pointer to one. A pointer with a high byte of 0 is indirect: its low byte names a pointer in the
    ///   caller's zero page, with that pointer's X-byte.
    ///  </para>
    /// </remarks>
    public static string? Describe(byte number, ushort address, Func<byte, ushort, byte> read)
    {
        if (Name(number) is not { } name) { return null; }
        (byte x, ushort list) = Pointer(read, 0, (ushort)(address + 2));
        byte Byte(int offset) => read(x, (ushort)(list + offset));
        int Word(int offset) => Byte(offset) | (Byte(offset + 1) << 8);
        string Text(int offset)
        {
            (byte textX, ushort text) = Pointer(read, x, (ushort)(list + offset));
            int length = read(textX, text);
            char[] characters = new char[length];
            for (int index = 0; index < length; index++)
            {
                char character = (char)(read(textX, (ushort)(text + 1 + index)) & 0x7F);
                characters[index] = character < ' ' || character == 0x7F ? '?' : character;
            }

            return $"\"{new string(characters)}\"";
        }

        // Each list's parameters start at offset 1, after their count.
        string? parameters = number switch
        {
            0xC0 or 0xC1 or 0xC3 or 0xC4 or 0xC6 or 0xC8 or 0xC5 or 0x84 => Text(1),
            0xC2 => $"{Text(1)} to {Text(3)}",
            0xCA or 0xCB => $"ref {Byte(1)}, {Word(4)} bytes",
            0xD2 => $"level {Byte(1)}",
            >= 0xC9 and <= 0xD1 => $"ref {Byte(1)}",
            0x80 or 0x81 => $"device {Byte(1)}, {Word(4)} bytes, block {Word(6)}",
            0x82 or 0x83 => $"device {Byte(1)}, code {Byte(2)}",
            0x85 => $"device {Byte(1)}",
            0x42 or 0x45 => $"segment {Byte(1)}",
            0x60 => $"fence {Byte(1)}",
            _ => null
        };

        return parameters is null ? name : $"{name} {parameters}";
    }

    // Reads a caller's pointer parameter as SOS's POINTER does: direct, in the caller's memory, or through a zero-page
    // pointer and its X-byte.
    private static (byte X, ushort Address) Pointer(Func<byte, ushort, byte> read, byte x, ushort at)
    {
        byte low = read(x, at);
        byte high = read(x, (ushort)(at + 1));
        if (high != 0) { return (0, (ushort)((high << 8) | low)); }
        ushort zeroPage = (ushort)((CallerZeroPage << 8) + low);
        ushort pointer = (ushort)(read(0, zeroPage) | (read(0, (ushort)(zeroPage + 1)) << 8));
        byte xByte = read(0, (ushort)((zeroPage + 1) ^ 0x0C00));
        return ((xByte & 0x80) != 0 ? xByte : (byte)0, pointer);
    }

    /// <summary>
    ///  Reads an SOS call by its name, such as <c>OPEN</c> or <c>get file info</c>, or its number, such as
    ///  <c>$C8</c>.
    /// </summary>
    /// <param name="text">The name or number.</param>
    /// <returns>The call's number, or null when it names none.</returns>
    public static byte? Parse(string text)
    {
        string item = text.Trim();
        if (item.StartsWith('$')
            && byte.TryParse(item.AsSpan(1), NumberStyles.AllowHexSpecifier, CultureInfo.InvariantCulture, out byte number))
        {
            return Name(number) is null ? null : number;
        }

        string name = item.Replace(' ', '_').Replace('.', '_').ToUpperInvariant();
        for (int call = 0x40; call <= 0xFF; call++)
        {
            if (Name((byte)call) == name) { return (byte)call; }
        }

        return null;
    }
}
