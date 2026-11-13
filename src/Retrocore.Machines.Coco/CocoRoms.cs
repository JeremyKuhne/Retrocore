// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Coco;

/// <summary>
///  A Color Computer's system ROMs: Color BASIC and an optional Extended Color BASIC on a CoCo 1 or 2, or the CoCo
///  3's single 32 KB ROM.
/// </summary>
public sealed class CocoRoms
{
    /// <summary>
    ///  The size of each CoCo 1 and 2 ROM.
    /// </summary>
    public const int BasicSize = 0x2000;

    /// <summary>
    ///  The size of the CoCo 3's ROM.
    /// </summary>
    public const int Coco3Size = 0x8000;

    private CocoRoms(ReadOnlyMemory<byte> colorBasic, ReadOnlyMemory<byte> extendedBasic, ReadOnlyMemory<byte> coco3)
    {
        ColorBasic = colorBasic;
        ExtendedBasic = extendedBasic;
        Coco3 = coco3;
    }

    /// <summary>
    ///  Gets Color BASIC, at <c>$A000-$BFFF</c> on a CoCo 1 or 2; empty for a CoCo 3.
    /// </summary>
    public ReadOnlyMemory<byte> ColorBasic { get; }

    /// <summary>
    ///  Gets Extended Color BASIC, at <c>$8000-$9FFF</c> on a CoCo 1 or 2; empty when it is not fitted.
    /// </summary>
    public ReadOnlyMemory<byte> ExtendedBasic { get; }

    /// <summary>
    ///  Gets the CoCo 3's ROM, at <c>$8000-$FFFF</c>; empty for a CoCo 1 or 2.
    /// </summary>
    public ReadOnlyMemory<byte> Coco3 { get; }

    /// <summary>
    ///  Gets whether these are the CoCo 3's ROM.
    /// </summary>
    public bool IsCoco3 => !Coco3.IsEmpty;

    /// <summary>
    ///  Creates CoCo 1 or 2 ROMs.
    /// </summary>
    /// <param name="colorBasic">Color BASIC, 8 KB.</param>
    /// <param name="extendedBasic">Extended Color BASIC, 8 KB, or empty for a machine without it.</param>
    /// <returns>The ROMs.</returns>
    /// <exception cref="ArgumentException">A ROM is the wrong size.</exception>
    public static CocoRoms ForCoco12(ReadOnlySpan<byte> colorBasic, ReadOnlySpan<byte> extendedBasic)
    {
        if (colorBasic.Length != BasicSize)
        {
            throw new ArgumentException("Color BASIC is an 8 KB ROM.", nameof(colorBasic));
        }

        if (!extendedBasic.IsEmpty && extendedBasic.Length != BasicSize)
        {
            throw new ArgumentException("Extended Color BASIC is an 8 KB ROM.", nameof(extendedBasic));
        }

        return new(colorBasic.ToArray(), extendedBasic.ToArray(), coco3: default);
    }

    /// <summary>
    ///  Creates the CoCo 3's ROM.
    /// </summary>
    /// <param name="rom">The 32 KB ROM.</param>
    /// <returns>The ROMs.</returns>
    /// <exception cref="ArgumentException">The ROM is the wrong size.</exception>
    public static CocoRoms ForCoco3(ReadOnlySpan<byte> rom) => rom.Length == Coco3Size
        ? new(colorBasic: default, extendedBasic: default, coco3: rom.ToArray())
        : throw new ArgumentException("The CoCo 3's ROM is 32 KB.", nameof(rom));

    /// <summary>
    ///  Loads dumps by MAME's file names, such as <c>bas12.rom</c>, <c>extbas11.rom</c> and <c>coco3.rom</c>, from a
    ///  directory or its <c>coco</c>, <c>coco2b</c> and <c>coco3</c> subdirectories.
    /// </summary>
    /// <param name="model">The model.</param>
    /// <param name="directory">The directory.</param>
    /// <param name="colorBasicVersion">Color BASIC's version, such as <c>12</c> for 1.2; null for 1.2.</param>
    /// <param name="extendedBasicVersion">Extended BASIC's version, 10 or 11; 0 for none; null for 1.1.</param>
    /// <returns>The ROMs.</returns>
    /// <exception cref="FileNotFoundException">A dump is missing.</exception>
    public static CocoRoms Load(
        CocoModel model,
        string directory,
        int? colorBasicVersion = null,
        int? extendedBasicVersion = null)
    {
        ArgumentNullException.ThrowIfNull(directory);
        if (model == CocoModel.Coco3)
        {
            return ForCoco3(File.ReadAllBytes(Find(directory, "coco3.rom")));
        }

        int color = colorBasicVersion ?? 12;
        int extended = extendedBasicVersion ?? 11;
        byte[] colorBasic = File.ReadAllBytes(Find(directory, $"bas{color}.rom"));
        byte[] extendedBasic = extended == 0 ? [] : File.ReadAllBytes(Find(directory, $"extbas{extended}.rom"));
        return ForCoco12(colorBasic, extendedBasic);
    }

    /// <summary>
    ///  Loads Disk Extended Color BASIC's 8 KB ROM, <c>disk10.rom</c> or <c>disk11.rom</c>, for the disk controller
    ///  cartridge, from a directory or its <c>coco_fdc</c>, <c>coco</c>, <c>coco2b</c> and <c>coco3</c>
    ///  subdirectories.
    /// </summary>
    /// <param name="directory">The directory.</param>
    /// <param name="version">The version, 10 or 11.</param>
    /// <returns>The ROM.</returns>
    /// <exception cref="FileNotFoundException">The dump is missing.</exception>
    public static byte[] LoadDiskBasic(string directory, int version = 11)
    {
        ArgumentNullException.ThrowIfNull(directory);
        return File.ReadAllBytes(Find(directory, $"disk{version}.rom"));
    }

    private static string Find(string directory, string name)
    {
        foreach (string folder in (string[])["", "coco_fdc", "coco", "coco2b", "coco3"])
        {
            string path = Path.Join(directory, folder, name);
            if (File.Exists(path)) { return path; }
        }

        throw new FileNotFoundException($"'{name}' was not found in '{directory}'.", name);
    }
}
