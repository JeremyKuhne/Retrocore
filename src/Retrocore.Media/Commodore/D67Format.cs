// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media.Commodore;

/// <summary>
///  Reads and writes D67 images: a 35-track DOS 1 disk's 690 sectors of 256 bytes in order, track 1 first, as the
///  2040 and 3040 lay them out.
/// </summary>
/// <remarks>
///  <para>
///   DOS 1 puts 20 sectors on each of tracks 18-24, where DOS 2 puts 19; the other zones are the same. Reading lays
///   each track out as the 2040 formats it, with the disk ID from track 18 sector 0's bytes <c>$A2</c> and
///   <c>$A3</c>, as for a <see cref="D64Format"/> image. Writing reads each sector back; a sector that cannot be read
///   is written as zeros and listed.
///  </para>
/// </remarks>
public static class D67Format
{
    /// <summary>
    ///  The size of an image.
    /// </summary>
    public const int Size = GcrLayout.Dos1Sectors * GcrLayout.SectorSize;

    /// <summary>
    ///  Gets whether bytes are the size of a D67 image.
    /// </summary>
    /// <param name="image">The bytes.</param>
    /// <returns>Whether they are.</returns>
    public static bool IsD67(ReadOnlySpan<byte> image) => image.Length == Size;

    /// <summary>
    ///  Reads an image.
    /// </summary>
    /// <param name="image">The file's bytes.</param>
    /// <returns>The disk.</returns>
    /// <exception cref="InvalidDataException">The image is not a D67 image's size.</exception>
    public static CommodoreDisk Read(ReadOnlySpan<byte> image)
    {
        if (!IsD67(image)) { throw new InvalidDataException($"A D67 image is {Size} bytes."); }
        return D64Format.ReadSectors(image, CommodoreDos.Dos1);
    }

    /// <summary>
    ///  Writes a disk's sectors as an image.
    /// </summary>
    /// <param name="disk">The disk.</param>
    /// <returns>The image, and the sectors that could not be read, as "track 18, sector 0".</returns>
    public static (byte[] Image, IReadOnlyList<string> Unreadable) Write(CommodoreDisk disk) =>
        D64Format.WriteSectors(disk, CommodoreDos.Dos1);
}
