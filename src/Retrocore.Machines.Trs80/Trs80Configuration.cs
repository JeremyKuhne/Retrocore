// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Trs80;

/// <summary>
///  How a Model I is built: its ROM, memory and the options fitted to it.
/// </summary>
public sealed record Trs80Configuration
{
    /// <summary>
    ///  Gets the BASIC in ROM.
    /// </summary>
    public Trs80Rom Rom { get; init; } = Trs80Rom.Level2;

    /// <summary>
    ///  Gets the RAM in kilobytes from <c>$4000</c>: 4 or 16 in the keyboard unit, 32 or 48 with the Expansion
    ///  Interface.
    /// </summary>
    public int RamKilobytes { get; init; } = 48;

    /// <summary>
    ///  Gets whether the Expansion Interface is attached, with the 40 Hz clock, the disk controller and the
    ///  printer port. More than 16K of RAM needs it.
    /// </summary>
    public bool ExpansionInterface { get; init; } = true;

    /// <summary>
    ///  Gets whether the Expansion Interface has its disk controller. Without one, <c>$37EC</c> reads
    ///  <c>$FF</c> and Level II starts BASIC instead of waiting for a disk.
    /// </summary>
    public bool DiskController { get; init; } = true;

    /// <summary>
    ///  Gets whether the lowercase modification adds the seventh video RAM bit and a lowercase character set.
    /// </summary>
    public bool LowercaseModification { get; init; }

    /// <summary>
    ///  Gets whether the scanned picture shows "snow": a character the beam draws while the CPU reads or writes
    ///  video RAM shows the CPU's byte for that scanline, as on a Model I without a snow fix.
    /// </summary>
    public bool VideoSnow { get; init; }

    /// <summary>
    ///  Gets the double-density adapter fitted to the disk controller.
    /// </summary>
    public Trs80Doubler Doubler { get; init; }

    /// <summary>
    ///  Checks the configuration.
    /// </summary>
    /// <exception cref="ArgumentException">The RAM size is not one a Model I has, or needs the interface.</exception>
    internal void Validate()
    {
        if (RamKilobytes is not (4 or 16 or 32 or 48))
        {
            throw new ArgumentException("A Model I has 4, 16, 32 or 48K of RAM.");
        }

        if (RamKilobytes > 16 && !ExpansionInterface)
        {
            throw new ArgumentException("More than 16K of RAM needs the Expansion Interface.");
        }

        if (!Enum.IsDefined(Rom) || !Enum.IsDefined(Doubler))
        {
            throw new ArgumentException("The ROM or doubler is not defined.");
        }
    }
}
