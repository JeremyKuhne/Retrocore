// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media;

/// <summary>
///  Starts a bootable SOS volume: the bootstrap loader in block 0, then SOS.KERNEL, SOS.DRIVER and SOS.INTERP, the
///  three files the Apple III needs to boot SOS and run a program.
/// </summary>
/// <remarks>
///  <para>
///   The boot ROM reads block 0 and runs it. The bootstrap loader finds SOS.KERNEL in the volume directory, which
///   must be a sapling (2-256 blocks), and starts it. SOS's loader then reads <c>.D1/SOS.INTERP</c> and
///   <c>.D1/SOS.DRIVER</c>, loads the drivers, and starts the interpreter. The three files are SOS system files,
///   type <c>$0C</c>, first in the directory as Apple's disks have them.
///  </para>
/// </remarks>
public static class SosBootDisk
{
    /// <summary>
    ///  The file type of SOS.KERNEL, SOS.DRIVER and SOS.INTERP: a SOS system file.
    /// </summary>
    public const int SystemFileType = 0x0C;

    /// <summary>
    ///  Starts a bootable volume; add the program's other files to the builder, then build it.
    /// </summary>
    /// <param name="name">The volume's name: 1-15 letters, digits and periods, starting with a letter.</param>
    /// <param name="loader">The bootstrap loader: block 0, or blocks 0 and 1.</param>
    /// <param name="kernel">SOS.KERNEL, which starts with <c>SOS KRNL</c>.</param>
    /// <param name="drivers">
    ///  SOS.DRIVER, which starts with <c>SOS DRVR</c>, as <see cref="SosDriverFile.Write"/> writes it.
    /// </param>
    /// <param name="interpreter">
    ///  SOS.INTERP, which starts with <c>SOS NTRP</c>, as <see cref="SosInterpreterFile.Write"/> writes it.
    /// </param>
    /// <returns>The builder, with the loader and the three files.</returns>
    /// <exception cref="ArgumentException">
    ///  The name is not a SOS name, the loader is not one or two blocks, a file lacks its label, or the kernel is not
    ///  a sapling's size.
    /// </exception>
    /// <exception cref="InvalidOperationException">The files do not fit on the volume.</exception>
    public static SosVolumeBuilder Create(
        string name,
        ReadOnlySpan<byte> loader,
        ReadOnlySpan<byte> kernel,
        ReadOnlySpan<byte> drivers,
        ReadOnlySpan<byte> interpreter)
    {
        Check(kernel, "SOS KRNL"u8, "SOS.KERNEL", nameof(kernel));
        Check(drivers, "SOS DRVR"u8, "SOS.DRIVER", nameof(drivers));
        Check(interpreter, "SOS NTRP"u8, "SOS.INTERP", nameof(interpreter));

        // The bootstrap loader reads SOS.KERNEL only as a sapling: an index block of 2 to 256 data blocks.
        if (kernel.Length is <= SosVolume.BlockSize or > 256 * SosVolume.BlockSize)
        {
            throw new ArgumentException(
                $"SOS.KERNEL must be a sapling, {SosVolume.BlockSize + 1}-{256 * SosVolume.BlockSize} bytes; this one is {kernel.Length}.",
                nameof(kernel));
        }

        SosVolumeBuilder builder = new(name);
        builder.BootFrom(loader);
        builder.Add("SOS.KERNEL", SystemFileType, 0, kernel);
        builder.Add("SOS.DRIVER", SystemFileType, 0, drivers);
        builder.Add("SOS.INTERP", SystemFileType, 0, interpreter);
        return builder;
    }

    private static void Check(ReadOnlySpan<byte> file, ReadOnlySpan<byte> label, string name, string parameter)
    {
        if (!file.StartsWith(label))
        {
            throw new ArgumentException($"{name} starts with \"{System.Text.Encoding.ASCII.GetString(label)}\".", parameter);
        }
    }
}
