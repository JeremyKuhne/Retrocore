// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Security.Cryptography;

namespace Retrocore.Machines.Trs80Model100;

/// <summary>
///  The ROMs a Model 100 runs: its 32 KB main ROM, which the user supplies, and an option ROM, if one is fitted.
/// </summary>
/// <remarks>
///  <para>
///   The main ROM holds BASIC, TEXT, TELCOM, ADDRSS and SCHEDL. The dumps known here are MAME's: the US Model 100's
///   <c>m100rom.m12</c> (CRC32 <c>730a3611</c>) and the US Tandy 102's <c>m102rom.m12</c> (<c>08e9f89c</c>). Other
///   32 KB images, such as the regional ROMs and Y2K-patched ones, run as well, as a Model 100 unless told otherwise.
///  </para>
/// </remarks>
public sealed class Trs80Model100Roms
{
    /// <summary>
    ///  The size of the main ROM, and the most an option ROM can be.
    /// </summary>
    public const int RomSize = 0x8000;

    /// <summary>
    ///  The SHA-1 of the US Model 100's ROM, MAME's <c>m100rom.m12</c>.
    /// </summary>
    public const string Model100Sha1 = "094DBC4AC5A4EA5CDF51A1AC581A40A9622BB25D";

    /// <summary>
    ///  The SHA-1 of the US Tandy 102's ROM, MAME's <c>m102rom.m12</c>.
    /// </summary>
    public const string Tandy102Sha1 = "B6EDE7735A361C80419F4C9C0E36E7D480C36D11";

    /// <summary>
    ///  Holds the ROMs.
    /// </summary>
    /// <param name="main">The 32 KB main ROM.</param>
    /// <param name="option">An option ROM of up to 32 KB, or null for an empty socket.</param>
    /// <exception cref="ArgumentException">A ROM is the wrong size.</exception>
    public Trs80Model100Roms(byte[] main, byte[]? option = null)
    {
        ArgumentNullException.ThrowIfNull(main);
        if (main.Length != RomSize)
        {
            throw new ArgumentException($"The main ROM must be {RomSize} bytes.", nameof(main));
        }

        if (option is { Length: 0 or > RomSize })
        {
            throw new ArgumentException($"An option ROM must be 1 to {RomSize} bytes.", nameof(option));
        }

        Main = main;
        Option = option;
    }

    /// <summary>
    ///  Gets the main ROM.
    /// </summary>
    public byte[] Main { get; }

    /// <summary>
    ///  Gets the option ROM, or null for an empty socket.
    /// </summary>
    public byte[]? Option { get; }

    /// <summary>
    ///  Gets which model a main ROM is a known dump of.
    /// </summary>
    /// <param name="rom">The ROM.</param>
    /// <returns>The model, or null for a ROM not known here.</returns>
    public static Trs80Model100Variant? Identify(ReadOnlySpan<byte> rom) => Convert.ToHexString(SHA1.HashData(rom)) switch
    {
        Model100Sha1 => Trs80Model100Variant.Model100,
        Tandy102Sha1 => Trs80Model100Variant.Tandy102,
        _ => null
    };
}
