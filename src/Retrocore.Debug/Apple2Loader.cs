// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Apple2;
using Retrocore.Media;

namespace Retrocore.Debug;

/// <summary>
///  Builds a IIe from its ROMs, dumped or assembled from the SDK, and its disk images.
/// </summary>
internal static class Apple2Loader
{
    /// <summary>
    ///  Constructs a machine from explicit ROMs and disk paths.
    /// </summary>
    /// <param name="model">The IIe model.</param>
    /// <param name="roms">The system and video ROMs.</param>
    /// <param name="diskPath">An optional ProDOS-order image.</param>
    /// <param name="diskFirmware">External P5/P6 firmware to select native Disk II rather than slot seven.</param>
    /// <returns>The initialized machine.</returns>
    internal static Apple2Machine Load(Apple2Model model, Apple2Roms roms, string? diskPath, DiskIIFirmware? diskFirmware = null)
    {
        if (diskPath is not null && diskFirmware is null && !Path.GetExtension(diskPath).Equals(".po", StringComparison.OrdinalIgnoreCase))
        {
            throw new ArgumentException("Native floppy images require externally supplied Disk II boot and sequencer ROMs.");
        }

        Apple2Machine machine = new(
            model,
            roms,
            diskPath is null || diskFirmware is not null ? null : Disk(diskPath));

        if (diskFirmware is not null)
        {
            machine.Bus.InstallDiskII(slot: 6, diskFirmware);
            if (diskPath is not null) { Insert(machine.Drives[0], Path.GetFullPath(diskPath)); }
        }
        else if (machine.BlockStorage is { } storage && diskPath is not null)
        {
            storage.Label = Path.GetFullPath(diskPath);
        }

        return machine;
    }

    /// <summary>
    ///  Inserts a WOZ image, or a DOS- or ProDOS-order or 13-sector (<c>.d13</c>) sector image converted to a WOZ
    ///  disk, in a Disk II drive.
    /// </summary>
    /// <param name="drive">The drive.</param>
    /// <param name="path">The image's full path.</param>
    internal static void Insert(Apple2FloppyDrive drive, string path)
    {
        byte[] data = File.ReadAllBytes(path);
        string extension = Path.GetExtension(path).TrimStart('.').ToUpperInvariant();
        WozDisk disk = extension switch
        {
            "WOZ" => WozDisk.Load(data),
            "D13" => SectorDiskConverter.ConvertThirteenSector(data),
            _ => SectorDiskConverter.Convert(data, extension == "PO")
        };

        drive.Insert(disk, path, extension.Length == 0 ? "DSK" : extension);
    }

    /// <summary>
    ///  Inserts a 3.5-inch disk image (<c>.po</c>, <c>.2mg</c>, <c>.hdv</c>, <c>.img</c> or <c>.dsk</c>) in a 3.5
    ///  drive.
    /// </summary>
    /// <param name="drive">The drive.</param>
    /// <param name="path">The image's full path.</param>
    internal static void Insert(Apple2Disk35Drive drive, string path)
    {
        Disk35Disk disk = Disk35Disk.Load(File.ReadAllBytes(path));
        string extension = Path.GetExtension(path).TrimStart('.').ToUpperInvariant();
        drive.Insert(disk, path, extension.Length == 0 ? "PO" : extension);
    }

    // The most blocks a ProDOS volume, and the slot 7 device's 16-bit block count, can hold: 32 MiB.
    private const int MaximumBlocks = 65535;

    /// <summary>
    ///  Reads an unadorned ProDOS-order image, which is its 512-byte blocks in order with no header.
    /// </summary>
    /// <param name="path">The image.</param>
    /// <returns>The block device.</returns>
    /// <exception cref="InvalidDataException">The file is not a whole number of blocks, or holds too many.</exception>
    private static MemoryBlockDevice Disk(string path)
    {
        long length = new FileInfo(path).Length;
        if (length == 0 || length % 512 != 0 || length / 512 > MaximumBlocks)
        {
            throw new InvalidDataException(
                $"{Path.GetFileName(path)} is not a ProDOS-order block image: it must be 1 to {MaximumBlocks} whole 512-byte blocks.");
        }

        return new MemoryBlockDevice(File.ReadAllBytes(path));
    }
}
