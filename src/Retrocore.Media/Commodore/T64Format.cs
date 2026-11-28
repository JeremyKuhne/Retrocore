// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Buffers.Binary;

namespace Retrocore.Media.Commodore;

/// <summary>
///  Reads a C64S T64 program archive as a Commodore cassette, synthesizing a standard tape recording of each
///  program in directory order.
/// </summary>
/// <remarks>
///  See <see href="https://ist.uwaterloo.ca/~schepers/formats/T64.TXT">Peter Schepers's T64 format notes</see>.
///  T64 does not store pulses. Only normal records (type 1) with PRG file types or the legacy program markers
///  <c>$01</c> and <c>$44</c> can be played; archives containing other active entries are refused.
///  The CONV64 end address <c>$C3C6</c> is repaired only when its declared length is impossible.
/// </remarks>
public static class T64Format
{
    private const int HeaderSize = 64;
    private const int EntrySize = 32;
    private const int MaximumPulses = 16 * 1024 * 1024;
    private const int Conv64EndAddress = 0xC3C6;

    /// <summary>
    ///  Gets whether the bytes start with a known T64 signature.
    /// </summary>
    /// <param name="image">The file's bytes.</param>
    /// <returns>Whether the signature is known.</returns>
    public static bool IsT64(ReadOnlySpan<byte> image)
    {
        if (image.StartsWith("C64S tape image file"u8)) { return true; }
        return image.StartsWith("C64S tape file"u8) || image.StartsWith("C64 tape image file"u8);
    }

    /// <summary>
    ///  Reads a T64 image, preserving its programs' names, load addresses and bytes.
    /// </summary>
    /// <param name="image">The file's bytes.</param>
    /// <returns>A tape with the programs in directory order.</returns>
    /// <exception cref="InvalidDataException">
    ///  The image is invalid, holds an unsupported entry, or is too large to expand into cassette pulses.
    /// </exception>
    public static CommodoreTape Read(ReadOnlySpan<byte> image)
    {
        if (!IsT64(image) || image.Length < HeaderSize)
        {
            throw new InvalidDataException("The file does not have a complete T64 header.");
        }

        // Some legacy single-program archives left either count unset.
        int slots = Math.Max(1, (int)BinaryPrimitives.ReadUInt16LittleEndian(image[0x22..]));
        int used = Math.Max(1, (int)BinaryPrimitives.ReadUInt16LittleEndian(image[0x24..]));
        int directoryEnd = HeaderSize + (slots * EntrySize);
        if (used > slots || directoryEnd > image.Length)
        {
            throw new InvalidDataException("The T64 image has an invalid or truncated directory.");
        }

        List<(int Index, int Offset, ushort Start, int End)> entries = [];
        for (int index = 0; index < slots; index++)
        {
            ReadOnlySpan<byte> record = Record(image, index);
            if (record[0] == 0) { continue; }
            if (record[0] != 1)
            {
                throw new InvalidDataException($"T64 entry {index + 1} is not a normal tape file.");
            }

            byte fileType = record[1];
            if (fileType is not (0x01 or 0x44) && (CbmDosFileType)(fileType & 0x07) != CbmDosFileType.Program)
            {
                throw new InvalidDataException($"T64 entry {index + 1} has unsupported CBM file type ${fileType:X2}; only programs can be played.");
            }

            ushort start = BinaryPrimitives.ReadUInt16LittleEndian(record[2..]);
            int end = BinaryPrimitives.ReadUInt16LittleEndian(record[4..]);
            uint offset = BinaryPrimitives.ReadUInt32LittleEndian(record[8..]);
            if (offset < directoryEnd || offset >= image.Length)
            {
                throw new InvalidDataException($"T64 entry {index + 1} points outside the program data.");
            }

            entries.Add((index, (int)offset, start, end == 0 ? 0x10000 : end));
        }

        if (entries.Count != used)
        {
            throw new InvalidDataException("The T64 image has no programs or its used entry count is incorrect.");
        }

        // Check the physical extents without changing the order in which the programs will play.
        entries.Sort(static (left, right) => left.Offset.CompareTo(right.Offset));
        long pulseCount = 0;
        for (int i = 0; i < entries.Count; i++)
        {
            var entry = entries[i];
            int available = (i + 1 < entries.Count ? entries[i + 1].Offset : image.Length) - entry.Offset;
            int length = entry.End - entry.Start;
            if (entry.End == Conv64EndAddress && (length <= 0 || length > available))
            {
                // CONV64 wrote a fixed end address, but a valid extent ending there can be followed by padding.
                length = available;
            }

            if (length <= 0 || length > available || length > 0x10000 - entry.Start)
            {
                throw new InvalidDataException($"T64 entry {entry.Index + 1} has an invalid or truncated program.");
            }

            entry.End = entry.Start + length;
            entries[i] = entry;
            pulseCount += CommodoreTapeBuilder.ProgramPulseCount(length);
        }

        if (pulseCount > MaximumPulses)
        {
            throw new InvalidDataException("The T64 image contains too much program data to expand into a cassette.");
        }

        entries.Sort(static (left, right) => left.Index.CompareTo(right.Index));
        List<int> pulses = [];
        pulses.EnsureCapacity((int)pulseCount);
        foreach (var (index, offset, start, end) in entries)
        {
            CommodoreTapeBuilder.AppendProgram(pulses, Record(image, index)[16..], start, image.Slice(offset, end - start));
        }

        return new(pulses);
    }

    private static ReadOnlySpan<byte> Record(ReadOnlySpan<byte> image, int index) =>
        image.Slice(HeaderSize + (index * EntrySize), EntrySize);
}
