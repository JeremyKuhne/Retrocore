// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Apple2;

namespace Retrocore.Machines.Apple3;

/// <summary>
///  The Apple III's firmware: the 4K boot ROM at <c>$F000</c>, and the built-in disk controller's sequencer PROM.
/// </summary>
public sealed class Apple3Roms
{
    /// <summary>
    ///  The boot ROM's file name in MAME's <c>apple3</c> set.
    /// </summary>
    public const string BootRomFile = "apple3.rom";

    /// <summary>
    ///  The sequencer PROM's file name in MAME's <c>apple3</c> set, the Disk II's 341-0028.
    /// </summary>
    public const string SequencerFile = "341-0028-a.rom";

    private readonly byte[] _boot;

    /// <summary>
    ///  Constructs the firmware from its images.
    /// </summary>
    /// <param name="boot">The 4K boot ROM.</param>
    /// <param name="sequencer">The 256-byte disk sequencer PROM, as the chip reads.</param>
    public Apple3Roms(ReadOnlySpan<byte> boot, ReadOnlySpan<byte> sequencer)
    {
        if (boot.Length != 0x1000)
        {
            throw new ArgumentException("The Apple III boot ROM is 4,096 bytes.", nameof(boot));
        }

        _boot = boot.ToArray();

        // The III has no slot boot ROM; its boot code is in the main ROM, so the controller's is left empty.
        Disk = new DiskIIFirmware(new byte[256], sequencer);
    }

    /// <summary>
    ///  Gets the boot ROM, mapped at <c>$F000-$FFFF</c>.
    /// </summary>
    public ReadOnlySpan<byte> Boot => _boot;

    /// <summary>
    ///  Gets the built-in disk controller's firmware.
    /// </summary>
    public DiskIIFirmware Disk { get; }

    /// <summary>
    ///  Loads the firmware from a directory holding <see cref="BootRomFile"/> and <see cref="SequencerFile"/>, as a
    ///  MAME <c>apple3</c> set unzipped does.
    /// </summary>
    /// <param name="directory">The directory.</param>
    /// <returns>The firmware.</returns>
    public static Apple3Roms LoadFromDirectory(string directory) => new(
        File.ReadAllBytes(Path.Join(directory, BootRomFile)),
        File.ReadAllBytes(Path.Join(directory, SequencerFile)));
}
