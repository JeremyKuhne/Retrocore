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
///   Images are written as version 1 for the machine their header names, the one that recorded them unless they are
///   saved back to an image read from another's: for the PET a byte is 8 µs, for the VIC-20 8 of its cycles. MAME reads every TAP image at the C64's PAL clock, so it plays a PET image 1.5% slow, which
///   Commodore's loaders allow, an NTSC VIC-20 image 3.7% slow and a PAL one 11% slow.
///  </para>
/// </remarks>
public static class TapFormat
{
    /// <summary>
    ///  The machine byte of a C64 image.
    /// </summary>
    public const byte C64Machine = 0;

    /// <summary>
    ///  The machine byte of a VIC-20 image.
    /// </summary>
    public const byte Vic20Machine = 1;

    /// <summary>
    ///  The machine byte of a PET image.
    /// </summary>
    public const byte PetMachine = 3;

    /// <summary>
    ///  The video byte of a PAL machine's image.
    /// </summary>
    public const byte Pal = 0;

    /// <summary>
    ///  The video byte of an NTSC machine's image.
    /// </summary>
    public const byte Ntsc = 1;

    /// <summary>
    ///  The longest pulse a PET image holds, in microseconds: a zero's three bytes of cycles, about 16.8 seconds. Other
    ///  machines' images hold <see cref="Longest(byte, byte)"/>.
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
    /// <exception cref="InvalidDataException">
    ///  The image is not a TAP image of version 0 or 1, or is cut short.
    /// </exception>
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
        uint declared = BinaryPrimitives.ReadUInt32LittleEndian(image[16..]);
        if (declared > (uint)(image.Length - HeaderLength))
        {
            throw new InvalidDataException(
                $"The TAP image says it holds {declared} bytes of pulses, but only {image.Length - HeaderLength} follow its header.");
        }

        ReadOnlySpan<byte> data = image.Slice(HeaderLength, (int)declared);
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
                if (i + 3 >= data.Length)
                {
                    throw new InvalidDataException("The TAP image ends inside a pulse's three-byte length.");
                }

                cycles = data[i + 1] | (data[i + 2] << 8) | (data[i + 3] << 16);
                i += 3;
                if (cycles == 0) { continue; }
            }

            pulses.Add(Math.Max(1, Microseconds(cycles, clock)));
        }

        return new(pulses);
    }

    /// <summary>
    ///  Writes pulses as a version 1 TAP image for a machine: a byte of 8 cycles' units where that reads back as the
    ///  same pulse, and otherwise a zero and the length in cycles. For the PET, whose cycle is a microsecond, that is
    ///  a byte for a multiple of 8 µs up to 2,040 µs.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   The PET's and the VIC-20's cycles are no longer than a microsecond, so their images hold each pulse exactly.
    ///   A pulse longer than <see cref="Longest"/> is written as that; <see cref="CommodoreTapeCodec"/> lists it as a
    ///   loss.
    ///  </para>
    /// </remarks>
    /// <param name="pulses">The pulses, in microseconds.</param>
    /// <param name="machine">The header's machine byte, such as <see cref="PetMachine"/>.</param>
    /// <param name="video">The header's video byte, <see cref="Pal"/> or <see cref="Ntsc"/>.</param>
    /// <returns>The image.</returns>
    public static byte[] Write(IReadOnlyList<int> pulses, byte machine = PetMachine, byte video = Pal)
    {
        ArgumentNullException.ThrowIfNull(pulses);
        double clock = Clock(machine, video);
        List<byte> data = [];
        foreach (int pulse in pulses)
        {
            long cycles = Math.Min((long)Math.Round(pulse * clock / 1_000_000), 0xFF_FFFF);
            long units = (long)Math.Round(cycles / 8.0);
            if (units is > 0 and < 256 && Microseconds(units * 8, clock) == pulse)
            {
                data.Add((byte)units);
            }
            else
            {
                data.Add(0);
                data.Add((byte)cycles);
                data.Add((byte)(cycles >> 8));
                data.Add((byte)(cycles >> 16));
            }
        }

        byte[] image = new byte[HeaderLength + data.Count];
        Signature.CopyTo(image);
        image[12] = 1;
        image[13] = machine;
        image[14] = video;
        BinaryPrimitives.WriteUInt32LittleEndian(image.AsSpan(16), (uint)data.Count);
        data.CopyTo(image, HeaderLength);
        return image;
    }

    /// <summary>
    ///  Gets the longest pulse a machine's image holds, in microseconds: a zero's three bytes of cycles.
    /// </summary>
    /// <param name="machine">The header's machine byte.</param>
    /// <param name="video">The header's video byte.</param>
    /// <returns>
    ///  The length: <see cref="LongestPulse"/> for the PET, and from about 15 seconds (the PAL VIC-20's) to about 19
    ///  (the C16's) for the others.
    /// </returns>
    public static int Longest(byte machine, byte video) => Microseconds(0xFF_FFFF, Clock(machine, video));

    /// <summary>
    ///  Gets the clock a header names, in hertz.
    /// </summary>
    /// <param name="machine">The header's machine byte.</param>
    /// <param name="video">The header's video byte.</param>
    /// <returns>The clock: the C64's for a machine byte it does not know.</returns>
    public static double Clock(byte machine, byte video) => machine switch
    {
        Vic20Machine => video == Ntsc ? 1_022_730 : 1_108_405,
        2 => video == Ntsc ? 894_886 : 886_724,
        PetMachine => 1_000_000,
        _ => video == Ntsc ? 1_022_730 : 985_248
    };

    private static int Microseconds(long cycles, double clock) => (int)Math.Round(cycles * 1_000_000 / clock);
}
