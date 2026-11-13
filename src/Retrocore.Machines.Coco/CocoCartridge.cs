// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Coco;

/// <summary>
///  A ROM pack in the cartridge port: up to 16 KB at <c>$C000-$FEFF</c>, which starts itself by tying the CART line
///  to the Q clock, so PIA 1's CB1 sees edges and Color BASIC's FIRQ handler jumps to <c>$C000</c>.
/// </summary>
public sealed class CocoCartridge
{
    /// <summary>
    ///  The most bytes the port maps.
    /// </summary>
    public const int MaximumSize = 0x3F00;

    private readonly byte[] _rom;

    /// <summary>
    ///  Creates a ROM pack from a <c>.ccc</c> or <c>.rom</c> image.
    /// </summary>
    /// <param name="rom">The image; one smaller than 16 KB repeats across the window.</param>
    /// <param name="autostart">Whether the pack ties CART to Q, as game packs do.</param>
    /// <exception cref="ArgumentException">The image is empty or larger than 16 KB.</exception>
    public CocoCartridge(ReadOnlySpan<byte> rom, bool autostart = true)
    {
        if (rom.IsEmpty || rom.Length > 0x4000)
        {
            throw new ArgumentException("A ROM pack holds 1 to 16 KB.", nameof(rom));
        }

        _rom = rom.ToArray();
        Autostart = autostart;
    }

    /// <summary>
    ///  Gets whether the pack starts itself through the CART line.
    /// </summary>
    public bool Autostart { get; }

    /// <summary>
    ///  Gets the image's size.
    /// </summary>
    public int Size => _rom.Length;

    /// <summary>
    ///  Gets the image, for the debugger to match against a source.
    /// </summary>
    internal ReadOnlySpan<byte> Bytes => _rom;

    /// <summary>
    ///  Reads the pack at an offset from <c>$C000</c>.
    /// </summary>
    /// <param name="offset">The offset.</param>
    /// <returns>The byte.</returns>
    internal byte Read(int offset) => _rom[offset % _rom.Length];
}
