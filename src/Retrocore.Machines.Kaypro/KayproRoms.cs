// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Kaypro;

/// <summary>
///  The Kaypro II's ROMs: the 2K monitor ROM and the 2K character generator.
/// </summary>
public sealed class KayproRoms
{
    /// <summary>
    ///  The monitor ROM's size.
    /// </summary>
    public const int MonitorSize = 0x800;

    /// <summary>
    ///  The character generator's size: 256 characters of 8 scanlines.
    /// </summary>
    public const int CharacterGeneratorSize = 0x800;

    /// <summary>
    ///  Creates the ROM set.
    /// </summary>
    /// <param name="monitor">The 2K monitor ROM, copied.</param>
    /// <param name="characterGenerator">The 2K character generator, copied.</param>
    /// <exception cref="ArgumentException">A ROM has the wrong size.</exception>
    public KayproRoms(ReadOnlySpan<byte> monitor, ReadOnlySpan<byte> characterGenerator)
    {
        if (monitor.Length != MonitorSize)
        {
            throw new ArgumentException("The monitor ROM is 2K.", nameof(monitor));
        }

        if (characterGenerator.Length != CharacterGeneratorSize)
        {
            throw new ArgumentException("The character generator is 2K.", nameof(characterGenerator));
        }

        Monitor = monitor.ToArray();
        CharacterGenerator = characterGenerator.ToArray();
    }

    /// <summary>
    ///  Gets the monitor ROM.
    /// </summary>
    public ReadOnlyMemory<byte> Monitor { get; }

    /// <summary>
    ///  Gets the character generator.
    /// </summary>
    public ReadOnlyMemory<byte> CharacterGenerator { get; }
}
