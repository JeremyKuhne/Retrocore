// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Trs80;

/// <summary>
///  The caller-supplied ROMs of a Model II, 12 or 16: the boot ROM and the character generator.
/// </summary>
public sealed class Trs80Model2Roms
{
    /// <summary>
    ///  The boot ROM's size.
    /// </summary>
    public const int BootSize = 0x800;

    /// <summary>
    ///  The character generator's size: 128 characters of 16 rows of 8 pixels.
    /// </summary>
    public const int CharacterGeneratorSize = 0x800;

    /// <summary>
    ///  Creates the ROM set.
    /// </summary>
    /// <param name="boot">The 2K boot ROM, copied.</param>
    /// <param name="characterGenerator">The 2K character generator, copied.</param>
    /// <exception cref="ArgumentException">A ROM has the wrong size.</exception>
    public Trs80Model2Roms(ReadOnlySpan<byte> boot, ReadOnlySpan<byte> characterGenerator)
    {
        if (boot.Length != BootSize)
        {
            throw new ArgumentException("The boot ROM is 2K.", nameof(boot));
        }

        if (characterGenerator.Length != CharacterGeneratorSize)
        {
            throw new ArgumentException("The character generator is 2K.", nameof(characterGenerator));
        }

        Boot = boot.ToArray();
        CharacterGenerator = characterGenerator.ToArray();
    }

    /// <summary>
    ///  Gets the boot ROM.
    /// </summary>
    public ReadOnlyMemory<byte> Boot { get; }

    /// <summary>
    ///  Gets the character generator.
    /// </summary>
    public ReadOnlyMemory<byte> CharacterGenerator { get; }
}
