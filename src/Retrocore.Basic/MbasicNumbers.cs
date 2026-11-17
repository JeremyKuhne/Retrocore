// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Numerics;

namespace Retrocore.Basic;

/// <summary>
///  MBASIC's numbers in a crunched line: FIN's reading of a typed number, which picks its type, and FOUT's writing of
///  one for LIST.
/// </summary>
/// <remarks>
///  <para>
///   A number without a point, exponent or type character is an integer up to 32767, a single to seven digits and a
///   double past that; a point or <c>E</c> makes it a single, a <c>D</c> a double, and <c>%</c>, <c>!</c> and
///   <c>#</c> say the type outright. Spaces between its characters are skipped, as CHRGET skips them.
///  </para>
///  <para>
///   A single matches FIN's bits: the digits, then a multiplication or division by ten for each power, each rounded.
///   A double that needs scaling by powers of ten can differ from FIN's in its last bits, as BASIC-80's
///   double-precision division rounds in its own way, which this does not follow yet.
///  </para>
/// </remarks>
internal static class MbasicNumbers
{
    private const byte ByteConstant = 0x0F;
    private const byte FirstDigit = 0x11;
    private const byte IntegerConstant = 0x1C;
    private const byte SingleConstant = 0x1D;
    private const byte DoubleConstant = 0x1F;
    private const int SingleDigits = 7;

    /// <summary>
    ///  Reads a typed number as FIN does and returns its crunched bytes: its token and value.
    /// </summary>
    /// <param name="line">The line's characters.</param>
    /// <param name="x">The number's first character; left after its last.</param>
    /// <returns>The bytes.</returns>
    /// <exception cref="FormatException">The number is too large for its type.</exception>
    internal static byte[] Crunch(int[] line, ref int x)
    {
        BigInteger digits = BigInteger.Zero;
        int significant = 0, scale = 0, exponent = 0;
        bool point = false, exponentSeen = false, exponentNegative = false;
        char type = '\0';
        bool typed = false;
        int end = x;
        while (true)
        {
            int unit = At(line, x);
            if (unit == ' ')
            {
                x++;
                continue;
            }

            int upper = unit is >= 'a' and <= 'z' ? unit & 0x5F : unit;
            if (!exponentSeen && unit is >= '0' and <= '9')
            {
                digits = (digits * 10) + (unit - '0');
                if (!digits.IsZero) { significant++; }
                if (point) { scale--; }
            }
            else if (!exponentSeen && !point && unit == '.')
            {
                point = true;
            }
            else if (!exponentSeen && upper is 'E' or 'D')
            {
                exponentSeen = true;
                if (upper == 'D') { type = '#'; }
                else if (type == '\0') { type = '!'; }
                x++;
                end = x;
                while (At(line, x) == ' ') { x++; }
                if (At(line, x) is '+' or '-')
                {
                    exponentNegative = At(line, x) == '-';
                    x++;
                    end = x;
                }

                continue;
            }
            else if (exponentSeen && unit is >= '0' and <= '9')
            {
                exponent = Math.Min((exponent * 10) + (unit - '0'), 1000);
            }
            else if (unit is '%' or '!' or '#')
            {
                type = (char)unit;
                typed = true;
                x++;
                end = x;
                break;
            }
            else
            {
                break;
            }

            x++;
            end = x;
        }

        x = end;
        int power = scale + (exponentNegative ? -exponent : exponent);
        if (type == '\0')
        {
            type = point ? '!' : digits <= 32767 && power >= 0 ? '%' : '!';
        }

        if (type == '!' && significant > SingleDigits && !typed) { type = '#'; }

        if (type == '%')
        {
            BigInteger whole = power >= 0 ? digits * BigInteger.Pow(10, power) : digits / BigInteger.Pow(10, -power);
            if (whole > 32767) { throw new FormatException("?Overflow: an integer is at most 32767."); }
            int value = (int)whole;
            return value switch
            {
                < 10 => [(byte)(FirstDigit + value)],
                < 256 => [ByteConstant, (byte)value],
                _ => [IntegerConstant, (byte)value, (byte)(value >> 8)]
            };
        }

        int length = type == '#' ? 8 : 4;
        byte[] bytes = new byte[length + 1];
        bytes[0] = type == '#' ? DoubleConstant : SingleConstant;
        Mbf(digits, power, bytes.AsSpan(1));
        return bytes;
    }

    /// <summary>
    ///  Reads an <c>&amp;H</c> or <c>&amp;O</c> constant's digits.
    /// </summary>
    /// <param name="line">The line's characters.</param>
    /// <param name="x">The first digit; left after the last.</param>
    /// <param name="radix">16 or 8.</param>
    /// <returns>The value.</returns>
    /// <exception cref="FormatException">The value does not fit in 16 bits.</exception>
    internal static int Radix(int[] line, ref int x, int radix)
    {
        int value = 0;
        while (true)
        {
            int unit = At(line, x);
            int upper = unit is >= 'a' and <= 'z' ? unit & 0x5F : unit;
            int digit = upper switch
            {
                >= '0' and <= '7' => upper - '0',
                '8' or '9' when radix == 16 => upper - '0',
                >= 'A' and <= 'F' when radix == 16 => upper - 'A' + 10,
                _ => -1
            };

            if (digit < 0) { return value; }
            value = (value * radix) + digit;
            if (value > 0xFFFF) { throw new FormatException("?Overflow: a constant is at most 16 bits."); }
            x++;
        }
    }

    // Writes digits times ten to a power in Microsoft's format, exponent last, as FIN makes it: the digits, then one
    // multiplication or division by ten for each power, each rounded to the format's bits as FMULT and FDIV round
    // (half up).
    private static void Mbf(BigInteger digits, int power, Span<byte> bytes)
    {
        bytes.Clear();
        if (digits.IsZero) { return; }
        int bits = 8 * (bytes.Length - 1);
        (BigInteger numerator, BigInteger denominator, int exponent) = Round(digits, BigInteger.One, bits);
        for (int step = 0; step < Math.Abs(power); step++)
        {
            (numerator, denominator, exponent) = power > 0
                ? Round(numerator * 10, denominator, bits)
                : Round(numerator, denominator * 10, bits);
        }

        if (exponent + 128 > 255) { throw new FormatException("?Overflow: the number is too large."); }
        if (exponent + 128 <= 0) { return; }

        // The value is now mantissa * 2^(exponent - bits), with the mantissa a whole number of bits.
        BigInteger mantissa = Mantissa(numerator, denominator, exponent, bits);
        for (int index = 0; index < bytes.Length - 1; index++)
        {
            bytes[index] = (byte)(mantissa & 0xFF);
            mantissa >>= 8;
        }

        bytes[^2] &= 0x7F;
        bytes[^1] = (byte)(exponent + 128);
    }

    // Rounds numerator / denominator to a mantissa of the given bits, half up, returning it as a fraction and its
    // binary exponent e, with 2^(e-1) <= value < 2^e.
    private static (BigInteger Numerator, BigInteger Denominator, int Exponent) Round(
        BigInteger numerator,
        BigInteger denominator,
        int bits)
    {
        int exponent = (int)(numerator.GetBitLength() - denominator.GetBitLength());
        while (Compare(numerator, denominator, exponent) >= 0) { exponent++; }
        while (Compare(numerator, denominator, exponent - 1) < 0) { exponent--; }
        BigInteger mantissa = Mantissa(numerator, denominator, exponent, bits, out bool half);
        if (half) { mantissa++; }
        if (mantissa.GetBitLength() > bits)
        {
            mantissa >>= 1;
            exponent++;
        }

        int shift = exponent - bits;
        return shift >= 0
            ? (mantissa << shift, BigInteger.One, exponent)
            : (mantissa, BigInteger.One << -shift, exponent);
    }

    // The value's top bits as a whole number, truncated.
    private static BigInteger Mantissa(BigInteger numerator, BigInteger denominator, int exponent, int bits) =>
        Mantissa(numerator, denominator, exponent, bits, out _);

    private static BigInteger Mantissa(BigInteger numerator, BigInteger denominator, int exponent, int bits, out bool half)
    {
        int shift = bits - exponent;
        if (shift >= 0) { numerator <<= shift; } else { denominator <<= -shift; }
        BigInteger mantissa = BigInteger.DivRem(numerator, denominator, out BigInteger remainder);
        half = remainder * 2 >= denominator;
        return mantissa;
    }

    // Compares numerator / denominator with 2^power.
    private static int Compare(BigInteger numerator, BigInteger denominator, int power) => power >= 0
        ? numerator.CompareTo(denominator << power)
        : (numerator << -power).CompareTo(denominator);

    private static int At(int[] line, int index) => index < line.Length ? line[index] : 0;
}
