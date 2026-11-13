// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Buffers.Binary;

namespace Retrocore.Media;

/// <summary>
///  Caller-owned WOZ 1/2 bitstream media, parsed by chunk IDs rather than assumed chunk offsets.
///  Specification: https://applesaucefdc.com/woz/reference2/ . Flux-stream WOZ 2.1 media is
///  explicitly unsupported; it must not be mistaken for a bitstream track.
/// </summary>
public sealed class WozDisk
{
    private readonly DiskTrack?[] _tracks = new DiskTrack?[160];
    private readonly byte[] _map = new byte[160];
    private readonly byte[] _info;
    private readonly List<(uint Id, byte[] Data)> _extraChunks = [];

    private WozDisk(byte[] info, bool writable)
    {
        _info = info;
        IsReadOnly = !writable || info[2] != 0;
        OptimalBitTiming = info[0] >= 2 ? info[39] : (byte)32;
        if (OptimalBitTiming == 0) { throw new InvalidDataException("WOZ optimal bit timing cannot be zero."); }
        Array.Fill(_map, (byte)255);
    }

    /// <summary>
    ///  Gets or sets whether writes are prohibited, as the disk's write-protect notch does: at first by the caller or
    ///  the image's write-protection flag.
    /// </summary>
    public bool IsReadOnly { get; set; }

    /// <summary>
    ///  Gets the bit-cell duration in 125-nanosecond units.
    /// </summary>
    public byte OptimalBitTiming { get; }

    /// <summary>
    ///  Gets whether controller writes have changed this media.
    /// </summary>
    public bool IsDirty { get; private set; }

    /// <summary>
    ///  Gets a count that changes whenever the media changes, so a reader of its files can tell when to read them
    ///  again.
    /// </summary>
    public long Version { get; private set; }

    /// <summary>
    ///  Loads validated 5.25-inch WOZ bitstream media; no file I/O or ROM lookup is performed.
    /// </summary>
    /// <param name="image">The complete WOZ file.</param>
    /// <param name="writable">Whether the caller explicitly permits writes.</param>
    /// <returns>The independent media object.</returns>
    public static WozDisk Load(ReadOnlySpan<byte> image, bool writable = false)
    {
        bool version2 = image.Length >= 12 && image[..4].SequenceEqual("WOZ2"u8);
        if (image.Length < 12
            || (!version2 && !image[..4].SequenceEqual("WOZ1"u8))
            || !image.Slice(4, 4).SequenceEqual<byte>([255, 10, 13, 10]))
        {
            throw new InvalidDataException("Invalid WOZ header.");
        }

        uint expectedCrc = BinaryPrimitives.ReadUInt32LittleEndian(image[8..]);
        if (expectedCrc != 0 && expectedCrc != WozCrc.Compute(image[12..]))
        {
            throw new InvalidDataException("WOZ CRC-32 mismatch.");
        }

        Dictionary<uint, (int Offset, int Length)> chunks = [];
        for (int offset = 12; offset < image.Length;)
        {
            if (image.Length - offset < 8) { throw new InvalidDataException("Truncated WOZ chunk header."); }
            uint id = BinaryPrimitives.ReadUInt32LittleEndian(image[offset..]);
            uint length = BinaryPrimitives.ReadUInt32LittleEndian(image[(offset + 4)..]);
            if (length > image.Length - offset - 8) { throw new InvalidDataException("WOZ chunk exceeds the file."); }
            if (!chunks.TryAdd(id, (offset + 8, (int)length)))
            {
                throw new InvalidDataException("Duplicate WOZ chunk.");
            }

            offset += 8 + (int)length;
        }

        const uint infoId = 0x4F464E49;
        const uint mapId = 0x50414D54;
        const uint tracksId = 0x534B5254;
        if (!chunks.TryGetValue(infoId, out var infoChunk)
            || infoChunk.Length != 60
            || !chunks.TryGetValue(mapId, out var mapChunk)
            || mapChunk.Length != 160
            || !chunks.TryGetValue(tracksId, out var tracksChunk))
        {
            throw new InvalidDataException("WOZ requires INFO, TMAP and TRKS chunks of the specified sizes.");
        }

        byte[] info = image.Slice(infoChunk.Offset, 60).ToArray();
        if (info[0] is < 1 or > 3 || info[1] != 1 || (info[0] >= 2 && info[37] != 1))
        {
            throw new InvalidDataException("Only single-sided 5.25-inch WOZ images are supported.");
        }

        if (chunks.ContainsKey(0x58554C46) || (info[0] >= 3
            && (BinaryPrimitives.ReadUInt16LittleEndian(info.AsSpan(46)) != 0
                || BinaryPrimitives.ReadUInt16LittleEndian(info.AsSpan(48)) != 0)))
        {
            throw new NotSupportedException("WOZ 2.1 FLUX tracks are not bitstream tracks and are not supported.");
        }

        WozDisk disk = new(info, writable);
        image.Slice(mapChunk.Offset, 160).CopyTo(disk._map);
        foreach ((uint id, var chunk) in chunks)
        {
            if (id != infoId && id != mapId && id != tracksId)
            {
                disk._extraChunks.Add((id, image.Slice(chunk.Offset, chunk.Length).ToArray()));
            }
        }

        if (version2 && tracksChunk.Length < 160 * 8)
        {
            throw new InvalidDataException("Truncated WOZ2 track descriptors.");
        }

        if (!version2 && tracksChunk.Length % 6656 != 0)
        {
            throw new InvalidDataException("Truncated WOZ1 track records.");
        }

        for (int quarterTrack = 0; quarterTrack < 160; quarterTrack++)
        {
            int index = disk._map[quarterTrack];
            if (index == 255) { continue; }
            if (index >= 160) { throw new InvalidDataException("WOZ TMAP track index exceeds 159."); }
            if (disk._tracks[index] is not null) { continue; }
            int dataOffset;
            int byteCount;
            int bitCount;
            if (version2)
            {
                int descriptor = tracksChunk.Offset + index * 8;
                dataOffset = BinaryPrimitives.ReadUInt16LittleEndian(image[descriptor..]) * 512;
                byteCount = BinaryPrimitives.ReadUInt16LittleEndian(image[(descriptor + 2)..]) * 512;
                uint count = BinaryPrimitives.ReadUInt32LittleEndian(image[(descriptor + 4)..]);
                if (count > int.MaxValue)
                {
                    throw new InvalidDataException("WOZ track length exceeds supported memory.");
                }

                bitCount = (int)count;
                if (dataOffset < tracksChunk.Offset + 160 * 8
                    || dataOffset > tracksChunk.Offset + tracksChunk.Length - byteCount)
                {
                    throw new InvalidDataException("WOZ2 track points outside TRKS data.");
                }
            }
            else
            {
                int record = index * 6656;
                if (record > tracksChunk.Length - 6656)
                {
                    throw new InvalidDataException("WOZ1 TMAP points outside TRKS.");
                }

                dataOffset = tracksChunk.Offset + record;
                byteCount = BinaryPrimitives.ReadUInt16LittleEndian(image[(dataOffset + 6646)..]);
                bitCount = BinaryPrimitives.ReadUInt16LittleEndian(image[(dataOffset + 6648)..]);
                if (byteCount > 6646) { throw new InvalidDataException("WOZ1 bytes-used exceeds track storage."); }
            }

            if (bitCount <= 0 || bitCount > (long)byteCount * 8 || dataOffset > image.Length - byteCount)
            {
                throw new InvalidDataException("Invalid WOZ track length or extent.");
            }

            disk._tracks[index] = new(image.Slice(dataOffset, byteCount), bitCount);
        }

        return disk;
    }

    /// <summary>
    ///  Creates original blank WOZ media, suitable for formatting tests without external assets.
    /// </summary>
    /// <param name="writable">Whether formatting and writes are permitted.</param>
    /// <returns>A blank 40-track disk with no formatted tracks.</returns>
    public static WozDisk CreateBlank(bool writable = true)
    {
        byte[] info = new byte[60];
        info[0] = 2;
        info[1] = 1;
        info[4] = 1;
        info[37] = 1;
        info[38] = 1;
        info[39] = 32;
        "Retrocore original blank media"u8.CopyTo(info.AsSpan(5, 32));
        return new(info, writable);
    }

    /// <summary>
    ///  Gets a shared physical track, or null for an unformatted quarter-track.
    /// </summary>
    /// <param name="quarterTrack">The head position, zero through 159.</param>
    /// <returns>The mapped track.</returns>
    public DiskTrack? Track(int quarterTrack)
    {
        return (uint)quarterTrack >= 160
            ? throw new ArgumentOutOfRangeException(nameof(quarterTrack))
            : _map[quarterTrack] == 255 ? null : _tracks[_map[quarterTrack]];
    }

    /// <summary>
    ///  Installs a copied bitstream at a head position; adjacent mappings may be assigned separately.
    /// </summary>
    /// <param name="quarterTrack">The head position.</param>
    /// <param name="bits">Packed bits.</param>
    /// <param name="bitCount">The exact length.</param>
    public void SetTrack(int quarterTrack, ReadOnlySpan<byte> bits, int bitCount)
    {
        if ((uint)quarterTrack >= 160) { throw new ArgumentOutOfRangeException(nameof(quarterTrack)); }
        if (IsReadOnly) { throw new InvalidOperationException("WOZ media is read-only."); }
        int index = _map[quarterTrack] == 255 ? Array.FindIndex(_tracks, track => track is null) : _map[quarterTrack];
        if (index < 0) { throw new InvalidOperationException("No free WOZ track descriptor remains."); }
        _tracks[index] = new(bits, bitCount);
        _map[quarterTrack] = (byte)index;
        IsDirty = true;
        Version++;
    }

    /// <summary>
    ///  Maps an additional quarter-track to the same physical bitstream.
    /// </summary>
    /// <param name="quarterTrack">The destination head position.</param>
    /// <param name="sourceQuarterTrack">An existing formatted position.</param>
    public void MapTrack(int quarterTrack, int sourceQuarterTrack)
    {
        if ((uint)quarterTrack >= 160 || (uint)sourceQuarterTrack >= 160)
        {
            throw new ArgumentOutOfRangeException(nameof(quarterTrack));
        }

        if (IsReadOnly) { throw new InvalidOperationException("WOZ media is read-only."); }
        if (_map[sourceQuarterTrack] == 255)
        {
            throw new ArgumentException("Source track is unformatted.", nameof(sourceQuarterTrack));
        }

        _map[quarterTrack] = _map[sourceQuarterTrack];
        IsDirty = true;
        Version++;
    }

    /// <summary>
    ///  Writes one bit; a missing track is formatted with a standard-length blank bitstream.
    /// </summary>
    /// <param name="quarterTrack">The head position.</param>
    /// <param name="position">The rotational bit position.</param>
    /// <param name="transition">Whether a flux transition is present.</param>
    public void WriteBit(int quarterTrack, int position, bool transition)
    {
        if (IsReadOnly) { throw new InvalidOperationException("WOZ media is read-only."); }
        DiskTrack? track = Track(quarterTrack);
        if ((uint)position >= (track?.BitCount ?? 51024)) { throw new ArgumentOutOfRangeException(nameof(position)); }
        if (track is null)
        {
            SetTrack(quarterTrack, new byte[(51024 + 7) / 8], bitCount: 51024);
            track = Track(quarterTrack) ?? throw new InvalidOperationException("Formatting did not create a track.");
        }

        track.WriteBit(position, transition);
        IsDirty = true;
        Version++;
    }

    /// <summary>
    ///  Exports valid WOZ2 media with preserved extra chunks, track lengths, aliases and a fresh CRC.
    ///  WOZ1 inputs are upgraded to WOZ2 on export.
    /// </summary>
    /// <returns>The complete file bytes.</returns>
    public byte[] Export()
    {
        int dataSize = 0;
        foreach (DiskTrack? track in _tracks)
        {
            if (track is not null) { dataSize = checked(dataSize + ((track.Bits.Length + 511) / 512) * 512); }
        }

        int extraSize = _extraChunks.Sum(chunk => 8 + chunk.Data.Length);
        byte[] image = new byte[1536 + dataSize + extraSize];
        "WOZ2"u8.CopyTo(image);
        image[4] = 255;
        image[5] = 10;
        image[6] = 13;
        image[7] = 10;
        WriteChunk(image, offset: 12, id: 0x4F464E49, length: 60);
        _info.CopyTo(image, index: 20);
        image[20] = 2;
        image[57] = 1;
        image[59] = OptimalBitTiming;
        Array.Clear(image, 66, 14);
        WriteChunk(image, offset: 80, id: 0x50414D54, length: 160);
        _map.CopyTo(image, index: 88);
        WriteChunk(image, offset: 248, id: 0x534B5254, length: (uint)(1280 + dataSize));
        int dataOffset = 1536;
        ushort largest = 0;
        for (int index = 0; index < 160; index++)
        {
            DiskTrack? track = _tracks[index];
            if (track is null) { continue; }
            int descriptor = 256 + index * 8;
            ushort blocks = checked((ushort)((track.Bits.Length + 511) / 512));
            BinaryPrimitives.WriteUInt16LittleEndian(image.AsSpan(descriptor), checked((ushort)(dataOffset / 512)));
            BinaryPrimitives.WriteUInt16LittleEndian(image.AsSpan(descriptor + 2), blocks);
            BinaryPrimitives.WriteUInt32LittleEndian(image.AsSpan(descriptor + 4), (uint)track.BitCount);
            track.Bits.CopyTo(image.AsSpan(dataOffset));
            dataOffset += blocks * 512;
            largest = Math.Max(largest, blocks);
        }

        BinaryPrimitives.WriteUInt16LittleEndian(image.AsSpan(64), largest);
        foreach ((uint id, byte[] data) in _extraChunks)
        {
            WriteChunk(image, dataOffset, id, (uint)data.Length);
            data.CopyTo(image, dataOffset + 8);
            dataOffset += 8 + data.Length;
        }

        BinaryPrimitives.WriteUInt32LittleEndian(image.AsSpan(8), WozCrc.Compute(image.AsSpan(12)));
        return image;
    }

    /// <summary>
    ///  Acknowledges that the caller successfully persisted the exported image.
    /// </summary>
    public void MarkSaved() => IsDirty = false;

    private static void WriteChunk(Span<byte> image, int offset, uint id, uint length)
    {
        BinaryPrimitives.WriteUInt32LittleEndian(image[offset..], id);
        BinaryPrimitives.WriteUInt32LittleEndian(image[(offset + 4)..], length);
    }
}
