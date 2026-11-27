// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Chips;

namespace Retrocore.Machines.Commodore.Vic20;

/// <summary>
///  A VIC-20's ROMs: BASIC at <c>$C000</c>, the kernal at <c>$E000</c>, and the character ROM at <c>$8000</c>.
/// </summary>
public sealed class Vic20Roms
{
    private readonly byte[] _basic;
    private readonly byte[] _kernal;
    private readonly byte[] _characters;

    /// <summary>
    ///  Constructs the ROMs.
    /// </summary>
    /// <param name="basic">BASIC, 8K.</param>
    /// <param name="kernal">The kernal, 8K.</param>
    /// <param name="characters">The character ROM, 4K: four sets of 128 characters of 8 rows.</param>
    /// <exception cref="ArgumentException">A ROM is the wrong size.</exception>
    public Vic20Roms(ReadOnlySpan<byte> basic, ReadOnlySpan<byte> kernal, ReadOnlySpan<byte> characters)
    {
        if (basic.Length != 0x2000) { throw new ArgumentException("BASIC is 8,192 bytes.", nameof(basic)); }
        if (kernal.Length != 0x2000) { throw new ArgumentException("The kernal is 8,192 bytes.", nameof(kernal)); }
        if (characters.Length != 0x1000)
        {
            throw new ArgumentException("The character ROM is 4,096 bytes.", nameof(characters));
        }

        _basic = basic.ToArray();
        _kernal = kernal.ToArray();
        _characters = characters.ToArray();
    }

    /// <summary>
    ///  Gets BASIC.
    /// </summary>
    public ReadOnlySpan<byte> Basic => _basic;

    /// <summary>
    ///  Gets the kernal.
    /// </summary>
    public ReadOnlySpan<byte> Kernal => _kernal;

    /// <summary>
    ///  Gets the character ROM.
    /// </summary>
    public ReadOnlySpan<byte> Characters => _characters;

    /// <summary>
    ///  Gets the kernal chip's file name in MAME's sets for a video standard: 901486-06.ue12 for NTSC, 901486-07.ue12 for
    ///  PAL.
    /// </summary>
    /// <param name="standard">The standard.</param>
    /// <returns>The file name.</returns>
    public static string KernalFile(VicVideoStandard standard) =>
        standard == VicVideoStandard.Ntsc ? "901486-06.ue12" : "901486-07.ue12";

    /// <summary>
    ///  Loads the ROMs from a directory holding MAME's chip files, as its <c>vic20</c> (NTSC) or <c>vic20p</c> (PAL)
    ///  set unzipped does: BASIC 901486-01, the kernal 901486-06 or -07, and the characters 901460-03.
    /// </summary>
    /// <param name="directory">The directory.</param>
    /// <param name="standard">The video standard, which picks the kernal.</param>
    /// <returns>The ROMs.</returns>
    public static Vic20Roms LoadFromDirectory(string directory, VicVideoStandard standard) => new(
        File.ReadAllBytes(Path.Join(directory, "901486-01.ue11")),
        File.ReadAllBytes(Path.Join(directory, KernalFile(standard))),
        File.ReadAllBytes(Path.Join(directory, "901460-03.ud7")));
}
