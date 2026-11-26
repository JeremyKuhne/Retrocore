// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media.Acorn;

/// <summary>
///  Records files on a tape as the BBC Micro's cassette filing system saves them.
/// </summary>
/// <remarks>
///  <para>
///   Each file starts with 1,500 cycles of carrier, a dummy byte and 1,500 more, then its blocks of up to 256 bytes,
///   each after 600 cycles of carrier. A block is a synchronisation byte (<c>&amp;2A</c>), a header and its CRC, then
///   the data and its CRC. The header: the name and a zero, the load and execution addresses, the block number and
///   length (low bytes first), the block flag (bit 0 locked, bit 6 no data, bit 7 the last block) and four spare
///   bytes. The CRCs are the MOS's (the Advanced User Guide's, section 16.10), high byte first; the header's leaves
///   out the synchronisation byte. Two seconds of silence follow each file.
///  </para>
/// </remarks>
public static class AcornTapeBuilder
{
    private const int BlockSize = 256;

    /// <summary>
    ///  Records files on a blank tape.
    /// </summary>
    /// <param name="files">The files, in order.</param>
    /// <param name="baud">The baud rate, 1200 or 300 (*TAPE12 or *TAPE3).</param>
    /// <returns>The tape.</returns>
    /// <exception cref="ArgumentException">
    ///  A name is empty, too long or holds a zero, or the rate is neither.
    /// </exception>
    public static AcornTape Build(IEnumerable<AcornTapeFile> files, int baud = 1200)
    {
        ArgumentNullException.ThrowIfNull(files);
        if (baud is not (300 or 1200))
        {
            throw new ArgumentException("The cassette runs at 1200 or 300 baud.", nameof(baud));
        }

        AcornTones tones = new() { Baud = baud };
        foreach (AcornTapeFile file in files)
        {
            if (file.Name.Length is 0 or > 10 || file.Name.Contains('\0', StringComparison.Ordinal))
            {
                throw new ArgumentException(
                    $"'{file.Name}' is not a cassette file name: 1-10 characters.",
                    nameof(files));
            }

            tones.Carrier(1500);
            tones.Byte(0xAA);
            tones.Carrier(1500);
            int blocks = Math.Max(1, (file.Data.Length + BlockSize - 1) / BlockSize);
            for (int block = 0; block < blocks; block++)
            {
                if (block > 0) { tones.Carrier(600); }
                int start = block * BlockSize;
                int length = Math.Min(BlockSize, file.Data.Length - start);
                int flag = file.Locked ? 0x01 : 0;
                if (length == 0) { flag |= 0x40; }
                if (block == blocks - 1) { flag |= 0x80; }

                List<byte> header = [.. System.Text.Encoding.ASCII.GetBytes(file.Name), 0];
                Address(header, file.LoadAddress);
                Address(header, file.ExecutionAddress);
                header.Add((byte)block);
                header.Add((byte)(block >> 8));
                header.Add((byte)length);
                header.Add((byte)(length >> 8));
                header.Add((byte)flag);
                header.AddRange([0, 0, 0, 0]);

                tones.Byte(0x2A);
                foreach (byte value in header) { tones.Byte(value); }
                Crc(tones, header.ToArray());
                if (length == 0) { continue; }
                ReadOnlySpan<byte> data = file.Data.AsSpan(start, length);
                foreach (byte value in data) { tones.Byte(value); }
                Crc(tones, data);
            }

            tones.Carrier(600);
            tones.Gap(2 * AcornTape.UnitsPerSecond);
        }

        return new AcornTape(tones.HalfCycles);
    }

    /// <summary>
    ///  Records files on a blank tape and writes it as a UEF file, which <see cref="UefFormat.Read"/> reads back as
    ///  the same tape.
    /// </summary>
    /// <param name="files">The files, in order.</param>
    /// <param name="baud">The baud rate, 1200 or 300 (*TAPE12 or *TAPE3).</param>
    /// <returns>The UEF file's bytes, uncompressed.</returns>
    /// <exception cref="ArgumentException">
    ///  A name is empty, too long or holds a zero, or the rate is neither.
    /// </exception>
    public static byte[] BuildUef(IEnumerable<AcornTapeFile> files, int baud = 1200) =>
        UefFormat.Write(Build(files, baud).HalfCycles);

    /// <summary>
    ///  Computes the cassette filing system's CRC: CRC-16 with polynomial <c>&amp;1021</c>, from zero.
    /// </summary>
    /// <param name="bytes">The bytes.</param>
    /// <returns>The CRC.</returns>
    public static ushort Crc(ReadOnlySpan<byte> bytes)
    {
        int crc = 0;
        foreach (byte value in bytes)
        {
            crc ^= value << 8;
            for (int bit = 0; bit < 8; bit++)
            {
                crc = (crc & 0x8000) != 0 ? (crc << 1) ^ 0x1021 : crc << 1;
            }
        }

        return (ushort)crc;
    }

    private static void Address(List<byte> header, uint address)
    {
        for (int shift = 0; shift < 32; shift += 8) { header.Add((byte)(address >> shift)); }
    }

    private static void Crc(AcornTones tones, ReadOnlySpan<byte> bytes)
    {
        ushort crc = Crc(bytes);
        tones.Byte((byte)(crc >> 8));
        tones.Byte((byte)crc);
    }
}
