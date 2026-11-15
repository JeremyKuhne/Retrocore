// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Apple2;
using Retrocore.Media;
using System.Runtime.CompilerServices;

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
        LoadedDisk loaded = DiskIIImage.Load(File.ReadAllBytes(path), Path.GetExtension(path));
        if (loaded.Codec is { } codec) { s_codecs.AddOrUpdate(loaded.Disk, codec); }
        drive.Insert(loaded.Disk, path, loaded.Codec?.Format ?? "D13");
    }

    // The codec each disk read from an image saves back to it with, so a .dsk keeps the sector order it was found in.
    private static readonly ConditionalWeakTable<WozDisk, IImageCodec> s_codecs = [];

    /// <summary>
    ///  Saves the disk in a drive, with what the machine wrote to it, to an image: its own image in the format and
    ///  sector order it was read in, or another as its extension names (a WOZ image for <c>.woz</c>, a sector image in
    ///  ProDOS's order for <c>.po</c> and DOS's for <c>.dsk</c> and <c>.do</c>).
    /// </summary>
    /// <param name="drive">The drive.</param>
    /// <param name="path">The image to write; the disk's own image when null.</param>
    /// <param name="acceptLosses">
    ///  Whether to save though the format cannot hold all of the disk; the disk then stays changed.
    /// </param>
    /// <exception cref="InvalidOperationException">The drive is empty.</exception>
    /// <exception cref="ArgumentException">The image's format can't hold a Disk II disk.</exception>
    /// <exception cref="InvalidDataException">
    ///  The format cannot hold all of the disk, such as a track that no longer reads as 16 sectors, and
    ///  <paramref name="acceptLosses"/> is false.
    /// </exception>
    internal static void Save(Apple2FloppyDrive drive, string? path, bool acceptLosses = false)
    {
        WozDisk disk = drive.Disk ?? throw new InvalidOperationException($"{drive.Info.Name} is empty.");
        string own = drive.Media?.Label ?? "";
        path = Path.GetFullPath(path ?? own);
        // Its own image is written in the format and order it was read in; another, as its extension says.
        IImageCodec? codec = DiskIIImage.CodecFor(Path.GetExtension(path));
        if (SameFile(path, own) && s_codecs.TryGetValue(disk, out IImageCodec? read)) { codec = read; }
        if (codec is null)
        {
            throw new ArgumentException($"{Path.GetFileName(path)} is not a .woz, .dsk, .do or .po image; save it as .woz.");
        }

        EncodedImage encoded = codec.Encode(disk.Snapshot());
        if (!encoded.IsLossless && !acceptLosses)
        {
            throw new InvalidDataException(
                $"{codec.Format} cannot hold all of the disk: {string.Join(" ", encoded.Losses)} Save it as .woz to keep all of it.");
        }

        byte[] image = encoded.Bytes;

        // Written to a new file beside it and moved over it, so a failed write leaves the image as it was.
        string temporary = Path.Join(Path.GetDirectoryName(path), $".{Path.GetFileName(path)}.{Guid.NewGuid():N}.saving");
        try
        {
            using (FileStream stream = new(temporary, FileMode.CreateNew, FileAccess.Write))
            {
                stream.Write(image);
            }

            File.Move(temporary, path, overwrite: true);
        }
        finally
        {
            File.Delete(temporary);
        }

        // The disk now comes from the image just written, which a lossy save leaves it changed against.
        s_codecs.AddOrUpdate(disk, codec);
        drive.Saved(path, codec.Format, encoded.IsLossless);
    }

    // Whether a path names a drive's own image: compared without case where the file system ignores it, as Windows'
    // and macOS's do by default, and with it elsewhere.
    private static bool SameFile(string path, string own) =>
        Path.IsPathFullyQualified(own) && string.Equals(path, Path.GetFullPath(own), PathComparison);

    private static StringComparison PathComparison =>
        OperatingSystem.IsWindows() || OperatingSystem.IsMacOS() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal;

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