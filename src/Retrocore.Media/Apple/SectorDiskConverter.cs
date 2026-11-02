// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media;

/// <summary>
///  Original 16-sector GCR encoder for raw .dsk/.do and ProDOS-order .po floppy images.
///  Uses the standard 4-and-4 address field and differential 6-and-2 data format, cross-checked
///  against CiderPress II SectorCodec and MIT dsk2woz2. No Disk II firmware is embedded.
/// </summary>
public static class SectorDiskConverter
{
    /// <summary>
    ///  Converts 35-40 tracks of raw sectors into precise sync/data bitstreams.
    ///  The generated media is read-only; persist writes by exporting and mounting a .woz image.
    /// </summary>
    /// <param name="image">Raw 4096-byte tracks.</param>
    /// <param name="proDosOrder">Whether the file uses ProDOS rather than DOS 3.3 sector order.</param>
    /// <returns>Generated WOZ media.</returns>
    public static WozDisk Convert(ReadOnlySpan<byte> image, bool proDosOrder)
    {
        if (image.Length % 4096 != 0 || image.Length / 4096 is < 35 or > 40)
        {
            throw new InvalidDataException("A raw 16-sector floppy image requires 35-40 complete 4096-byte tracks.");
        }

        WozDisk disk = WozDisk.CreateBlank();
        byte[] packed = new byte[(51024 + 7) / 8];
        Span<byte> encoded = stackalloc byte[343];
        for (int track = 0; track < image.Length / 4096; track++)
        {
            Array.Clear(packed);
            DiskBitWriter writer = new(packed);
            for (int count = 0; count < 16; count++) { writer.Sync(); }
            for (int physical = 0; physical < 16; physical++)
            {
                writer.Byte(value: 0xD5);
                writer.Byte(value: 0xAA);
                writer.Byte(value: 0x96);
                writer.Address(value: 254);
                writer.Address((byte)track);
                writer.Address((byte)physical);
                writer.Address((byte)(254 ^ track ^ physical));
                Epilogue(ref writer);
                for (int count = 0; count < 7; count++) { writer.Sync(); }
                writer.Byte(value: 0xD5);
                writer.Byte(value: 0xAA);
                writer.Byte(value: 0xAD);
                int logical = physical == 15 ? 15 : physical * (proDosOrder ? 8 : 7) % 15;
                EncodeSector(image.Slice(track * 4096 + logical * 256, 256), encoded);
                foreach (byte value in encoded) { writer.Byte(value); }
                Epilogue(ref writer);
                for (int count = 0; count < 16; count++) { writer.Sync(); }
            }

            while (writer.Position + 10 <= 51024) { writer.Sync(); }
            while (writer.Position < 51024) { writer.Bit(value: false); }
            disk.SetTrack(track * 4, packed, bitCount: 51024);
            if (track != 0) { disk.MapTrack(track * 4 - 1, track * 4); }
            disk.MapTrack(track * 4 + 1, track * 4);
        }

        return WozDisk.Load(disk.Export(), writable: false);
    }

    /// <summary>
    ///  Encodes one sector into 342 differential GCR nibbles and its checksum nibble.
    /// </summary>
    /// <param name="sector">Exactly 256 decoded bytes.</param>
    /// <param name="encoded">Exactly 343 output bytes.</param>
    public static void EncodeSector(ReadOnlySpan<byte> sector, Span<byte> encoded)
    {
        if (sector.Length != 256 || encoded.Length != 343)
        {
            throw new ArgumentException("Six-and-two encoding requires 256 input and 343 output bytes.");
        }

        Span<byte> values = stackalloc byte[342];
        values.Clear();
        for (int index = 0; index < 256; index++)
        {
            int pair = ((sector[index] & 1) << 1) | ((sector[index] & 2) >> 1);
            values[index % 86] |= (byte)(pair << (index / 86 * 2));
            values[86 + index] = (byte)(sector[index] >> 2);
        }

        byte previous = 0;
        for (int index = 0; index < 342; index++)
        {
            encoded[index] = Gcr[values[index] ^ previous];
            previous = values[index];
        }

        encoded[342] = Gcr[previous];
    }

    /// <summary>
    ///  Converts a 13-sector image (<c>.d13</c>) into 5-and-3 bitstreams, as DOS 3.1 to 3.2.1 format disks.
    ///  The generated media is read-only; persist writes by exporting and mounting a .woz image.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   The image holds 35 tracks of 13 sectors in the order of their numbers. Sectors are written around the
    ///   track in DOS 3.2's interleave, each number ten places after the last, between gaps of nine-bit sync
    ///   bytes.
    ///  </para>
    /// </remarks>
    /// <param name="image">Raw 3328-byte tracks.</param>
    /// <returns>Generated WOZ media.</returns>
    public static WozDisk ConvertThirteenSector(ReadOnlySpan<byte> image)
    {
        const int TrackSize = 13 * 256;
        if (image.Length % TrackSize != 0 || image.Length / TrackSize is < 35 or > 40)
        {
            throw new InvalidDataException("A 13-sector floppy image requires 35-40 complete 3328-byte tracks.");
        }

        WozDisk disk = WozDisk.CreateBlank();
        byte[] packed = new byte[(51024 + 7) / 8];
        Span<byte> encoded = stackalloc byte[411];
        for (int track = 0; track < image.Length / TrackSize; track++)
        {
            Array.Clear(packed);
            DiskBitWriter writer = new(packed);
            for (int count = 0; count < 16; count++) { writer.Sync9(); }
            for (int position = 0; position < 13; position++)
            {
                int sector = position * 10 % 13;
                writer.Byte(value: 0xD5);
                writer.Byte(value: 0xAA);
                writer.Byte(value: 0xB5);
                writer.Address(value: 254);
                writer.Address((byte)track);
                writer.Address((byte)sector);
                writer.Address((byte)(254 ^ track ^ sector));
                Epilogue(ref writer);
                for (int count = 0; count < 7; count++) { writer.Sync9(); }
                writer.Byte(value: 0xD5);
                writer.Byte(value: 0xAA);
                writer.Byte(value: 0xAD);
                EncodeSectorFiveAndThree(image.Slice((track * TrackSize) + (sector * 256), 256), encoded);
                foreach (byte value in encoded) { writer.Byte(value); }
                Epilogue(ref writer);
                for (int count = 0; count < 16; count++) { writer.Sync9(); }
            }

            while (writer.Position + 9 <= 51024) { writer.Sync9(); }
            while (writer.Position < 51024) { writer.Bit(value: true); }
            disk.SetTrack(track * 4, packed, bitCount: 51024);
            if (track != 0) { disk.MapTrack(track * 4 - 1, track * 4); }
            disk.MapTrack(track * 4 + 1, track * 4);
        }

        return WozDisk.Load(disk.Export(), writable: false);
    }

    /// <summary>
    ///  Encodes one sector into 410 differential 5-and-3 nibbles and its checksum nibble.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   Each byte's top five bits go to one of 256 nibbles; its three low bits are spread over 154 more, which
    ///   come first on the disk, last one first. Bytes are taken five at a time: the first three keep their low
    ///   bits together in one value each, and the last two's low bits are shared out one bit to each.
    ///  </para>
    /// </remarks>
    /// <param name="sector">Exactly 256 decoded bytes.</param>
    /// <param name="encoded">Exactly 411 output bytes.</param>
    public static void EncodeSectorFiveAndThree(ReadOnlySpan<byte> sector, Span<byte> encoded)
    {
        const int Group = 51;
        if (sector.Length != 256 || encoded.Length != 411)
        {
            throw new ArgumentException("Five-and-three encoding requires 256 input and 411 output bytes.");
        }

        Span<byte> threes = stackalloc byte[154];
        Span<byte> fives = stackalloc byte[256];
        for (int chunk = 0; chunk < Group; chunk++)
        {
            int index = Group - 1 - chunk;
            ReadOnlySpan<byte> bytes = sector.Slice(chunk * 5, 5);
            int fourth = bytes[3];
            int fifth = bytes[4];
            for (int part = 0; part < 5; part++) { fives[(part * Group) + index] = (byte)(bytes[part] >> 3); }

            threes[index] = (byte)(((bytes[0] & 7) << 2) | (((fourth >> 2) & 1) << 1) | ((fifth >> 2) & 1));
            threes[Group + index] = (byte)(((bytes[1] & 7) << 2) | (((fourth >> 1) & 1) << 1) | ((fifth >> 1) & 1));
            threes[(2 * Group) + index] = (byte)(((bytes[2] & 7) << 2) | ((fourth & 1) << 1) | (fifth & 1));
        }

        fives[255] = (byte)(sector[255] >> 3);
        threes[153] = (byte)(sector[255] & 7);

        byte previous = 0;
        int output = 0;
        for (int index = 153; index >= 0; index--)
        {
            encoded[output++] = Gcr53[threes[index] ^ previous];
            previous = threes[index];
        }

        for (int index = 0; index < 256; index++)
        {
            encoded[output++] = Gcr53[fives[index] ^ previous];
            previous = fives[index];
        }

        encoded[output] = Gcr53[previous];
    }

    private static void Epilogue(ref DiskBitWriter writer)
    {
        writer.Byte(value: 0xDE);
        writer.Byte(value: 0xAA);
        writer.Byte(value: 0xEB);
    }

    // The 32 nibbles of 5-and-3 encoding, by value: no two 0 bits together, and never $D5 or $AA.
    private static ReadOnlySpan<byte> Gcr53 =>
    [
        0xAB,0xAD,0xAE,0xAF,0xB5,0xB6,0xB7,0xBA,0xBB,0xBD,0xBE,0xBF,0xD6,0xD7,0xDA,0xDB,
        0xDD,0xDE,0xDF,0xEA,0xEB,0xED,0xEE,0xEF,0xF5,0xF6,0xF7,0xFA,0xFB,0xFD,0xFE,0xFF
    ];

    private static ReadOnlySpan<byte> Gcr =>
    [
        0x96,0x97,0x9A,0x9B,0x9D,0x9E,0x9F,0xA6,0xA7,0xAB,0xAC,0xAD,0xAE,0xAF,0xB2,0xB3,
        0xB4,0xB5,0xB6,0xB7,0xB9,0xBA,0xBB,0xBC,0xBD,0xBE,0xBF,0xCB,0xCD,0xCE,0xCF,0xD3,
        0xD6,0xD7,0xD9,0xDA,0xDB,0xDC,0xDD,0xDE,0xDF,0xE5,0xE6,0xE7,0xE9,0xEA,0xEB,0xEC,
        0xED,0xEE,0xEF,0xF2,0xF3,0xF4,0xF5,0xF6,0xF7,0xF9,0xFA,0xFB,0xFC,0xFD,0xFE,0xFF
    ];
}
