// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Globalization;
using Touki.Text;

namespace Retrocore.Basic;

/// <summary>
///  The Atari floating point package's numbers, as Atari BASIC keeps them: six bytes, an exponent byte (a power of 100
///  biased by $40, its top bit the sign) and five bytes of BCD, ten digits with the point after the first byte.
/// </summary>
/// <remarks>
///  <para>
///   <see cref="Parse"/> is the package's AFP and <see cref="Format"/> its FASC, step for step from the SDK's
///   <c>FloatingPoint.asm</c>, so a constant reads and lists as Atari BASIC reads and lists it: only the first nine
///   significant digits count, and later ones are dropped rather than rounded.
///  </para>
/// </remarks>
internal static class AtariNumbers
{
    /// <summary>
    ///  The bytes in a number.
    /// </summary>
    internal const int Size = 6;

    /// <summary>
    ///  The end of line, which ends the text AFP reads.
    /// </summary>
    internal const byte EndOfLine = 0x9B;

    /// <summary>
    ///  The exponent byte of 100^0: the power of 100 is the byte less this.
    /// </summary>
    internal const int Bias = 0x40;

    /// <summary>
    ///  The exponent byte's bit that is set for a negative number.
    /// </summary>
    internal const byte Sign = 0x80;

    /// <summary>
    ///  The smallest exponent byte out of range: 1E98, an overflow.
    /// </summary>
    internal const int TooLarge = 0x71;

    /// <summary>
    ///  The smallest exponent byte kept, 1E-98; smaller results become 0.
    /// </summary>
    internal const int Smallest = 0x0F;

    /// <summary>
    ///  Reads a number from text, as AFP does.
    /// </summary>
    /// <param name="text">The text, ending in an end of line.</param>
    /// <param name="index">
    ///  Where the number, or spaces before it, starts; on return, the first character after it. AFP leaves it past
    ///  what it tried when the text holds no number.
    /// </param>
    /// <returns>The number, or null when the text holds none or it is too large.</returns>
    internal static byte[]? Parse(ReadOnlySpan<byte> text, ref int index)
    {
        AtariAfp state = new(text, index);
        byte[]? number = state.Run();
        index = state.Cix;
        return number;
    }

    /// <summary>
    ///  Writes a number as FASC does: plainly from 0.01 up to 10^10, otherwise in E notation.
    /// </summary>
    /// <param name="number">The number.</param>
    /// <returns>The text.</returns>
    internal static string Format(ReadOnlySpan<byte> number)
    {
        // LBUFF, with LBPR1 and LBPR2 before it: index 2 is LBUFF's first byte.
        byte[] buffer = new byte[24];
        const int lbuff = 2;
        int start = lbuff;
        buffer[lbuff - 1] = (byte)'0';
        byte exponent = number[0];
        if (exponent == 0) { return "0"; }

        int bare = exponent & 0x7F;
        if (bare >= Bias - 1 && bare < Bias + 5)
        {
            WriteDigits(buffer, lbuff, number, bare - (Bias - 1));
            int last = FindLastDigit(buffer, lbuff);
            buffer[lbuff + last] |= 0x80;
            if (buffer[lbuff] == '.') { start--; }
            else if (buffer[lbuff] == '0') { start++; }
        }
        else
        {
            WriteDigits(buffer, lbuff, number, 1);
            int length = FindLastDigit(buffer, lbuff) + 1;
            int power = (byte)((exponent << 1) - (Bias * 2));
            if (buffer[lbuff] != '0')
            {
                // Two digits before the point: move it left one place.
                (buffer[lbuff + 1], buffer[lbuff + 2]) = (buffer[lbuff + 2], buffer[lbuff + 1]);
                if (length == 2) { length++; }
                power = (byte)(power + 1);
            }

            buffer[lbuff + length++] = (byte)'E';
            sbyte signed = (sbyte)power;
            buffer[lbuff + length++] = (byte)(signed < 0 ? '-' : '+');
            int magnitude = Math.Abs((int)signed);
            buffer[lbuff + length++] = (byte)('0' + magnitude / 10);
            buffer[lbuff + length] = (byte)(('0' + magnitude % 10) | 0x80);
            if (buffer[lbuff] == '0') { start++; }
        }

        if ((exponent & Sign) != 0)
        {
            start--;
            buffer[start] = (byte)'-';
        }

        using ValueStringBuilder text = new(stackalloc char[24]);
        for (int at = start; at < buffer.Length; at++)
        {
            text.Append((char)(buffer[at] & 0x7F));
            if ((buffer[at] & 0x80) != 0) { break; }
        }

        return text.ToString();
    }

    /// <summary>
    ///  Gets a number's value.
    /// </summary>
    /// <param name="number">The number.</param>
    /// <returns>The value.</returns>
    internal static double ToDouble(ReadOnlySpan<byte> number)
    {
        if ((number[0] & 0x7F) == 0) { return 0; }
        long mantissa = 0;
        for (int index = 1; index < Size; index++)
        {
            mantissa = (mantissa * 100) + ((number[index] >> 4) * 10) + (number[index] & 0x0F);
        }

        // The point follows the first byte: the mantissa is ten digits, 100^4 times the fraction.
        double value = mantissa * Math.Pow(100, (number[0] & 0x7F) - Bias - 4);
        value = double.Parse(value.ToString("G10", CultureInfo.InvariantCulture), CultureInfo.InvariantCulture);
        return (number[0] & Sign) != 0 ? -value : value;
    }

    /// <summary>
    ///  Gets the number for a value: its digits rounded to ten, then, when the first byte holds one digit (an even
    ///  power of ten), cut to nine: the tenth digit is dropped, not rounded.
    /// </summary>
    /// <param name="value">The value.</param>
    /// <returns>The number.</returns>
    /// <exception cref="OverflowException">The value is 1E98 or more.</exception>
    internal static byte[] FromDouble(double value)
    {
        byte[] number = new byte[Size];
        if (value == 0 || double.IsNaN(value)) { return number; }
        if (double.IsInfinity(value)) { throw new OverflowException("ERROR- 11: the number is 1E98 or more."); }
        string text = Math.Abs(value).ToString("E9", CultureInfo.InvariantCulture);
        int ePosition = text.IndexOf('E', StringComparison.Ordinal);
        string digits = text[..ePosition].Replace(".", "", StringComparison.Ordinal);
        int power = int.Parse(text[(ePosition + 1)..], CultureInfo.InvariantCulture);

        // Each byte is a power of 100: an even power of ten puts the first digit in the first byte's units, an odd
        // one in its tens.
        if ((power & 1) == 0)
        {
            digits = "0" + digits[..9];
        }
        else
        {
            power--;
        }

        int exponent = (power / 2) + Bias;
        if (exponent >= TooLarge) { throw new OverflowException("ERROR- 11: the number is 1E98 or more."); }
        if (exponent < Smallest) { return number; }

        number[0] = (byte)(exponent | (value < 0 ? Sign : 0));
        for (int index = 0; index < 5; index++)
        {
            number[index + 1] = (byte)(((digits[index * 2] - '0') << 4) | (digits[(index * 2) + 1] - '0'));
        }

        return number;
    }

    /// <summary>
    ///  Rounds a number to an unsigned 16-bit integer, as FPI does.
    /// </summary>
    /// <param name="number">The number.</param>
    /// <returns>The integer, or null when the number is negative or 65536 or more.</returns>
    internal static int? ToInteger(ReadOnlySpan<byte> number)
    {
        byte[] fr0 = number[..Size].ToArray();
        if ((fr0[0] & Sign) != 0 || fr0[0] >= Bias + 3) { return null; }
        int result = 0;
        int bytes = fr0[0] - Bias;
        if (bytes >= 0)
        {
            for (int digit = 0; digit < (bytes + 1) * 2; digit++)
            {
                result = (result * 10) + TakeDigit(fr0);
                if (result > 0xFFFF) { return null; }
            }
        }

        // A carry out of the rounding is lost, as FPI loses it.
        if (TakeDigit(fr0) >= 5) { result = (result + 1) & 0xFFFF; }
        return result;
    }

    // FP_TAKE_FR0_DIGIT: shifts the mantissa a digit left and gives the digit shifted out.
    private static int TakeDigit(byte[] fr0)
    {
        int top = fr0[1] >> 4;
        for (int index = 1; index < Size - 1; index++)
        {
            fr0[index] = (byte)((fr0[index] << 4) | (fr0[index + 1] >> 4));
        }

        fr0[Size - 1] = (byte)(fr0[Size - 1] << 4);
        return top;
    }

    // FP_WRITE_DIGITS: the mantissa's ten digits, with the point after the given number of bytes.
    private static void WriteDigits(byte[] buffer, int lbuff, ReadOnlySpan<byte> number, int before)
    {
        int y = 0;
        int countdown = before;
        for (int x = 0; x < 5; x++)
        {
            if (countdown == 0) { buffer[lbuff + y++] = (byte)'.'; }
            countdown = (countdown - 1) & 0xFF;
            buffer[lbuff + y++] = (byte)('0' + (number[x + 1] >> 4));
            buffer[lbuff + y++] = (byte)('0' + (number[x + 1] & 0x0F));
        }

        // The loop falls into FP_WRITE_POINT, which writes the point after the last byte when its time has come.
        if (countdown == 0) { buffer[lbuff + y] = (byte)'.'; }
    }

    // FP_FIND_LAST_DIGIT: the last character that isn't a trailing zero or a bare point.
    private static int FindLastDigit(byte[] buffer, int lbuff)
    {
        int x = 10;
        while (true)
        {
            byte character = buffer[lbuff + x];
            if (character == '.') { return x - 1; }
            if (character != '0') { return x; }
            x--;
            if (x == 0) { return 0; }
        }
    }
}
