// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media.Trs80;

/// <summary>
///  Reads a TRS-80 disk image in whichever format it is: JV1, JV3, DMK or IMD.
/// </summary>
public static class Trs80DiskImage
{
    /// <summary>
    ///  Reads an image, by its extension where that names a format, and otherwise by its contents.
    /// </summary>
    /// <param name="image">The file's bytes.</param>
    /// <param name="extension">The file's extension, such as <c>.dsk</c>.</param>
    /// <returns>The disk and its format's name.</returns>
    /// <exception cref="InvalidDataException">The image is not in the format it appears to be.</exception>
    public static (FloppyDisk Disk, string Format) Read(ReadOnlySpan<byte> image, string? extension)
    {
        string format = (extension ?? "").ToLowerInvariant() switch
        {
            ".jv3" => "JV3",
            ".jv1" => "JV1",
            ".dmk" => "DMK",
            ".imd" => "IMD",
            _ => Detect(image)
        };

        FloppyDisk disk = format switch
        {
            "JV3" => Jv3Format.Read(image),
            "DMK" => DmkFormat.Read(image),
            "IMD" => ImdFormat.Read(image),
            _ => Jv1Format.Read(image)
        };

        return (disk, format);
    }

    // JV1 is whole 10-sector tracks of 256 bytes, which neither IMD's signature nor DMK's header matches.
    private static string Detect(ReadOnlySpan<byte> image)
    {
        if (ImdFormat.IsImd(image)) { return "IMD"; }
        if (image.Length % 2560 == 0) { return "JV1"; }
        return DmkFormat.IsDmk(image) ? "DMK" : "JV3";
    }
}
