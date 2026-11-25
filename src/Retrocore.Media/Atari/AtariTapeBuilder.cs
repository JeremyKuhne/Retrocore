// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media.Atari;

/// <summary>
///  Makes cassette files as the OS's <c>C:</c> handler writes them: a long leader, then 132-byte records, then an
///  end-of-file record.
/// </summary>
/// <remarks>
///  <para>
///   Each record (OS User's Manual, cassette handler) is two <c>$55</c> bytes the handler times to find the baud
///   rate, a control byte (<c>$FC</c> a full record, <c>$FA</c> a part-full one whose last data byte is its count,
///   <c>$FE</c> the end of the file), 128 data bytes, and a checksum: the carry-wrapped sum of the 131 bytes before
///   it.
///  </para>
/// </remarks>
public static class AtariTapeBuilder
{
    /// <summary>
    ///  The leader the OS writes before a file's first record, in milliseconds.
    /// </summary>
    public const int Leader = 20_000;

    /// <summary>
    ///  Makes the records of a file.
    /// </summary>
    /// <param name="data">The file's bytes.</param>
    /// <param name="gap">
    ///  The gap before each record after the first, in milliseconds: about 250 for the short gaps the OS uses when the
    ///  computer keeps up, about 3,000 for the long ones it uses otherwise.
    /// </param>
    /// <param name="baud">The baud rate.</param>
    /// <returns>The blocks: one record for each 128 bytes or part, then the end-of-file record.</returns>
    public static IReadOnlyList<AtariTapeBlock> File(ReadOnlySpan<byte> data, int gap = 250, int baud = AtariTape.StandardBaud)
    {
        List<AtariTapeBlock> blocks = [];
        int offset = 0;
        while (offset < data.Length)
        {
            int length = Math.Min(128, data.Length - offset);
            byte[] record = new byte[128];
            data.Slice(offset, length).CopyTo(record);
            byte control = 0xFC;
            if (length < 128)
            {
                control = 0xFA;
                record[127] = (byte)length;
            }

            blocks.Add(Record(blocks.Count == 0 ? Leader : gap, baud, control, record));
            offset += length;
        }

        blocks.Add(Record(blocks.Count == 0 ? Leader : gap, baud, 0xFE, new byte[128]));
        return blocks;
    }

    /// <summary>
    ///  Makes a boot tape: the OS loads its records at the address in the first six bytes, as a power-on with START
    ///  held does.
    /// </summary>
    /// <param name="program">
    ///  The program, starting with the boot header: a flags byte, the number of records, the load address and the
    ///  initialization address (low byte first), then the code the OS calls at the load address plus 6.
    /// </param>
    /// <returns>The tape.</returns>
    public static AtariTape BootTape(ReadOnlySpan<byte> program) => new(File(program), "Boot tape");

    private static AtariTapeBlock Record(int gap, int baud, byte control, ReadOnlySpan<byte> data)
    {
        byte[] bytes = new byte[132];
        bytes[0] = 0x55;
        bytes[1] = 0x55;
        bytes[2] = control;
        data.CopyTo(bytes.AsSpan(3));
        int sum = 0;
        for (int i = 0; i < 131; i++)
        {
            sum += bytes[i];
            if (sum > 0xFF) { sum = (sum & 0xFF) + 1; }
        }

        bytes[131] = (byte)sum;
        return new(gap, baud, bytes, Durations: null);
    }
}
