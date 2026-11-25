// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Atari;

/// <summary>
///  Finds and identifies the 810's 2 KB firmware.
/// </summary>
/// <remarks>
///  <para>
///   Revisions B and C differ only in the order they format a track's sectors: C writes sector 18, then the odd
///   sectors, then the even ones (9:1); B writes them 13 apart (13:1). C is the common one and MAME's default.
///   Revision E adds commands that run code on the drive (Altirra Hardware Reference Manual, 10.9).
///  </para>
/// </remarks>
public static class Atari810Firmware
{
    /// <summary>
    ///  MAME's <c>atari810</c> name for revision C's chip.
    /// </summary>
    public const string RevisionCFile = "8229_c68168_c011299c-03.bin";

    /// <summary>
    ///  MAME's <c>atari810</c> name for revision B's chip.
    /// </summary>
    public const string RevisionBFile = "810rom_b.bin";

    private const uint RevisionBCrc = 0x19227D33;
    private const uint RevisionCCrc = 0x0896F03D;
    private const uint RevisionECrc = 0xAAD220F4;

    /// <summary>
    ///  Loads the firmware from a folder holding MAME's <c>atari810</c> set, unzipped: revision C if it's there, else
    ///  revision B.
    /// </summary>
    /// <param name="directory">The folder.</param>
    /// <returns>The firmware, or null if neither chip is there.</returns>
    public static byte[]? LoadFromDirectory(string directory)
    {
        ArgumentNullException.ThrowIfNull(directory);
        foreach (string name in (ReadOnlySpan<string>)[RevisionCFile, RevisionBFile])
        {
            string path = Path.Join(directory, name);
            if (File.Exists(path)) { return File.ReadAllBytes(path); }
        }

        return null;
    }

    /// <summary>
    ///  Identifies a firmware's revision from its CRC-32.
    /// </summary>
    /// <param name="rom">The firmware.</param>
    /// <returns><c>'B'</c>, <c>'C'</c>, <c>'E'</c>, or <c>'?'</c> for one it doesn't know.</returns>
    public static char Revision(ReadOnlySpan<byte> rom) => Crc32(rom) switch
    {
        RevisionBCrc => 'B',
        RevisionCCrc => 'C',
        RevisionECrc => 'E',
        _ => '?'
    };

    private static uint Crc32(ReadOnlySpan<byte> data)
    {
        uint crc = 0xFFFFFFFF;
        foreach (byte value in data)
        {
            crc ^= value;
            for (int bit = 0; bit < 8; bit++)
            {
                crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
            }
        }

        return ~crc;
    }
}
