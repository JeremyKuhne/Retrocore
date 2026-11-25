// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media.Trs80;

/// <summary>
///  Reads what a CAS tape holds from its first recording.
/// </summary>
/// <remarks>
///  <para>
///   Every TRS-80 ROM writes a leader of zero bytes and the <c>$A5</c> sync byte; what follows differs. Level II's
///   <c>CSAVE</c> writes three <c>$D3</c> bytes and a one-character name (<c>ST_CSAVE</c> in Level2.asm), and its
///   <c>SYSTEM</c> tapes open with <c>$55</c>, a six-character name and a <c>$3C</c> data block (or the <c>$78</c>
///   entry address). Level I writes the block's start and end addresses, high bytes first, then the bytes between and
///   a checksum that makes the bytes sum to zero (<c>TAPE_WRITE_BLOCK</c> in Level1.asm). The headers can coincide,
///   so this is a likely reading, not a certain one: a Level I block at <c>$55xx</c> whose next six bytes read as a
///   name and whose fourth data byte is <c>$3C</c> or <c>$78</c> reads as a <c>SYSTEM</c> tape.
///  </para>
/// </remarks>
public static class CassetteFormat
{
    private const byte Sync = 0xA5;
    private const byte BasicHeader = 0xD3;
    private const byte SystemHeader = 0x55;
    private const int SystemNameLength = 6;
    private const byte SystemData = 0x3C;
    private const byte SystemEntry = 0x78;

    // Level I's RAM starts at $4000, above its video at $3C00; its CSAVE saves the program from $4200.
    private const int Level1RamStart = 0x4000;

    /// <summary>
    ///  Reads what a tape holds.
    /// </summary>
    /// <param name="bytes">The tape's bytes.</param>
    /// <returns>What its first recording is, or <see cref="CassetteContents.Unknown"/>.</returns>
    public static CassetteContents Detect(IReadOnlyList<byte> bytes)
    {
        ArgumentNullException.ThrowIfNull(bytes);
        int index = 0;
        while (index < bytes.Count && bytes[index] == 0) { index++; }

        // No leader, or something other than the sync byte after it, such as a 1500 baud tape's $55 leader.
        if (index == 0 || index >= bytes.Count || bytes[index] != Sync) { return CassetteContents.Unknown; }
        index++;

        if (Repeats(bytes, index, BasicHeader, 3)) { return CassetteContents.Level2Basic; }

        // A SYSTEM tape's $55 and printable six-character name are followed by its first data block or its entry
        // address, which tells most Level I blocks that start at $55xx from one.
        if (IsSystemHeader(bytes, index))
        {
            return CassetteContents.Level2System;
        }

        // Level I's addresses: a block in RAM, with its bytes on the tape after them and a checksum that makes them
        // sum to zero, which tells a Level I block from a Level II data tape's first record.
        if (index + 4 > bytes.Count) { return CassetteContents.Unknown; }
        int start = (bytes[index] << 8) | bytes[index + 1];
        int end = (bytes[index + 2] << 8) | bytes[index + 3];
        int checksum = index + 4 + (end - start);
        if (start < Level1RamStart || end <= start || checksum >= bytes.Count) { return CassetteContents.Unknown; }
        int sum = 0;
        for (int i = index + 4; i <= checksum; i++) { sum += bytes[i]; }
        return (sum & 0xFF) == 0 ? CassetteContents.Level1 : CassetteContents.Unknown;
    }

    // Whether a SYSTEM tape's header starts at index: $55, the name, then a data block or the entry address.
    private static bool IsSystemHeader(IReadOnlyList<byte> bytes, int index)
    {
        int first = index + 1 + SystemNameLength;
        if (first >= bytes.Count || bytes[index] != SystemHeader) { return false; }
        return (bytes[first] is SystemData or SystemEntry) && IsName(bytes, index + 1, SystemNameLength);
    }

    // Whether count bytes from index are a name: a printable character, then printable characters or $00 padding,
    // as the loader compares only the characters typed.
    private static bool IsName(IReadOnlyList<byte> bytes, int index, int count)
    {
        if (bytes[index] is < 0x21 or > 0x7E) { return false; }
        for (int i = index + 1; i < index + count; i++)
        {
            if (bytes[i] is not 0 and (< 0x20 or > 0x7E)) { return false; }
        }

        return true;
    }

    // Whether count bytes from index are all value.
    private static bool Repeats(IReadOnlyList<byte> bytes, int index, byte value, int count)
    {
        if (index + count > bytes.Count) { return false; }
        for (int i = index; i < index + count; i++)
        {
            if (bytes[i] != value) { return false; }
        }

        return true;
    }
}
