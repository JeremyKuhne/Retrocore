// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Globalization;
using System.Numerics;
using System.Text.RegularExpressions;

namespace Retrocore.Basic;

/// <summary>
///  The interpreters' number formats: Microsoft's binary floating point, as AppleSoft's five bytes and Level II's
///  four (single) and eight (double), and how PRINT writes numbers.
/// </summary>
/// <remarks>
///  <para>
///   A float is an exponent byte, biased by 128 with 0 meaning zero, and a mantissa from 0.5 to just under 1 whose
///   top bit, always 1, holds the sign instead. AppleSoft stores the exponent first and the mantissa from its top
///   byte; Level II stores the mantissa from its lowest byte and the exponent last.
///  </para>
/// </remarks>
public static partial class BasicNumbers
{
    private const int Bias = 128;
    private const byte SignBit = 0x80;

    /// <summary>
    ///  Reads a float.
    /// </summary>
    /// <param name="bytes">Its bytes in memory order.</param>
    /// <param name="exponentFirst">Whether the exponent is the first byte (AppleSoft) or the last (Level II).</param>
    /// <returns>The value.</returns>
    public static double ReadFloat(ReadOnlySpan<byte> bytes, bool exponentFirst)
    {
        int mantissaBytes = bytes.Length - 1;
        byte exponent = exponentFirst ? bytes[0] : bytes[^1];
        if (exponent == 0) { return 0; }
        double mantissa = 0;
        bool negative = false;
        for (int index = 0; index < mantissaBytes; index++)
        {
            // From the top byte down.
            byte value = exponentFirst ? bytes[1 + index] : bytes[mantissaBytes - 1 - index];
            if (index == 0)
            {
                negative = (value & SignBit) != 0;
                value |= SignBit;
            }

            mantissa = mantissa * 256 + value;
        }

        double result = Math.ScaleB(mantissa, exponent - Bias - (8 * mantissaBytes));
        return negative ? -result : result;
    }

    /// <summary>
    ///  Writes a float, rounding to the nearest value its mantissa holds.
    /// </summary>
    /// <param name="value">The value.</param>
    /// <param name="length">The float's bytes: 5 (AppleSoft), 4 (Level II single) or 8 (Level II double).</param>
    /// <param name="exponentFirst">Whether the exponent is the first byte (AppleSoft) or the last (Level II).</param>
    /// <returns>The bytes in memory order.</returns>
    /// <exception cref="OverflowException">The value is too large for the format.</exception>
    public static byte[] WriteFloat(double value, int length, bool exponentFirst)
    {
        if (value == 0 || double.IsNaN(value)) { return new byte[length]; }
        int bits = 8 * (length - 1);
        bool negative = value < 0;
        double magnitude = Math.Abs(value);
        int exponent = Math.ILogB(magnitude) + 1;

        // The mantissa as a whole number of bits, from 0.5 up; rounding can carry into another bit.
        double scaled = Math.Round(Math.ScaleB(magnitude, bits - exponent), MidpointRounding.AwayFromZero);
        if (scaled >= Math.ScaleB(1, bits))
        {
            scaled = Math.ScaleB(scaled, -1);
            exponent++;
        }

        return Pack(negative, exponent, (UInt128)scaled, length, exponentFirst);
    }

    /// <summary>
    ///  Writes a number as BASIC writes it, such as <c>9007199254740993</c> or <c>-2.5E-3</c>, as a float, exactly:
    ///  the decimal is rounded once, to the nearest value the mantissa holds, so Level II's double keeps all its 56
    ///  bits, which a <see cref="double"/> would round to 53 first.
    /// </summary>
    /// <param name="text">The number, with an optional sign, point and exponent with E (or D).</param>
    /// <param name="length">The float's bytes: 4, 5 or 8.</param>
    /// <param name="exponentFirst">Whether the exponent is the first byte (AppleSoft) or the last (Level II).</param>
    /// <returns>The bytes in memory order.</returns>
    /// <exception cref="FormatException">The text is not a number.</exception>
    /// <exception cref="OverflowException">The value is too large for the format.</exception>
    public static byte[] WriteFloat(string text, int length, bool exponentFirst)
    {
        ArgumentNullException.ThrowIfNull(text);
        string normalized = text.Trim().Replace('D', 'E').Replace('d', 'E').TrimEnd('!', '#', '%');
        Match match = DecimalNumber().Match(normalized);
        if (!match.Success || match.Groups[2].Length + match.Groups[3].Length == 0)
        {
            throw new FormatException($"{text} is not a number.");
        }

        string significant = (match.Groups[2].Value + match.Groups[3].Value).TrimStart('0');
        if (significant.Length == 0) { return new byte[length]; }
        BigInteger digits = BigInteger.Parse(significant, CultureInfo.InvariantCulture);

        // The value is digits times ten to the scale; far past any format's range, it is too large, or zero.
        int written = match.Groups[4].Success ? int.Parse(match.Groups[4].Value, CultureInfo.InvariantCulture) : 0;
        int scale = written - match.Groups[3].Length;
        int magnitude = significant.Length + scale;
        if (magnitude > 400)
        {
            throw new OverflowException("?OVERFLOW: the value is too large for BASIC.");
        }

        if (magnitude < -400) { return new byte[length]; }
        BigInteger numerator = scale >= 0 ? digits * BigInteger.Pow(10, scale) : digits;
        BigInteger denominator = scale >= 0 ? BigInteger.One : BigInteger.Pow(10, -scale);

        // The binary exponent: the value is from 2^(exponent - 1) up to 2^exponent.
        int exponent = (int)(numerator.GetBitLength() - denominator.GetBitLength());
        while (Compare(numerator, denominator, exponent) >= 0) { exponent++; }
        while (Compare(numerator, denominator, exponent - 1) < 0) { exponent--; }

        int bits = 8 * (length - 1);
        int shift = bits - exponent;
        BigInteger scaledNumerator = shift >= 0 ? numerator << shift : numerator;
        BigInteger scaledDenominator = shift >= 0 ? denominator : denominator << -shift;
        BigInteger mantissa = BigInteger.DivRem(scaledNumerator, scaledDenominator, out BigInteger remainder);
        if (remainder * 2 >= scaledDenominator) { mantissa++; }
        if (mantissa >= BigInteger.One << bits)
        {
            mantissa >>= 1;
            exponent++;
        }

        return Pack(match.Groups[1].Value == "-", exponent, (UInt128)mantissa, length, exponentFirst);
    }

    // Compares numerator / denominator with 2^power.
    private static int Compare(BigInteger numerator, BigInteger denominator, int power) =>
        power >= 0 ? numerator.CompareTo(denominator << power) : (numerator << -power).CompareTo(denominator);

    // Lays out a float: the exponent byte, biased, and the mantissa from 0.5 up, whose top bit holds the sign.
    private static byte[] Pack(bool negative, int exponent, UInt128 mantissa, int length, bool exponentFirst)
    {
        byte[] bytes = new byte[length];
        int mantissaBytes = length - 1;
        if (exponent + Bias > 255) { throw new OverflowException("?OVERFLOW: the value is too large for BASIC."); }
        if (exponent + Bias <= 0) { return bytes; }
        for (int index = mantissaBytes - 1; index >= 0; index--)
        {
            byte part = (byte)(mantissa & 0xFF);
            mantissa >>= 8;
            if (index == 0) { part = negative ? (byte)(part | SignBit) : (byte)(part & ~SignBit); }
            bytes[exponentFirst ? 1 + index : mantissaBytes - 1 - index] = part;
        }

        bytes[exponentFirst ? 0 : length - 1] = (byte)(exponent + Bias);
        return bytes;
    }

    // A decimal number: its sign, whole digits, fraction digits and exponent.
    [GeneratedRegex(@"^([-+]?)([0-9]*)(?:\.([0-9]*))?(?:[eE]([-+]?[0-9]{1,6}))?$")]
    private static partial Regex DecimalNumber();

    /// <summary>
    ///  Writes a number as PRINT does, without the leading space for a positive number: up to the given significant
    ///  digits, no zero before the point, and exponent form outside the range PRINT writes plainly.
    /// </summary>
    /// <param name="value">The number.</param>
    /// <param name="digits">The significant digits: 9 for AppleSoft, 6 for Level II single, 16 for double.</param>
    /// <returns>The text, such as <c>.25</c>, <c>-3</c> or <c>1E+10</c>.</returns>
    public static string Format(double value, int digits)
    {
        if (value == 0) { return "0"; }
        string scientific = value.ToString($"E{digits - 1}", CultureInfo.InvariantCulture);
        double rounded = double.Parse(scientific, CultureInfo.InvariantCulture);
        double magnitude = Math.Abs(rounded);
        int exponent = (int)Math.Floor(Math.Log10(magnitude));
        string sign = rounded < 0 ? "-" : "";
        if (exponent >= digits || exponent < -2)
        {
            double mantissa = magnitude / Math.Pow(10, exponent);
            string fraction = Trim(mantissa.ToString($"F{digits - 1}", CultureInfo.InvariantCulture));
            return $"{sign}{fraction}E{(exponent < 0 ? "-" : "+")}{Math.Abs(exponent):D2}";
        }

        string plain = Trim(magnitude.ToString($"F{Math.Max(0, digits - 1 - exponent)}", CultureInfo.InvariantCulture));
        return sign + (plain.StartsWith("0.", StringComparison.Ordinal) ? plain[1..] : plain);
    }

    /// <summary>
    ///  Reads a number as BASIC writes it: digits, a point, and an exponent with E (or D for Level II double).
    /// </summary>
    /// <param name="text">The text, with an optional sign.</param>
    /// <param name="value">The number.</param>
    /// <returns>Whether the text is a number.</returns>
    public static bool TryParse(string text, out double value)
    {
        ArgumentNullException.ThrowIfNull(text);
        string normalized = text.Trim().Replace('D', 'E').Replace('d', 'E').TrimEnd('!', '#', '%');
        return double.TryParse(normalized, NumberStyles.Float, CultureInfo.InvariantCulture, out value);
    }

    private static string Trim(string text) =>
        text.Contains('.', StringComparison.Ordinal) ? text.TrimEnd('0').TrimEnd('.') : text;
}
