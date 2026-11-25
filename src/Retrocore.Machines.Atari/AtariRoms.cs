// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Atari;

/// <summary>
///  The operating system's 10 KB: the floating point package at <c>$D800-$DFFF</c> and the OS at
///  <c>$E000-$FFFF</c>, the character set in its first 1 KB.
/// </summary>
public sealed class AtariRoms
{
    /// <summary>
    ///  The size of the OS image, floating point package included.
    /// </summary>
    public const int Size = 0x2800;

    /// <summary>
    ///  The address the image starts at.
    /// </summary>
    public const ushort Base = 0xD800;

    private readonly byte[] _image;
    private readonly byte[] _diskDrive;

    /// <summary>
    ///  Constructs the ROMs from the 10 KB image in address order.
    /// </summary>
    /// <param name="image">The floating point package, then the OS.</param>
    /// <param name="diskDrive">The 810's 2 KB firmware, or empty for none.</param>
    /// <exception cref="ArgumentException">The image isn't 10,240 bytes, or the firmware isn't 2 KB.</exception>
    public AtariRoms(ReadOnlySpan<byte> image, ReadOnlySpan<byte> diskDrive = default)
    {
        if (image.Length != Size) { throw new ArgumentException("The OS image is 10,240 bytes.", nameof(image)); }
        if (!diskDrive.IsEmpty && diskDrive.Length != Atari810.RomSize)
        {
            throw new ArgumentException("The 810's firmware is 2 KB.", nameof(diskDrive));
        }

        _image = image.ToArray();
        _diskDrive = diskDrive.ToArray();
    }

    /// <summary>
    ///  Gets the image, <c>$D800-$FFFF</c>.
    /// </summary>
    public ReadOnlySpan<byte> Image => _image;

    /// <summary>
    ///  Gets the 810's firmware, or empty if there is none.
    /// </summary>
    public ReadOnlySpan<byte> DiskDrive => _diskDrive;

    /// <summary>
    ///  Loads the three chips from a folder holding MAME's <c>a800</c> or <c>a800pal</c> set, unzipped.
    /// </summary>
    /// <param name="directory">The folder.</param>
    /// <param name="revision">
    ///  The OS revision: <c>'B'</c> (the NTSC 400/800's last, the default) or <c>'A'</c>. A folder with the PAL chips
    ///  (<c>co15199.rom</c>, <c>co15299.rom</c>) loads those whatever the revision.
    /// </param>
    /// <param name="diskDriveDirectory">
    ///  The folder holding MAME's <c>atari810</c> set, unzipped, for the 810's firmware: by default an
    ///  <c>atari810</c> folder beside <paramref name="directory"/>, or <paramref name="directory"/> itself. With no
    ///  firmware, the machine's disk drives must work at the command level
    ///  (<see cref="AtariDiskDriveKind.CommandLevel"/>).
    /// </param>
    /// <returns>The ROMs.</returns>
    /// <exception cref="FileNotFoundException">A chip is missing.</exception>
    public static AtariRoms LoadFromDirectory(string directory, char revision = 'B', string? diskDriveDirectory = null)
    {
        ArgumentNullException.ThrowIfNull(directory);
        string fp = Path.Join(directory, "co12399b.rom");
        string pal = Path.Join(directory, "co15199.rom");
        string[] os = File.Exists(pal)
            ? [pal, Path.Join(directory, "co15299.rom")]
            : char.ToUpperInvariant(revision) == 'A'
                ? [Path.Join(directory, "co12499a.rom"), Path.Join(directory, "co14599a.rom")]
                : [Path.Join(directory, "co12499b.rom"), Path.Join(directory, "co14599b.rom")];

        byte[] image = new byte[Size];
        File.ReadAllBytes(fp).CopyTo(image, 0);
        File.ReadAllBytes(os[0]).CopyTo(image, 0x0800);
        File.ReadAllBytes(os[1]).CopyTo(image, 0x1800);

        string beside = Path.Join(Path.GetDirectoryName(Path.TrimEndingDirectorySeparator(Path.GetFullPath(directory))), "atari810");
        byte[]? drive = Atari810Firmware.LoadFromDirectory(diskDriveDirectory ?? beside)
            ?? Atari810Firmware.LoadFromDirectory(directory);

        return new(image, drive);
    }
}
