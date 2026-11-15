// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Buffers.Binary;

namespace Retrocore.Media;

/// <summary>
///  Reads Disk II images into disks, and gives the codec that writes each format: WOZ, and 16-sector images in DOS's
///  or ProDOS's sector order. A 13-sector <c>.d13</c> image is read only.
/// </summary>
/// <remarks>
///  <para>
///   A <c>.dsk</c> image's sector order is found from its file system rather than assumed: DOS 3.3's catalog,
///   ProDOS's volume directory and Apple Pascal's directory each read back whole only in the order the image is in.
///   One with none of them is taken as DOS order, as <c>.dsk</c> images usually are, and saved back in the order it
///   was read.
///  </para>
/// </remarks>
public static class DiskIIImage
{
    private const int TrackSize = 16 * 256;

    /// <summary>
    ///  Gets the formats a Disk II disk saves as.
    /// </summary>
    public static IReadOnlyList<string> SaveFormats { get; } = ["WOZ", "DSK", "DO", "PO"];

    /// <summary>
    ///  Reads an image into a disk, which comes in write-protected, as the Disk II's disks do.
    /// </summary>
    /// <param name="image">The image's bytes.</param>
    /// <param name="extension">Its extension, such as <c>dsk</c>, with or without the dot, in any case.</param>
    /// <returns>The disk, and the codec that writes it back to the image as it was.</returns>
    /// <exception cref="InvalidDataException">The image is not a disk of its format.</exception>
    public static LoadedDisk Load(ReadOnlySpan<byte> image, string extension)
    {
        string format = Normalize(extension);
        switch (format)
        {
            case "WOZ":
                WozDisk woz = WozDisk.Load(image);
                return new(woz, new WozCodec(woz.SourceVersion));
            case "D13":
                return new(SectorDiskConverter.ConvertThirteenSector(image), Codec: null);
            default:
                bool proDosOrder = format == "PO" || (format == "DSK" && IsProDosOrder(image));
                return new(SectorDiskConverter.Convert(image, proDosOrder), new SectorImageCodec(format, proDosOrder));
        }
    }

    /// <summary>
    ///  Gets the codec that writes a disk to a new image of a format, as a save to another file does: DOS order for
    ///  <c>.dsk</c> and <c>.do</c>, ProDOS order for <c>.po</c>.
    /// </summary>
    /// <param name="extension">The image's extension, such as <c>po</c>, with or without the dot, in any case.</param>
    /// <returns>The codec, or null for a format a Disk II disk cannot be saved as.</returns>
    public static IImageCodec? CodecFor(string extension) => Normalize(extension) switch
    {
        "WOZ" => new WozCodec(),
        "DSK" => new SectorImageCodec("DSK", proDosOrder: false),
        "DO" => new SectorImageCodec("DO", proDosOrder: false),
        "PO" => new SectorImageCodec("PO", proDosOrder: true),
        _ => null,
    };

    /// <summary>
    ///  Finds whether a 16-sector image is in ProDOS's sector order, from the file system on it.
    /// </summary>
    /// <param name="image">The image: 35 to 40 tracks of 4,096 bytes.</param>
    /// <returns>True when its file system reads whole in ProDOS's order and not better in DOS's.</returns>
    public static bool IsProDosOrder(ReadOnlySpan<byte> image) => Score(image, proDosOrder: true) > Score(image, proDosOrder: false);

    // The extension as a format: upper case, with no dot, and DSK for none.
    private static string Normalize(string extension)
    {
        string format = extension.TrimStart('.').ToUpperInvariant();
        return format.Length == 0 ? "DSK" : format;
    }

    // How well the image's file system reads when the image is taken to be in an order: the links that hold up.
    private static int Score(ReadOnlySpan<byte> image, bool proDosOrder)
    {
        if (image.Length % TrackSize != 0 || image.Length / TrackSize < 35) { return 0; }
        return Math.Max(DosScore(image, proDosOrder), Math.Max(ProDosScore(image, proDosOrder), PascalScore(image, proDosOrder)));
    }

    // DOS 3.3: its VTOC, then the catalog's sectors, each linked to the one before it on the catalog track.
    private static int DosScore(ReadOnlySpan<byte> image, bool proDosOrder)
    {
        int tracks = image.Length / TrackSize;
        ReadOnlySpan<byte> vtoc = DosSector(image, proDosOrder, track: 17, sector: 0);
        if (vtoc[3] != 3 || vtoc[0x27] != 122 || vtoc[0x35] != 16 || vtoc[1] >= tracks || vtoc[2] > 15) { return 0; }

        int score = 1;
        int catalogTrack = vtoc[1];
        int sector = vtoc[2];
        for (int step = 0; step < 15 && sector > 1; step++)
        {
            ReadOnlySpan<byte> catalog = DosSector(image, proDosOrder, catalogTrack, sector);
            if (catalog[1] != catalogTrack || catalog[2] != sector - 1) { break; }
            score++;
            sector--;
        }

        return score;
    }

    // ProDOS: the volume directory's key block, 2, and the blocks after it, each naming the one before and after.
    private static int ProDosScore(ReadOnlySpan<byte> image, bool proDosOrder)
    {
        Span<byte> block = stackalloc byte[512];
        Block(image, proDosOrder, number: 2, block);
        if (BinaryPrimitives.ReadUInt16LittleEndian(block) != 0 || (block[4] >> 4) != 0xF || block[0x23] != 0x27 || block[0x24] != 0x0D)
        {
            return 0;
        }

        int score = 1;
        int previous = 2;
        int next = BinaryPrimitives.ReadUInt16LittleEndian(block[2..]);
        for (int step = 0; step < 8 && next is > 2 and < 280; step++)
        {
            Block(image, proDosOrder, next, block);
            if (BinaryPrimitives.ReadUInt16LittleEndian(block) != previous) { break; }
            score++;
            previous = next;
            next = BinaryPrimitives.ReadUInt16LittleEndian(block[2..]);
        }

        return score;
    }

    // Apple Pascal: the volume's entry at the start of block 2, with a name of 1 to 7 letters and the volume's blocks.
    private static int PascalScore(ReadOnlySpan<byte> image, bool proDosOrder)
    {
        Span<byte> block = stackalloc byte[512];
        Block(image, proDosOrder, number: 2, block);
        int length = block[6];
        int blocks = BinaryPrimitives.ReadUInt16LittleEndian(block[14..]);
        if (BinaryPrimitives.ReadUInt16LittleEndian(block) != 0
            || BinaryPrimitives.ReadUInt16LittleEndian(block[2..]) != 6
            || length is < 1 or > 7
            || blocks != image.Length / 512)
        {
            return 0;
        }

        foreach (byte letter in block.Slice(7, length))
        {
            if (letter is < 0x20 or > 0x7E) { return 0; }
        }

        return 2;
    }

    // A sector by its DOS 3.3 number, from an image taken to be in an order.
    private static ReadOnlySpan<byte> DosSector(ReadOnlySpan<byte> image, bool proDosOrder, int track, int sector) =>
        Sector(image, proDosOrder, track, Physical(sector, proDosOrder: false));

    // A ProDOS block: the two sectors ProDOS numbers 2n and 2n + 1 on its track, from an image taken to be in an order.
    private static void Block(ReadOnlySpan<byte> image, bool proDosOrder, int number, Span<byte> block)
    {
        int track = number / 8;
        if ((track + 1) * TrackSize > image.Length)
        {
            block.Clear();
            return;
        }

        int first = number % 8 * 2;
        Sector(image, proDosOrder, track, Physical(first, proDosOrder: true)).CopyTo(block);
        Sector(image, proDosOrder, track, Physical(first + 1, proDosOrder: true)).CopyTo(block[256..]);
    }

    // A physical sector, from an image taken to be in an order.
    private static ReadOnlySpan<byte> Sector(ReadOnlySpan<byte> image, bool proDosOrder, int track, int physical) =>
        image.Slice((track * TrackSize) + (Logical(physical, proDosOrder) * 256), 256);

    // Where an order puts a physical sector, as SectorDiskConverter does.
    private static int Logical(int physical, bool proDosOrder) => physical == 15 ? 15 : physical * (proDosOrder ? 8 : 7) % 15;

    // The physical sector an order puts at a place.
    private static int Physical(int logical, bool proDosOrder)
    {
        for (int physical = 0; physical < 16; physical++)
        {
            if (Logical(physical, proDosOrder) == logical) { return physical; }
        }

        throw new UnreachableException();
    }
}
