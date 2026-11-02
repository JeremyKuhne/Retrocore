// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Cpu.Z80;

/// <summary>
///  The flag bits and the flag tables the core computes results with.
/// </summary>
internal static class Z80Flags
{
    /// <summary>
    ///  The carry.
    /// </summary>
    internal const byte C = 0x01;

    /// <summary>
    ///  Subtract, for <c>DAA</c>.
    /// </summary>
    internal const byte N = 0x02;

    /// <summary>
    ///  Parity or overflow.
    /// </summary>
    internal const byte PV = 0x04;

    /// <summary>
    ///  Undocumented bit 3, X.
    /// </summary>
    internal const byte X = 0x08;

    /// <summary>
    ///  Half carry.
    /// </summary>
    internal const byte H = 0x10;

    /// <summary>
    ///  Undocumented bit 5, Y.
    /// </summary>
    internal const byte Y = 0x20;

    /// <summary>
    ///  Zero.
    /// </summary>
    internal const byte Z = 0x40;

    /// <summary>
    ///  Sign.
    /// </summary>
    internal const byte S = 0x80;

    /// <summary>
    ///  The undocumented bits together.
    /// </summary>
    internal const byte XY = X | Y;

    /// <summary>
    ///  Sign, zero, X and Y of each value.
    /// </summary>
    internal static readonly byte[] SignZero = Create(parity: false);

    /// <summary>
    ///  Sign, zero, X, Y and even parity of each value.
    /// </summary>
    internal static readonly byte[] SignZeroParity = Create(parity: true);

    private static byte[] Create(bool parity)
    {
        byte[] table = new byte[256];
        for (int value = 0; value < table.Length; value++)
        {
            int flags = (value & (S | XY)) | (value == 0 ? Z : 0);
            if (parity && (System.Numerics.BitOperations.PopCount((uint)value) & 1) == 0) { flags |= PV; }
            table[value] = (byte)flags;
        }

        return table;
    }
}
