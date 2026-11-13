// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Cpu.I8080;

/// <summary>
///  The bits of the flags register, the low byte of PSW.
/// </summary>
/// <remarks>
///  <para>
///   On the 8080 bits 5 and 3 always read 0 and bit 1 always reads 1. The 8085 keeps the undocumented K (bit 5)
///   and V (bit 1) there; bit 3 reads 0.
///  </para>
/// </remarks>
public static class I8080Flags
{
    /// <summary>
    ///  S, the sign: bit 7 of the result.
    /// </summary>
    public const byte S = 0x80;

    /// <summary>
    ///  Z: the result is zero.
    /// </summary>
    public const byte Z = 0x40;

    /// <summary>
    ///  K (also called X5 or UI), on the 8085 only and undocumented: V exclusive-or S after 8-bit arithmetic, or
    ///  the carry out of <c>INX</c> and <c>DCX</c>.
    /// </summary>
    public const byte K = 0x20;

    /// <summary>
    ///  AC, the auxiliary carry out of bit 3.
    /// </summary>
    public const byte AC = 0x10;

    /// <summary>
    ///  P: the result has an even number of 1 bits.
    /// </summary>
    public const byte P = 0x04;

    /// <summary>
    ///  V, on the 8085 only and undocumented: two's-complement overflow, the exclusive-or of the carries into and out
    ///  of bit 7. On the 8080 this bit always reads 1.
    /// </summary>
    public const byte V = 0x02;

    /// <summary>
    ///  CY, the carry.
    /// </summary>
    public const byte CY = 0x01;

    /// <summary>
    ///  The bits the 8080 keeps; <see cref="V"/> reads 1 and the others 0.
    /// </summary>
    internal const byte Mask8080 = S | Z | AC | P | CY;

    /// <summary>
    ///  The bits the 8085 keeps.
    /// </summary>
    internal const byte Mask8085 = Mask8080 | K | V;

    /// <summary>
    ///  Gets S, Z and P for each result.
    /// </summary>
    internal static ReadOnlySpan<byte> SignZeroParity => s_signZeroParity;

    private static readonly byte[] s_signZeroParity = Create();

    private static byte[] Create()
    {
        byte[] table = new byte[256];
        for (int value = 0; value < 256; value++)
        {
            int flags = value & S;
            if (value == 0) { flags |= Z; }
            if ((System.Numerics.BitOperations.PopCount((uint)value) & 1) == 0) { flags |= P; }
            table[value] = (byte)flags;
        }

        return table;
    }
}
