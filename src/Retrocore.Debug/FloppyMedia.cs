// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Chips;
using Retrocore.Media.Floppy;
using Retrocore.Media.Trs80;

namespace Retrocore.Debug;

/// <summary>
///  Puts TRS-80, Color Computer and Kaypro disk images in their drives, recording where each came from so it saves
///  back.
/// </summary>
internal static class FloppyMedia
{
    /// <summary>
    ///  Inserts a disk image in a drive, in place of any disk there: the image is read and checked first, so a bad
    ///  one leaves that disk.
    /// </summary>
    /// <param name="drive">The drive.</param>
    /// <param name="path">The image's path.</param>
    /// <param name="family">
    ///  Whose drive it is: a TRS-80's reads JV1, JV3, DMK and IMD, a Color Computer's JVC and DMK, and a Kaypro's raw
    ///  images, IMD and DMK.
    /// </param>
    internal static void Insert(FloppyDrive drive, string path, FloppyFamily family)
    {
        string full = Path.GetFullPath(path);
        byte[] bytes = File.ReadAllBytes(full);
        string extension = Path.GetExtension(full);
        (FloppyDisk disk, string format) = family switch
        {
            FloppyFamily.Coco => Trs80DiskImage.ReadCoco(bytes, extension),
            FloppyFamily.Kaypro => Trs80DiskImage.ReadKaypro(bytes, extension),
            _ => Trs80DiskImage.Read(bytes, extension)
        };

        drive.Eject();
        MediaActions.Register(disk, full, FloppyImageCodec.ForImage(format, bytes), bytes);
        drive.Insert(disk, full, format);
    }
}
