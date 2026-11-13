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

    // IMD has a signature, JV3 a table whose sectors fit the file, and DMK a header whose tracks are the whole file.
    // JV1 is any whole number of 256-byte sectors, a last track cut short included. A DMK image with more after its
    // tracks comes last, as JV1's sector data can pass for its loose header.
    private static string Detect(ReadOnlySpan<byte> image)
    {
        if (ImdFormat.IsImd(image)) { return "IMD"; }
        if (Jv3Format.IsJv3(image)) { return "JV3"; }
        if (DmkFormat.IsDmk(image) && DmkFormat.ImageLength(image) == image.Length) { return "DMK"; }
        if (image.Length != 0 && image.Length % Jv1Format.SectorSize == 0) { return "JV1"; }
        return DmkFormat.IsDmk(image) ? "DMK" : "JV3";
    }
}
