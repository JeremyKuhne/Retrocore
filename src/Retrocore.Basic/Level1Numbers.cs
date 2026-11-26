// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Globalization;

namespace Retrocore.Basic;

/// <summary>
///  Level I BASIC's numbers, as a variable keeps them in four bytes.
/// </summary>
/// <remarks>
///  <para>
///   On Level I's FP stack a number is five bytes: a 24-bit mantissa, low byte first, whose top bit is always set,
///   so the mantissa is a fraction from 0.5 up to 1; a signed exponent, a power of two, which is $80 for zero; and a
///   byte whose bit 7 is the sign. A variable keeps four (<c>FP_POP_VAR</c>): the mantissa's two low bytes, then its
///   top seven bits under the exponent's low bit, then the sign over the exponent's other seven bits. The value is
///   the mantissa times two to the exponent.
///  </para>
/// </remarks>
internal static class Level1Numbers
{
    private const int Zero = 0x80;
    private const int MantissaBits = 24;

    /// <summary>
    ///  Reads a number.
    /// </summary>
    /// <param name="bytes">Its four bytes.</param>
    /// <returns>The value.</returns>
    internal static double Read(ReadOnlySpan<byte> bytes)
    {
        int exponent = ((bytes[3] & 0x7F) << 1) | (bytes[2] >> 7);
        if (exponent == Zero) { return 0; }
        int mantissa = 0x80_0000 | ((bytes[2] & 0x7F) << 16) | (bytes[1] << 8) | bytes[0];
        double magnitude = Math.ScaleB(mantissa, (sbyte)exponent - MantissaBits);
        return (bytes[3] & 0x80) != 0 ? -magnitude : magnitude;
    }

    /// <summary>
    ///  Writes a number, rounding to the nearest value its mantissa holds.
    /// </summary>
    /// <param name="value">The value.</param>
    /// <returns>Its four bytes.</returns>
    /// <exception cref="OverflowException">The value is too large, as HOW? says.</exception>
    internal static byte[] Write(double value)
    {
        if (double.IsNaN(value) || double.IsInfinity(value))
        {
            throw new OverflowException("HOW?: the number is too large for Level I.");
        }

        double magnitude = Math.Abs(value);
        if (magnitude == 0) { return [0, 0, 0, Zero >> 1]; }
        int exponent = (int)Math.Floor(Math.Log2(magnitude)) + 1;
        long mantissa = (long)Math.Round(Math.ScaleB(magnitude, MantissaBits - exponent));
        if (mantissa >= 1L << MantissaBits)
        {
            mantissa >>= 1;
            exponent++;
        }

        if (exponent > sbyte.MaxValue)
        {
            throw new OverflowException("HOW?: the number is too large for Level I.");
        }

        if (exponent <= sbyte.MinValue) { return [0, 0, 0, Zero >> 1]; }
        byte sign = value < 0 ? (byte)0x80 : (byte)0;
        return
        [
            (byte)mantissa,
            (byte)(mantissa >> 8),
            (byte)(((exponent & 1) << 7) | (int)((mantissa >> 16) & 0x7F)),
            (byte)(sign | ((exponent & 0xFF) >> 1))
        ];
    }

    /// <summary>
    ///  Writes a number as PRINT does, without the leading space for a positive number: in six digits, and in E
    ///  notation from 1E6 up and below 0.1 (<c>FP_PRINT_FORMAT</c>), where the other BASICs' PRINT goes on to 0.01.
    /// </summary>
    /// <param name="value">The value.</param>
    /// <returns>The text.</returns>
    internal static string Format(double value)
    {
        string text = BasicNumbers.Format(value, 6);
        if (value == 0 || Math.Abs(double.Parse(text, CultureInfo.InvariantCulture)) >= 0.1) { return text; }

        // From 0.01 up the others write .05; Level I writes 5E-02.
        string scientific = value.ToString("E5", CultureInfo.InvariantCulture);
        int e = scientific.IndexOf('E');
        string mantissa = scientific[..e].TrimEnd('0').TrimEnd('.');
        int exponent = int.Parse(scientific[(e + 1)..], CultureInfo.InvariantCulture);
        return $"{mantissa}E-{-exponent:D2}";
    }
}
