// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Buffers.Binary;

namespace Retrocore.Media.Commodore;

/// <summary>
///  Reads a Commodore tape from a WAV recording, and writes one as a square wave.
/// </summary>
/// <remarks>
///  <para>
///   The Datasette's read line is high while the signal is above its middle, and a pulse runs from one fall to the
///   next, as MAME and the PET's tape routines see it. A written pulse is low for its first half and high for its
///   second; the file starts with a sample of high and ends with one of low, so the first and last pulses have falls
///   at both ends and read back with the rest.
///  </para>
/// </remarks>
public static class CommodoreWave
{
    private const int Microsecond = 1_000_000;

    /// <summary>
    ///  Gets whether bytes start as a WAV file does.
    /// </summary>
    /// <param name="image">The bytes.</param>
    /// <returns>Whether they start <c>RIFF</c>, then <c>WAVE</c>.</returns>
    public static bool IsWave(ReadOnlySpan<byte> image) =>
        image.Length >= 12 && image[..4].SequenceEqual("RIFF"u8) && image.Slice(8, 4).SequenceEqual("WAVE"u8);

    /// <summary>
    ///  Reads a recording: PCM, 8 or 16 bits, the first channel of any number.
    /// </summary>
    /// <param name="wave">The file's bytes.</param>
    /// <returns>The tape.</returns>
    /// <exception cref="InvalidDataException">The file is not a PCM WAV file.</exception>
    public static CommodoreTape Read(ReadOnlySpan<byte> wave)
    {
        if (!IsWave(wave)) { throw new InvalidDataException("The file is not a WAV file."); }

        int channels = 0;
        int rate = 0;
        int bits = 0;
        ReadOnlySpan<byte> samples = default;
        int offset = 12;
        while (offset + 8 <= wave.Length)
        {
            ReadOnlySpan<byte> id = wave.Slice(offset, 4);
            uint declared = BinaryPrimitives.ReadUInt32LittleEndian(wave[(offset + 4)..]);
            int available = wave.Length - offset - 8;
            bool needed = id.SequenceEqual("fmt "u8) || id.SequenceEqual("data"u8);

            // A cut-short format or sample chunk would read as a shorter tape; any other chunk is skipped anyway.
            if (needed && declared > (uint)available)
            {
                throw new InvalidDataException(
                    $"The WAV file's {System.Text.Encoding.ASCII.GetString(id).Trim()} chunk says {declared} bytes, but only {available} follow.");
            }

            int size = (int)Math.Min(declared, (uint)available);
            ReadOnlySpan<byte> body = wave.Slice(offset + 8, size);
            if (id.SequenceEqual("fmt "u8) && size >= 16)
            {
                if (BinaryPrimitives.ReadUInt16LittleEndian(body) != 1)
                {
                    throw new InvalidDataException("Only PCM WAV files are supported.");
                }

                channels = BinaryPrimitives.ReadUInt16LittleEndian(body[2..]);
                rate = BinaryPrimitives.ReadInt32LittleEndian(body[4..]);
                bits = BinaryPrimitives.ReadUInt16LittleEndian(body[14..]);
            }
            else if (id.SequenceEqual("data"u8))
            {
                samples = body;
            }

            offset += 8 + size + (size & 1);
        }

        if (channels < 1 || rate <= 0 || bits is not (8 or 16))
        {
            throw new InvalidDataException("The WAV file must be 8 or 16-bit PCM.");
        }

        int frame = channels * bits / 8;
        int count = samples.Length / frame;
        List<int> pulses = [];
        if (count == 0) { return new(pulses); }

        // The level changes where the signal crosses its middle, with a little hysteresis against noise.
        const int Hysteresis = 256;
        bool high = Sample(samples, 0, bits) > 0;
        long lastFall = -1;
        for (int index = 1; index < count; index++)
        {
            int value = Sample(samples, index * frame, bits);
            if (high ? value > -Hysteresis : value <= Hysteresis) { continue; }
            high = !high;
            if (high) { continue; }

            long time = (long)index * Microsecond / rate;
            if (lastFall >= 0) { pulses.Add((int)Math.Max(1, time - lastFall)); }
            lastFall = time;
        }

        return new(pulses);
    }

    /// <summary>
    ///  Writes a tape as a 16-bit mono WAV file of a square wave.
    /// </summary>
    /// <param name="pulses">The pulses, in microseconds.</param>
    /// <param name="rate">The sample rate.</param>
    /// <returns>The file's bytes.</returns>
    public static byte[] Write(IReadOnlyList<int> pulses, int rate = 44100)
    {
        ArgumentNullException.ThrowIfNull(pulses);
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(rate);
        const short Amplitude = 16000;
        long total = 0;
        foreach (int pulse in pulses) { total += pulse; }

        // A sample of high before the first fall, and one of low after the last, so each pulse lies between two falls.
        long count = Position(total) + 2;
        byte[] wave = new byte[44 + (count * 2)];
        Span<byte> span = wave;
        "RIFF"u8.CopyTo(span);
        BinaryPrimitives.WriteInt32LittleEndian(span[4..], wave.Length - 8);
        "WAVEfmt "u8.CopyTo(span[8..]);
        BinaryPrimitives.WriteInt32LittleEndian(span[16..], 16);
        BinaryPrimitives.WriteInt16LittleEndian(span[20..], 1);
        BinaryPrimitives.WriteInt16LittleEndian(span[22..], 1);
        BinaryPrimitives.WriteInt32LittleEndian(span[24..], rate);
        BinaryPrimitives.WriteInt32LittleEndian(span[28..], rate * 2);
        BinaryPrimitives.WriteInt16LittleEndian(span[32..], 2);
        BinaryPrimitives.WriteInt16LittleEndian(span[34..], 16);
        "data"u8.CopyTo(span[36..]);
        BinaryPrimitives.WriteInt32LittleEndian(span[40..], (int)(count * 2));

        // Each change lands on the sample its time falls in, so lengths do not drift. The level starts high, so the
        // first pulse begins with a fall, and ends low, so the last one ends with one.
        long sample = 0;
        long time = 0;
        Fill(span, ref sample, Position(0), Amplitude);
        foreach (int pulse in pulses)
        {
            Fill(span, ref sample, Position(time + (pulse / 2)), -Amplitude);
            time += pulse;
            Fill(span, ref sample, Position(time), Amplitude);
        }

        Fill(span, ref sample, count, -Amplitude);
        return wave;

        // The sample a time in microseconds lands on, after the first sample's high.
        long Position(long microseconds) => 1 + (microseconds * rate / Microsecond);

        static void Fill(Span<byte> span, ref long sample, long end, short level)
        {
            for (; sample < end; sample++)
            {
                BinaryPrimitives.WriteInt16LittleEndian(span[(int)(44 + (sample * 2))..], level);
            }
        }
    }

    // A sample as a signed 16-bit value.
    private static int Sample(ReadOnlySpan<byte> samples, int offset, int bits) => bits == 8
        ? (samples[offset] - 128) << 8
        : BinaryPrimitives.ReadInt16LittleEndian(samples[offset..]);
}
