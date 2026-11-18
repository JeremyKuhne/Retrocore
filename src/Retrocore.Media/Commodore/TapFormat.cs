// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Buffers.Binary;

namespace Retrocore.Media.Commodore;

/// <summary>
///  Reads and writes TAP images, the raw Commodore tape format of CCS64 and VICE: <c>C64-TAPE-RAW</c>, a version
///  byte, the machine and video standard, the data's length, and a byte per pulse.
/// </summary>
/// <remarks>
///  <para>
///   A byte is the pulse's length in units of 8 of the machine's clock cycles; in version 1 a zero is followed by
///   the length in cycles, in 3 bytes, low first, and in version 0 a zero is a pause longer than 255 units. Version
///   2, which counts half waves for the C16, is not read. The clock comes from the header: the C64's 985,248 or
///   1,022,730 Hz, the VIC-20's 1,108,405 or 1,022,730 Hz, the C16's 886,724 or 894,886 Hz, and the PET's
///   1,000,000 Hz.
///  </para>
///  <para>
///   Images are written as version 1 for the PET, so a byte is 8 µs. MAME reads every TAP image at the C64's PAL
///   clock, so it plays a PET image 1.5% slow, which Commodore's loaders allow.
///  </para>
/// </remarks>
public static class TapFormat
{
    /// <summary>
    ///  The machine byte of a PET image.
    /// </summary>
    public const byte PetMachine = 3;

    /// <summary>
    ///  The longest pulse an image holds, in microseconds: a zero's three bytes of cycles, about 16.8 seconds.
    /// </summary>
    public const int LongestPulse = 0xFF_FFFF;

    private const int HeaderLength = 20;
    private static ReadOnlySpan<byte> Signature => "C64-TAPE-RAW"u8;

    /// <summary>
    ///  Gets whether bytes start as a TAP image does.
    /// </summary>
    /// <param name="image">The bytes.</param>
    /// <returns>Whether they have the signature.</returns>
    public static bool IsTap(ReadOnlySpan<byte> image) => image.StartsWith(Signature);

    /// <summary>
    ///  Reads a TAP image.
    /// </summary>
    /// <param name="image">The file's bytes.</param>
    /// <returns>The tape.</returns>
    /// <exception cref="InvalidDataException">The image is not a TAP image of version 0 or 1.</exception>
    public static CommodoreTape Read(ReadOnlySpan<byte> image)
    {
        if (image.Length < HeaderLength || !IsTap(image))
        {
            throw new InvalidDataException("The file is not a TAP image: it does not start C64-TAPE-RAW.");
        }

        byte version = image[12];
        if (version > 1)
        {
            throw new InvalidDataException($"TAP version {version} is not supported; versions 0 and 1 are.");
        }

        double clock = Clock(image[13], image[14]);
        int length = (int)Math.Min(BinaryPrimitives.ReadUInt32LittleEndian(image[16..]), (uint)(image.Length - HeaderLength));
        ReadOnlySpan<byte> data = image.Slice(HeaderLength, length);
        List<int> pulses = [];
        for (int i = 0; i < data.Length; i++)
        {
            long cycles;
            if (data[i] != 0)
            {
                cycles = data[i] * 8;
            }
            else if (version == 0)
            {
                cycles = 256 * 8;
            }
            else
            {
                if (i + 3 >= data.Length) { break; }
                cycles = data[i + 1] | (data[i + 2] << 8) | (data[i + 3] << 16);
                i += 3;
                if (cycles == 0) { continue; }
            }

            pulses.Add((int)Math.Max(1, Math.Round(cycles * 1_000_000 / clock)));
        }

        return new(pulses);
    }

    /// <summary>
    ///  Writes pulses as a version 1 TAP image for the PET: a byte of 8 µs units for a pulse up to 2,040 µs, and a
    ///  zero and the exact length for a longer one or one that is not a multiple of 8.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   A pulse longer than <see cref="LongestPulse"/> is written as that; <see cref="CommodoreTapeCodec"/> lists it
    ///   as a loss.
    ///  </para>
    /// </remarks>
    /// <param name="pulses">The pulses, in microseconds.</param>
    /// <returns>The image.</returns>
    public static byte[] Write(IReadOnlyList<int> pulses)
    {
        ArgumentNullException.ThrowIfNull(pulses);
        List<byte> data = [];
        foreach (int pulse in pulses)
        {
            if (pulse % 8 == 0 && pulse / 8 is > 0 and < 256)
            {
                data.Add((byte)(pulse / 8));
            }
            else
            {
                int cycles = Math.Min(pulse, LongestPulse);
                data.Add(0);
                data.Add((byte)cycles);
                data.Add((byte)(cycles >> 8));
                data.Add((byte)(cycles >> 16));
            }
        }

        byte[] image = new byte[HeaderLength + data.Count];
        Signature.CopyTo(image);
        image[12] = 1;
        image[13] = PetMachine;
        BinaryPrimitives.WriteUInt32LittleEndian(image.AsSpan(16), (uint)data.Count);
        data.CopyTo(image, HeaderLength);
        return image;
    }

    private static double Clock(byte machine, byte video) => machine switch
    {
        1 => video == 1 ? 1_022_730 : 1_108_405,
        2 => video == 1 ? 894_886 : 886_724,
        PetMachine => 1_000_000,
        _ => video == 1 ? 1_022_730 : 985_248
    };
}
