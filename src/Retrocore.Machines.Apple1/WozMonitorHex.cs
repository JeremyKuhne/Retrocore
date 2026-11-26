// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Touki.Text;

namespace Retrocore.Machines.Apple1;

/// <summary>
///  Writes bytes as the text a user types at the Woz Monitor's <c>\</c> prompt to store them, and the line that runs
///  them: <c>0300: A9 C1 20 EF FF</c> then <c>0300R</c>.
/// </summary>
/// <remarks>
///  <para>
///   Each line gives its address, so a line typed wrong can be typed again on its own. The Monitor takes up to 127
///   keys before Return, so a line holds at most <see cref="MaxBytesPerLine"/> bytes; the default of
///   <see cref="DefaultBytesPerLine"/> keeps each line within the terminal's 40 columns. Lines end with a carriage
///   return and a line feed. <see cref="Apple1Keyboard.Type(string)"/> skips the carriage return and types the line
///   feed as Return; a Monitor sent both runs the line at the carriage return and skips the line feed at the start
///   of the next, as it skips any character below <c>.</c>, and the terminal drops the line feed.
///  </para>
/// </remarks>
public static class WozMonitorHex
{
    /// <summary>
    ///  The bytes a line holds by default: 8, which make a 29-character line.
    /// </summary>
    public const int DefaultBytesPerLine = 8;

    /// <summary>
    ///  The most bytes a line can hold: 40, which make 125 characters, within the 127 keys the Monitor takes.
    /// </summary>
    public const int MaxBytesPerLine = 40;

    /// <summary>
    ///  The line ending: a carriage return and a line feed, which make one Return to the Monitor.
    /// </summary>
    public const string NewLine = "\r\n";

    /// <summary>
    ///  Writes the lines that store the bytes from an address, then optionally the line that runs them.
    /// </summary>
    /// <param name="bytes">The bytes to store.</param>
    /// <param name="address">The address of the first byte.</param>
    /// <param name="entry">Where to start the program with <c>R</c>, or null for no run line.</param>
    /// <param name="bytesPerLine">The bytes on each line, 1 to <see cref="MaxBytesPerLine"/>.</param>
    /// <returns>The text to type, each line ending in <see cref="NewLine"/>.</returns>
    /// <exception cref="ArgumentOutOfRangeException">
    ///  <paramref name="bytesPerLine"/> is out of range, or the bytes run past <c>$FFFF</c>.
    /// </exception>
    public static string ToText(ReadOnlySpan<byte> bytes, ushort address, ushort? entry, int bytesPerLine = DefaultBytesPerLine)
    {
        ArgumentOutOfRangeException.ThrowIfLessThan(bytesPerLine, 1);
        ArgumentOutOfRangeException.ThrowIfGreaterThan(bytesPerLine, MaxBytesPerLine);
        if (address + bytes.Length > 0x10000)
        {
            throw new ArgumentOutOfRangeException(nameof(bytes), $"{bytes.Length} bytes from ${address:X4} run past $FFFF.");
        }

        using ValueStringBuilder text = new(stackalloc char[256]);
        for (int start = 0; start < bytes.Length; start += bytesPerLine)
        {
            text.Append($"{address + start:X4}:");
            foreach (byte value in bytes.Slice(start, Math.Min(bytesPerLine, bytes.Length - start)))
            {
                text.Append($" {value:X2}");
            }

            text.Append(NewLine);
        }

        if (entry is { } run)
        {
            text.Append($"{run:X4}R");
            text.Append(NewLine);
        }

        return text.ToString();
    }
}
