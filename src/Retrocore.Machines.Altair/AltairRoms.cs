// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Altair;

/// <summary>
///  The Altair's boot PROMs: MITS's disk boot loader (DBL) on a PROM board at $FF00, and its multi-boot loader (MBL),
///  which loads tapes, at $FE00. Either may be left out.
/// </summary>
public sealed record AltairRoms
{
    /// <summary>
    ///  The size of each PROM.
    /// </summary>
    public const int PromSize = 256;

    /// <summary>
    ///  Gets the DBL PROM's 256 bytes, or null without it.
    /// </summary>
    public byte[]? Dbl
    {
        get;
        init => field = Check(value, nameof(Dbl));
    }

    /// <summary>
    ///  Gets the MBL PROM's 256 bytes, or null without it.
    /// </summary>
    public byte[]? Mbl
    {
        get;
        init => field = Check(value, nameof(Mbl));
    }

    private static byte[]? Check(byte[]? value, string name) => value is null || value.Length == PromSize
        ? value
        : throw new ArgumentException($"The {name} PROM is {PromSize} bytes, not {value.Length}.", name);
}
