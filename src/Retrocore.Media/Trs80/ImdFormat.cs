// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media.Trs80;

/// <summary>
///  ImageDisk (IMD), Dave Dunfield's format, in which most Model II disks and many Model III and 4 disks are kept:
///  an ASCII comment ended by <c>$1A</c>, then each track as its mode, cylinder, head, sector count and size, its
///  sector numbers, and a record per sector.
/// </summary>
/// <remarks>
///  <para>
///   Modes 0-2 are single density (FM) and 3-5 double (MFM). Head bit 7 adds a map of each sector's cylinder and
///   bit 6 one of its head. A record is 0 for a sector with no data, then odd for the data and even for one byte
///   that fills it; 3-4 are deleted data, 5-6 data with a CRC error, and 7-8 both.
///  </para>
/// </remarks>
public static class ImdFormat
{
    private const byte CommentEnd = 0x1A;

    /// <summary>
    ///  Gets whether an image looks like IMD: it starts with <c>IMD</c>.
    /// </summary>
    /// <param name="image">The file's bytes.</param>
    /// <returns>Whether it is IMD.</returns>
    public static bool IsImd(ReadOnlySpan<byte> image) => image.StartsWith("IMD"u8);

    /// <summary>
    ///  Reads an image.
    /// </summary>
    /// <param name="image">The file's bytes.</param>
    /// <returns>The disk.</returns>
    /// <exception cref="InvalidDataException">The image is not IMD or is truncated.</exception>
    public static FloppyDisk Read(ReadOnlySpan<byte> image)
    {
        if (!IsImd(image)) { throw new InvalidDataException("An IMD image starts with \"IMD\"."); }
        int offset = image.IndexOf(CommentEnd);
        if (offset < 0) { throw new InvalidDataException("An IMD image's comment ends with $1A."); }
        offset++;
        FloppyDisk disk = new();
        while (offset < image.Length)
        {
            Need(image, offset, 5);
            byte mode = image[offset];
            byte cylinder = image[offset + 1];
            byte head = image[offset + 2];
            int count = image[offset + 3];
            byte sizeCode = image[offset + 4];
            offset += 5;
            if (sizeCode > 3)
            {
                throw new InvalidDataException("IMD sectors larger than 1024 bytes are not supported.");
            }

            int size = 128 << sizeCode;
            int side = head & 1;
            Need(image, offset, count);
            ReadOnlySpan<byte> numbers = image.Slice(offset, count);
            offset += count;
            ReadOnlySpan<byte> cylinders = [];
            ReadOnlySpan<byte> heads = [];
            if ((head & 0x80) != 0)
            {
                Need(image, offset, count);
                cylinders = image.Slice(offset, count);
                offset += count;
            }

            if ((head & 0x40) != 0)
            {
                Need(image, offset, count);
                heads = image.Slice(offset, count);
                offset += count;
            }

            for (int index = 0; index < count; index++)
            {
                Need(image, offset, 1);
                byte record = image[offset++];
                if (record > 8) { throw new InvalidDataException($"IMD sector record {record} is not defined."); }
                if (record == 0) { continue; }
                byte[] data = new byte[size];
                if (record % 2 == 1)
                {
                    Need(image, offset, size);
                    image.Slice(offset, size).CopyTo(data);
                    offset += size;
                }
                else
                {
                    Need(image, offset, 1);
                    data.AsSpan().Fill(image[offset++]);
                }

                bool deleted = record is 3 or 4 or 7 or 8;
                FloppySector sector = new(
                    cylinders.IsEmpty ? cylinder : cylinders[index],
                    heads.IsEmpty ? (byte)side : heads[index],
                    numbers[index],
                    data,
                    doubleDensity: mode >= 3,
                    deleted ? (byte)0xF8 : (byte)0xFB)
                {
                    CrcError = record >= 5
                };

                disk.Add(cylinder, side, sector);
            }
        }

        return disk;
    }

    private static void Need(ReadOnlySpan<byte> image, int offset, int length)
    {
        if (offset + length > image.Length) { throw new InvalidDataException("The IMD image is truncated."); }
    }
}
