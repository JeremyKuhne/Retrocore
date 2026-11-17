// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Trs80;
using Retrocore.Media.Trs80;

namespace Retrocore.Debug;

/// <summary>
///  Puts TRS-80 and Color Computer disk images in their drives, recording where each came from so it saves back.
/// </summary>
internal static class FloppyMedia
{
    /// <summary>
    ///  Inserts a disk image in a drive, in place of any disk there: the image is read and checked first, so a bad
    ///  one leaves that disk.
    /// </summary>
    /// <param name="drive">The drive.</param>
    /// <param name="path">The image's path.</param>
    /// <param name="coco">
    ///  Whether the drive is a Color Computer's, which reads JVC and DMK; a TRS-80's reads JV1, JV3, DMK and IMD.
    /// </param>
    internal static void Insert(Trs80FloppyDrive drive, string path, bool coco)
    {
        string full = Path.GetFullPath(path);
        byte[] bytes = File.ReadAllBytes(full);
        string extension = Path.GetExtension(full);
        (FloppyDisk disk, string format) = coco
            ? Trs80DiskImage.ReadCoco(bytes, extension)
            : Trs80DiskImage.Read(bytes, extension);

        drive.Eject();
        MediaActions.Register(disk, full, FloppyImageCodec.ForImage(format, bytes), bytes);
        drive.Insert(disk, full, format);
    }
}
