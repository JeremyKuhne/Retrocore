// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media.Trs80;

/// <summary>
///  DMK, David Keil's format: a 16-byte header, then each track's raw bytes as the controller reads them, led by a
///  table of the offsets of its ID address marks.
/// </summary>
/// <remarks>
///  <para>
///   The header is the write protect byte (<c>$FF</c> protected), the tracks, the track length (with its 128-byte
///   table) and options: bit 4 single-sided, bit 6 single density only, bit 7 ignore density. Each of a track's 64
///   table entries is an offset into the track, bit 15 set for a double-density ID mark, ending at 0. Unless the
///   image is single density only, a single-density byte is stored twice. Sides alternate within a cylinder.
///  </para>
/// </remarks>
public static class DmkFormat
{
    private const int HeaderSize = 16;
    private const int TableEntries = 64;
    private const byte IdMark = 0xFE;

    /// <summary>
    ///  Gets whether an image looks like DMK: a write protect byte of 0 or <c>$FF</c>, a track length that divides
    ///  the rest of the image, and no undefined option bits.
    /// </summary>
    /// <param name="image">The file's bytes.</param>
    /// <returns>Whether it is DMK.</returns>
    public static bool IsDmk(ReadOnlySpan<byte> image)
    {
        if (image.Length < HeaderSize || image[0] is not (0 or 0xFF) || (image[4] & 0x2F) != 0) { return false; }
        int length = image[2] | (image[3] << 8);
        int tracks = image[1] * ((image[4] & 0x10) != 0 ? 1 : 2);
        return length > TableEntries * 2 && tracks > 0 && image.Length >= HeaderSize + (length * tracks);
    }

    /// <summary>
    ///  Reads an image.
    /// </summary>
    /// <param name="image">The file's bytes.</param>
    /// <returns>The disk.</returns>
    /// <exception cref="InvalidDataException">The image is not DMK.</exception>
    public static FloppyDisk Read(ReadOnlySpan<byte> image)
    {
        if (!IsDmk(image)) { throw new InvalidDataException("The image is not DMK."); }
        int length = image[2] | (image[3] << 8);
        bool singleSided = (image[4] & 0x10) != 0;
        bool singleOnly = (image[4] & 0x40) != 0;
        FloppyDisk disk = new() { WriteProtected = image[0] == 0xFF };
        int sides = singleSided ? 1 : 2;
        for (int cylinder = 0; cylinder < image[1]; cylinder++)
        {
            for (int side = 0; side < sides; side++)
            {
                ReadOnlySpan<byte> track = image.Slice(HeaderSize + (((cylinder * sides) + side) * length), length);
                ReadTrack(disk, cylinder, side, track, singleOnly);
            }
        }

        return disk;
    }

    private static void ReadTrack(FloppyDisk disk, int cylinder, int side, ReadOnlySpan<byte> track, bool singleOnly)
    {
        for (int entry = 0; entry < TableEntries; entry++)
        {
            int pointer = track[entry * 2] | (track[(entry * 2) + 1] << 8);
            if (pointer == 0) { break; }
            bool doubleDensity = (pointer & 0x8000) != 0;
            int offset = pointer & 0x3FFF;

            // A single-density byte is doubled, except in a single-density-only image.
            int step = doubleDensity || singleOnly ? 1 : 2;
            if (offset + (7 * step) > track.Length || track[offset] != IdMark) { continue; }
            byte trackNumber = track[offset + step];
            byte sideNumber = track[offset + (2 * step)];
            byte sectorNumber = track[offset + (3 * step)];
            int size = 128 << (track[offset + (4 * step)] & 3);

            // The data mark follows within the gap after the ID field and its CRC.
            int data = offset + (7 * step);
            int limit = Math.Min(track.Length, data + (60 * step));
            while (data < limit && track[data] is not (>= 0xF8 and <= 0xFB)) { data += step; }
            if (data >= limit || data + ((size + 1) * step) > track.Length) { continue; }
            byte mark = track[data];
            byte[] bytes = new byte[size];
            for (int index = 0; index < size; index++) { bytes[index] = track[data + ((index + 1) * step)]; }
            disk.Add(cylinder, side, new(trackNumber, sideNumber, sectorNumber, bytes, doubleDensity, mark));
        }
    }
}
