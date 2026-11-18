// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Buffers.Binary;
using System.IO.Compression;

namespace Retrocore.Media.Acorn;

/// <summary>
///  The Unified Emulator Format for Acorn tapes: a header and a list of chunks, often gzip-compressed.
/// </summary>
/// <remarks>
///  <para>
///   The header is <c>UEF File!</c>, a zero, then the minor and major version. Each chunk is a 2-byte id, a 4-byte
///   length and its data, little-endian. The tape chunks read here: <c>&amp;0100</c> bytes with a start and a stop
///   bit, <c>&amp;0102</c> explicit bits (the first byte counts the unused bits at the end; then bits from bit 0
///   of each byte), <c>&amp;0104</c> bytes in a defined format, <c>&amp;0110</c> carrier (a count of 2400 Hz
///   cycles), <c>&amp;0111</c> carrier with a dummy <c>&amp;AA</c> byte, <c>&amp;0112</c> a gap in 1/2400 seconds,
///   <c>&amp;0114</c> security cycles, <c>&amp;0116</c> a gap in seconds as a float, and <c>&amp;0117</c> the baud
///   rate, 1200 or 300. A change of base frequency (<c>&amp;0113</c>) and phase (<c>&amp;0115</c>) are ignored, as
///   the serial ULA hears only the two tones.
///  </para>
///  <para>
///   A tape is written uncompressed, as version 0.10: bytes that are whole characters with one start and one stop
///   bit as <c>&amp;0100</c> (at 300 baud after a <c>&amp;0117</c>), runs of 2400 Hz as <c>&amp;0110</c>, anything
///   else as <c>&amp;0102</c> bits at 1200 baud or, for a lone half-cycle, <c>&amp;0114</c>, and silences as
///   <c>&amp;0112</c> or <c>&amp;0116</c>. Reading it back gives the same half-cycles.
///  </para>
/// </remarks>
public static class UefFormat
{

    private static ReadOnlySpan<byte> Magic => "UEF File!\0"u8;

    /// <summary>
    ///  Gets whether bytes are a UEF file, plain or gzip-compressed.
    /// </summary>
    /// <param name="image">The file's bytes.</param>
    /// <returns>Whether they are.</returns>
    public static bool IsUef(ReadOnlySpan<byte> image)
    {
        if (image.StartsWith(Magic)) { return true; }
        if (image.Length < 2 || image[0] != 0x1F || image[1] != 0x8B) { return false; }
        try
        {
            return Decompress(image).AsSpan().StartsWith(Magic);
        }
        catch (InvalidDataException)
        {
            return false;
        }
    }

    /// <summary>
    ///  Reads a UEF file's tape.
    /// </summary>
    /// <param name="image">The file's bytes, plain or gzip-compressed.</param>
    /// <returns>The tape.</returns>
    /// <exception cref="InvalidDataException">The file is not a UEF file.</exception>
    public static AcornTape Read(ReadOnlySpan<byte> image)
    {
        byte[] plain = image.Length >= 2 && image[0] == 0x1F && image[1] == 0x8B ? Decompress(image) : image.ToArray();
        ReadOnlySpan<byte> file = plain;
        if (!file.StartsWith(Magic) || file.Length < 12) { throw new InvalidDataException("This is not a UEF file."); }

        AcornTones tape = new();
        int position = 12;
        while (position + 6 <= file.Length)
        {
            int id = BinaryPrimitives.ReadUInt16LittleEndian(file[position..]);
            int length = (int)BinaryPrimitives.ReadUInt32LittleEndian(file[(position + 2)..]);
            position += 6;
            if (length < 0 || position + length > file.Length)
            {
                throw new InvalidDataException("A UEF chunk runs past the file.");
            }

            ReadOnlySpan<byte> data = file.Slice(position, length);
            position += length;
            switch (id)
            {
                case 0x0100:
                    foreach (byte value in data) { tape.Byte(value); }
                    break;
                case 0x0102 when length > 0:
                    int bits = ((length - 1) * 8) - data[0];
                    for (int bit = 0; bit < bits; bit++) { tape.Bit((data[1 + (bit >> 3)] & (1 << (bit & 7))) != 0); }
                    break;
                case 0x0104 when length >= 3:
                    tape.Defined(data[0], (char)data[1], (sbyte)data[2], data[3..]);
                    break;
                case 0x0110 when length >= 2:
                    tape.Carrier(BinaryPrimitives.ReadUInt16LittleEndian(data));
                    break;
                case 0x0111 when length >= 4:
                    tape.Carrier(BinaryPrimitives.ReadUInt16LittleEndian(data));
                    tape.Byte(0xAA);
                    tape.Carrier(BinaryPrimitives.ReadUInt16LittleEndian(data[2..]));
                    break;
                case 0x0112 when length >= 2:
                    tape.Gap(BinaryPrimitives.ReadUInt16LittleEndian(data) * 2);
                    break;
                case 0x0114 when length >= 5:
                    tape.Security(data);
                    break;
                case 0x0116 when length >= 4:
                    float seconds = BinaryPrimitives.ReadSingleLittleEndian(data);
                    if (float.IsFinite(seconds) && seconds > 0)
                    {
                        tape.Gap((int)Math.Round(seconds * AcornTape.UnitsPerSecond));
                    }

                    break;
                case 0x0117 when length >= 2:
                    tape.Baud = BinaryPrimitives.ReadUInt16LittleEndian(data) == 300 ? 300 : 1200;
                    break;
            }
        }

        return new AcornTape(tape.HalfCycles);
    }

    /// <summary>
    ///  Writes half-cycles as a UEF file.
    /// </summary>
    /// <param name="halfCycles">The half-cycles, in units of 1/4,800 second.</param>
    /// <returns>The file.</returns>
    public static byte[] Write(IReadOnlyList<int> halfCycles)
    {
        ArgumentNullException.ThrowIfNull(halfCycles);
        UefWriter writer = new();
        int index = 0;
        while (index < halfCycles.Count)
        {
            int length = halfCycles[index];
            if (length >= AcornTones.Silence)
            {
                writer.Gap(length);
                index++;
                continue;
            }

            // A run of whole tone cycles, up to the next silence or lone half-cycle.
            int start = index;
            List<bool> cycles = [];
            while (index + 1 < halfCycles.Count
                && halfCycles[index] < AcornTones.Silence
                && halfCycles[index] == halfCycles[index + 1])
            {
                cycles.Add(halfCycles[index] == 1);
                index += 2;
            }

            if (index == start)
            {
                writer.LoneHalf(length == 1);
                index++;
                continue;
            }

            writer.Cycles(cycles);
        }

        return writer.Finish();
    }

    private static byte[] Decompress(ReadOnlySpan<byte> image)
    {
        using MemoryStream input = new(image.ToArray());
        using GZipStream gzip = new(input, CompressionMode.Decompress);
        using MemoryStream output = new();
        gzip.CopyTo(output);
        return output.ToArray();
    }
}
