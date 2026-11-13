// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Apple1;

/// <summary>
///  Caller-supplied Apple-1 firmware: the Monitor, the terminal's character generator, and the cassette
///  interface's PROM. No Apple ROM data is bundled with the library.
/// </summary>
public sealed class Apple1Roms
{
    /// <summary>
    ///  The Monitor's size: the 256 bytes of two 256x4 PROMs, <c>$FF00</c>-<c>$FFFF</c>.
    /// </summary>
    public const int MonitorSize = 256;

    /// <summary>
    ///  The cassette interface PROM's size, <c>$C100</c>-<c>$C1FF</c>.
    /// </summary>
    public const int CassetteSize = 256;

    /// <summary>
    ///  The character generator's size: the Signetics 2513's 64 characters of eight rows, the low five bits of each
    ///  row its dots, bit 4 leftmost.
    /// </summary>
    public const int CharacterGeneratorSize = 512;

    /// <summary>
    ///  Creates the ROM set.
    /// </summary>
    /// <param name="monitor">The 256-byte Monitor, copied.</param>
    /// <param name="characterGenerator">The 512-byte character generator, copied.</param>
    /// <param name="cassette">The cassette interface's 256-byte PROM, copied, or empty without the card.</param>
    /// <exception cref="ArgumentException">A ROM has the wrong size.</exception>
    public Apple1Roms(ReadOnlySpan<byte> monitor, ReadOnlySpan<byte> characterGenerator, ReadOnlySpan<byte> cassette = default)
    {
        if (monitor.Length != MonitorSize)
        {
            throw new ArgumentException("The Monitor is 256 bytes.", nameof(monitor));
        }

        if (characterGenerator.Length != CharacterGeneratorSize)
        {
            throw new ArgumentException("The character generator is 512 bytes.", nameof(characterGenerator));
        }

        if (cassette.Length is not (0 or CassetteSize))
        {
            throw new ArgumentException("The cassette interface's PROM is 256 bytes.", nameof(cassette));
        }

        Monitor = monitor.ToArray();
        CharacterGenerator = characterGenerator.ToArray();
        Cassette = cassette.ToArray();
    }

    /// <summary>
    ///  Gets the Monitor.
    /// </summary>
    public ReadOnlyMemory<byte> Monitor { get; }

    /// <summary>
    ///  Gets the character generator.
    /// </summary>
    public ReadOnlyMemory<byte> CharacterGenerator { get; }

    /// <summary>
    ///  Gets the cassette interface's PROM, or empty when none was supplied.
    /// </summary>
    public ReadOnlyMemory<byte> Cassette { get; }
}
