// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Buffers.Binary;

namespace Retrocore.Machines.Trs80Model100;

/// <summary>
///  A cassette recording as the Model 100 sees it: the level the tape starts at, and the time between each change of
///  level after it, in the 80C85's cycles while the motor runs.
/// </summary>
/// <remarks>
///  <para>
///   The ROM writes a tape through SOD, a cycle of 2400 Hz for a 1 bit and of 1200 Hz for a 0, and reads it through
///   SID by timing the level's changes, so a recording is the length of each half cycle. Recordings come from and go
///   to WAV files.
///  </para>
/// </remarks>
public sealed class Trs80Model100Tape
{
    private readonly List<int> _halves;

    /// <summary>
    ///  Creates an empty tape, to record onto.
    /// </summary>
    public Trs80Model100Tape() => _halves = [];

    /// <summary>
    ///  Creates a tape from its half cycles.
    /// </summary>
    /// <param name="startsHigh">Whether the level before the first change is high.</param>
    /// <param name="halfCycles">The length of each half cycle, in the 80C85's cycles.</param>
    /// <exception cref="ArgumentException">A half cycle is not a positive length.</exception>
    public Trs80Model100Tape(bool startsHigh, IEnumerable<int> halfCycles)
    {
        ArgumentNullException.ThrowIfNull(halfCycles);
        StartsHigh = startsHigh;
        _halves = [.. halfCycles];
        if (_halves.Exists(length => length <= 0))
        {
            throw new ArgumentException("Every half cycle has a positive length.", nameof(halfCycles));
        }
    }

    /// <summary>
    ///  Gets whether the level before the first change is high.
    /// </summary>
    public bool StartsHigh { get; private set; }

    /// <summary>
    ///  Gets the length of each half cycle, in the 80C85's cycles.
    /// </summary>
    public IReadOnlyList<int> HalfCycles => _halves;

    /// <summary>
    ///  Gets the recording's length in the 80C85's cycles.
    /// </summary>
    public long Cycles
    {
        get
        {
            long total = 0;
            foreach (int half in _halves) { total += half; }
            return total;
        }
    }

    /// <summary>
    ///  Sets the level a recording starts at, before its first change.
    /// </summary>
    /// <param name="high">The level.</param>
    internal void Start(bool high)
    {
        if (_halves.Count == 0) { StartsHigh = high; }
    }

    /// <summary>
    ///  Adds a half cycle to a recording.
    /// </summary>
    /// <param name="cycles">Its length.</param>
    internal void Add(long cycles) => _halves.Add((int)Math.Clamp(cycles, 1, int.MaxValue));

    /// <summary>
    ///  Reads a recording from a WAV file: PCM (or WAVE_FORMAT_EXTENSIBLE's PCM), 8 or 16 bits, the first channel of
    ///  any number.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   The level changes where the signal crosses its middle, with some hysteresis against noise, as the Model
    ///   100's input comparator does; a file that starts silent starts low.
    ///  </para>
    /// </remarks>
    /// <param name="wave">The file's bytes.</param>
    /// <returns>The tape.</returns>
    /// <exception cref="InvalidDataException">The file is not an 8 or 16-bit PCM WAV file.</exception>
    public static Trs80Model100Tape FromWave(ReadOnlySpan<byte> wave)
    {
        if (wave.Length < 12 || !wave[..4].SequenceEqual("RIFF"u8) || !wave.Slice(8, 4).SequenceEqual("WAVE"u8))
        {
            throw new InvalidDataException("The file is not a WAV file.");
        }

        int channels = 0;
        int rate = 0;
        int bits = 0;
        ReadOnlySpan<byte> samples = default;
        int offset = 12;
        while (offset + 8 <= wave.Length)
        {
            ReadOnlySpan<byte> id = wave.Slice(offset, 4);
            int size = (int)Math.Min(BinaryPrimitives.ReadUInt32LittleEndian(wave[(offset + 4)..]), (uint)(wave.Length - offset - 8));
            ReadOnlySpan<byte> body = wave.Slice(offset + 8, size);
            if (id.SequenceEqual("fmt "u8) && size >= 16)
            {
                // PCM, or WAVE_FORMAT_EXTENSIBLE with the PCM subformat.
                int format = BinaryPrimitives.ReadUInt16LittleEndian(body);
                if (format == 0xFFFE && size >= 26) { format = BinaryPrimitives.ReadUInt16LittleEndian(body[24..]); }
                if (format != 1)
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
        if (count == 0) { return new(); }

        const int Hysteresis = 1024;
        List<int> halves = [];
        bool high = Sample(samples, 0, bits) > Hysteresis;
        bool startsHigh = high;
        long last = 0;
        for (int index = 1; index < count; index++)
        {
            int value = Sample(samples, index * frame, bits);
            if (high ? value > -Hysteresis : value < Hysteresis) { continue; }
            high = !high;
            long cycle = (long)index * Trs80Model100Timing.ClockHertz / rate;
            halves.Add((int)Math.Max(1, cycle - last));
            last = cycle;
        }

        return new(startsHigh, halves);
    }

    /// <summary>
    ///  Writes the recording as a 16-bit mono WAV file of a square wave.
    /// </summary>
    /// <param name="rate">The sample rate.</param>
    /// <returns>The file's bytes.</returns>
    public byte[] ToWave(int rate = 44100)
    {
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(rate);
        const short Amplitude = 16000;
        long samples = (Cycles * rate / Trs80Model100Timing.ClockHertz) + 1;
        byte[] wave = new byte[44 + (samples * 2)];
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
        BinaryPrimitives.WriteInt32LittleEndian(span[40..], (int)(samples * 2));

        // Each change lands on the sample its cycle falls in, so lengths do not drift.
        long sample = 0;
        long cycle = 0;
        bool high = StartsHigh;
        foreach (int half in _halves)
        {
            cycle += half;
            long end = cycle * rate / Trs80Model100Timing.ClockHertz;
            for (; sample < end; sample++)
            {
                BinaryPrimitives.WriteInt16LittleEndian(span[(int)(44 + (sample * 2))..], high ? Amplitude : (short)-Amplitude);
            }

            high = !high;
        }

        for (; sample < samples; sample++)
        {
            BinaryPrimitives.WriteInt16LittleEndian(span[(int)(44 + (sample * 2))..], high ? Amplitude : (short)-Amplitude);
        }

        return wave;
    }

    // A sample as a signed 16-bit value.
    private static int Sample(ReadOnlySpan<byte> samples, int offset, int bits) => bits == 8
        ? (samples[offset] - 128) << 8
        : BinaryPrimitives.ReadInt16LittleEndian(samples[offset..]);
}
