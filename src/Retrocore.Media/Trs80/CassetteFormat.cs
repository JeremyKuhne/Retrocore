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
///   <c>SYSTEM</c> tapes open with <c>$55</c> and a six-character name. Level I writes the block's start and end
///   addresses, high bytes first, then the bytes between and a checksum (<c>TAPE_WRITE_BLOCK</c> in Level1.asm).
///  </para>
/// </remarks>
public static class CassetteFormat
{
    private const byte Sync = 0xA5;
    private const byte BasicHeader = 0xD3;
    private const byte SystemHeader = 0x55;

    // Level I's memory starts at $4000, where its video and work areas are; a program is saved from above them.
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

        if (index < bytes.Count && bytes[index] == SystemHeader) { return CassetteContents.Level2System; }

        // Level I's addresses: a block in RAM, with its bytes on the tape after them.
        if (index + 4 > bytes.Count) { return CassetteContents.Unknown; }
        int start = (bytes[index] << 8) | bytes[index + 1];
        int end = (bytes[index + 2] << 8) | bytes[index + 3];
        return start >= Level1RamStart && end > start && index + 4 + (end - start) <= bytes.Count
            ? CassetteContents.Level1
            : CassetteContents.Unknown;
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
