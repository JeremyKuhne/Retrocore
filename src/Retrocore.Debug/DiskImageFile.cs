// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Media;

namespace Retrocore.Debug;

/// <summary>
///  Reads a 140K disk image file's sectors: a <c>.dsk</c> image as it is, or a <c>.woz</c> image's track data read
///  back into sectors in DOS order, as the Apple Pascal disks preserved as WOZ images are.
/// </summary>
internal static class DiskImageFile
{
    /// <summary>
    ///  Reads an image's sectors.
    /// </summary>
    /// <param name="path">The image's path.</param>
    /// <returns>The 143,360 bytes of its sectors, in DOS order.</returns>
    public static byte[] Sectors(string path)
    {
        byte[] image = File.ReadAllBytes(path);
        return path.EndsWith(".woz", StringComparison.OrdinalIgnoreCase)
            ? SectorDiskReader.Read(WozDisk.Load(image), proDosOrder: false)
            : image;
    }
}
