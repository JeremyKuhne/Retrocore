// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Trs80;

/// <summary>
///  The caller-supplied ROMs: BASIC and the character generator.
/// </summary>
public sealed class Trs80Roms
{
    /// <summary>
    ///  The character generator's size: 128 characters of 8 rows, the low 6 bits of each a row of pixels.
    /// </summary>
    public const int CharacterGeneratorSize = 1024;

    /// <summary>
    ///  Creates the ROM set.
    /// </summary>
    /// <param name="system">BASIC: 12K for Level II, 4K for Level I. It is copied.</param>
    /// <param name="characterGenerator">The 1K character generator, copied.</param>
    /// <exception cref="ArgumentException">A ROM has the wrong size.</exception>
    public Trs80Roms(ReadOnlySpan<byte> system, ReadOnlySpan<byte> characterGenerator)
    {
        if (system.Length is not (0x1000 or 0x3000))
        {
            throw new ArgumentException("BASIC is 4K (Level I) or 12K (Level II).", nameof(system));
        }

        if (characterGenerator.Length != CharacterGeneratorSize)
        {
            throw new ArgumentException("The character generator is 1K.", nameof(characterGenerator));
        }

        System = system.ToArray();
        CharacterGenerator = characterGenerator.ToArray();
    }

    /// <summary>
    ///  Gets BASIC.
    /// </summary>
    public ReadOnlyMemory<byte> System { get; }

    /// <summary>
    ///  Gets the character generator.
    /// </summary>
    public ReadOnlyMemory<byte> CharacterGenerator { get; }
}
