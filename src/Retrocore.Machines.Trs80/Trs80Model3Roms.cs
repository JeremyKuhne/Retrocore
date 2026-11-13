// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Trs80;

/// <summary>
///  The caller-supplied ROMs of a Model III, 4 or 4P: the system ROM and the character generator.
/// </summary>
public sealed class Trs80Model3Roms
{
    /// <summary>
    ///  The Model III and 4's ROM size: 14K at <c>$0000</c>-<c>$37FF</c>.
    /// </summary>
    public const int SystemSize = 0x3800;

    /// <summary>
    ///  The Model 4P's boot ROM size: 4K at <c>$0000</c>-<c>$0FFF</c>.
    /// </summary>
    public const int BootSize = 0x1000;

    /// <summary>
    ///  The character generator's size: 256 characters of 8 rows of 8 pixels.
    /// </summary>
    public const int CharacterGeneratorSize = 0x800;

    /// <summary>
    ///  Creates the ROM set.
    /// </summary>
    /// <param name="system">The 14K Model III ROM, or the Model 4P's 4K boot ROM. It is copied.</param>
    /// <param name="characterGenerator">The 2K character generator, copied.</param>
    /// <exception cref="ArgumentException">A ROM has the wrong size.</exception>
    public Trs80Model3Roms(ReadOnlySpan<byte> system, ReadOnlySpan<byte> characterGenerator)
    {
        if (system.Length is not (SystemSize or BootSize))
        {
            throw new ArgumentException("The ROM is 14K (Model III and 4) or 4K (the Model 4P's boot ROM).", nameof(system));
        }

        if (characterGenerator.Length != CharacterGeneratorSize)
        {
            throw new ArgumentException("The character generator is 2K.", nameof(characterGenerator));
        }

        System = system.ToArray();
        CharacterGenerator = characterGenerator.ToArray();
    }

    /// <summary>
    ///  Gets the system ROM.
    /// </summary>
    public ReadOnlyMemory<byte> System { get; }

    /// <summary>
    ///  Gets the character generator.
    /// </summary>
    public ReadOnlyMemory<byte> CharacterGenerator { get; }
}
