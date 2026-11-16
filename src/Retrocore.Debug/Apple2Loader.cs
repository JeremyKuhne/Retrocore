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
    /// <param name="diskPath">
    ///  An optional ProDOS-order image for slot 7 (<c>.po</c>, <c>.hdv</c> or <c>.2mg</c>), or a Disk II image with
    ///  <paramref name="diskFirmware"/>.
    /// </param>
    /// <param name="diskFirmware">External P5/P6 firmware to select native Disk II rather than slot seven.</param>
    /// <returns>The initialized machine.</returns>
    internal static Apple2Machine Load(Apple2Model model, Apple2Roms roms, string? diskPath, DiskIIFirmware? diskFirmware = null)
    {
        if (diskPath is not null && diskFirmware is null && Path.GetExtension(diskPath).ToLowerInvariant() is not (".po" or ".hdv" or ".2mg"))
        {
            throw new ArgumentException("Native floppy images require externally supplied Disk II boot and sequencer ROMs.");
        }

        string? blockPath = diskPath is null || diskFirmware is not null ? null : Path.GetFullPath(diskPath);
        Apple2Machine machine = new(model, roms, blockPath is null ? null : Disk(blockPath));

        if (diskFirmware is not null)
        {
            machine.Bus.InstallDiskII(slot: 6, diskFirmware);
            if (diskPath is not null) { Insert(machine.Drives[0], Path.GetFullPath(diskPath)); }
        }
        else if (machine.BlockStorage is { } storage && blockPath is not null)
        {
            storage.Label = blockPath;
            storage.Format = Path.GetExtension(blockPath).TrimStart('.').ToUpperInvariant();
        }

        return machine;
    }

    /// <summary>
    ///  Inserts a WOZ image, or a DOS- or ProDOS-order or 13-sector (<c>.d13</c>) sector image converted to a WOZ
    ///  disk, in a Disk II drive, in place of any disk there.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   The image is read and checked before the disk in the drive comes out, so one that cannot be read leaves that
    ///   disk where it was.
    ///  </para>
    /// </remarks>
    /// <param name="drive">The drive.</param>
    /// <param name="path">The image's full path.</param>
    internal static void Insert(Apple2FloppyDrive drive, string path)
    {
        byte[] bytes = File.ReadAllBytes(path);
        LoadedDisk loaded = DiskIIImage.Load(bytes, Path.GetExtension(path));
        drive.Eject();
        MediaActions.Register(loaded.Disk, path, loaded.Codec, bytes);
        drive.Insert(loaded.Disk, path, loaded.Codec?.Format ?? "D13");
    }

    /// <summary>
    ///  Inserts a 3.5-inch disk image (<c>.po</c>, <c>.2mg</c>, <c>.hdv</c>, <c>.img</c> or <c>.dsk</c>) in a 3.5
    ///  drive, in place of any disk there; as for a Disk II, the image is read and checked before that disk comes out.
    /// </summary>
    /// <param name="drive">The drive.</param>
    /// <param name="path">The image's full path.</param>
    internal static void Insert(Apple2Disk35Drive drive, string path)
    {
        byte[] bytes = File.ReadAllBytes(path);
        Disk35Disk disk = Disk35Disk.Load(bytes);
        drive.Eject();
        BlockImageCodec? codec = BlockImageCodec.For(Path.GetExtension(path));
        MediaActions.Register(disk, path, codec, bytes);
        drive.Insert(disk, path, codec?.Format ?? "PO");
    }

    // The most blocks a ProDOS volume, and the slot 7 device's 16-bit block count, can hold: 32 MiB.
    private const int MaximumBlocks = 65535;

    /// <summary>
    ///  Reads a ProDOS-order image for slot 7: its 512-byte blocks in order with no header, or a 2MG of them. It loads
    ///  locked, as slot 7 always has, and writes once unlocked.
    /// </summary>
    /// <param name="path">The image's full path.</param>
    /// <returns>The block device.</returns>
    /// <exception cref="InvalidDataException">The file is not a whole number of blocks, or holds too many.</exception>
    private static MemoryBlockDevice Disk(string path)
    {
        byte[] bytes = File.ReadAllBytes(path);
        MemoryBlockDevice disk = MemoryBlockDevice.Load(bytes, writeProtected: true);
        if (disk.BlockCount > MaximumBlocks)
        {
            throw new InvalidDataException(
                $"{Path.GetFileName(path)} is not a ProDOS-order block image: it must be 1 to {MaximumBlocks} whole 512-byte blocks.");
        }

        MediaActions.Register(disk, path, BlockImageCodec.For(Path.GetExtension(path)), bytes);
        return disk;
    }
}