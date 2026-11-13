// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Buffers.Binary;

namespace Retrocore.Machines.Apple1;

/// <summary>
///  A cassette recording as the Apple Cassette Interface sees it: the time between each change of the tape's
///  level, in 6502 cycles.
/// </summary>
/// <remarks>
///  <para>
///   The interface turns the tape's signal into a square wave and times its half cycles, so a recording is just
///   their lengths. Recordings come from and go to WAV files; <see cref="FromData"/> makes one that the ACI's
///   R command reads.
///  </para>
/// </remarks>
public sealed class Apple1Tape
{
    // The half cycles the ACI's W command writes, in cycles: the leader's (about 860 Hz), the short one that ends
    // it, and the halves of a 1 bit (about 1080 Hz) and a 0 bit (about 2150 Hz).
    private const int LeaderHalf = 592;
    private const int SyncHalf = 180;
    private const int OneHalf = 473;
    private const int ZeroHalf = 238;

    // Seconds of leader before the data: the R command lets about two pass before it looks for the end.
    private const int LeaderSeconds = 4;

    private readonly List<int> _halves;

    /// <summary>
    ///  Creates an empty tape, to record onto.
    /// </summary>
    public Apple1Tape() => _halves = [];

    /// <summary>
    ///  Creates a tape from its half cycles.
    /// </summary>
    /// <param name="halfCycles">The length of each half cycle, in 6502 cycles.</param>
    public Apple1Tape(IEnumerable<int> halfCycles)
    {
        ArgumentNullException.ThrowIfNull(halfCycles);
        _halves = [.. halfCycles];
        if (_halves.Exists(length => length <= 0))
        {
            throw new ArgumentException("Every half cycle has a positive length.", nameof(halfCycles));
        }
    }

    /// <summary>
    ///  Gets the length of each half cycle, in 6502 cycles.
    /// </summary>
    public IReadOnlyList<int> HalfCycles => _halves;

    /// <summary>
    ///  Gets the recording's length in 6502 cycles.
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
    ///  Adds a half cycle to the end, as recording does.
    /// </summary>
    /// <param name="cycles">Its length.</param>
    internal void Add(int cycles) => _halves.Add(Math.Max(1, cycles));

    /// <summary>
    ///  Makes the recording the ACI's W command would of some bytes: a leader, the short half cycle that ends it,
    ///  then each byte's bits, most significant first.
    /// </summary>
    /// <param name="data">The bytes.</param>
    /// <returns>The tape.</returns>
    public static Apple1Tape FromData(ReadOnlySpan<byte> data)
    {
        List<int> halves = [];
        int leader = LeaderSeconds * Apple1Timing.ClockHertz / LeaderHalf;
        for (int index = 0; index < leader; index++) { halves.Add(LeaderHalf); }
        halves.Add(SyncHalf);
        halves.Add(ZeroHalf);
        foreach (byte value in data)
        {
            for (int bit = 7; bit >= 0; bit--)
            {
                int half = ((value >> bit) & 1) != 0 ? OneHalf : ZeroHalf;
                halves.Add(half);
                halves.Add(half);
            }
        }

        // A last change so the final bit's cycle ends.
        halves.Add(OneHalf);
        return new(halves);
    }

    /// <summary>
    ///  Reads a recording from a WAV file: PCM, 8 or 16 bits, the first channel of any number.
    /// </summary>
    /// <param name="wave">The file's bytes.</param>
    /// <returns>The tape.</returns>
    /// <exception cref="InvalidDataException">The file is not a PCM WAV file.</exception>
    public static Apple1Tape FromWave(ReadOnlySpan<byte> wave)
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

        // The level changes where the signal crosses its middle, with some hysteresis against noise.
        const int Hysteresis = 1024;
        List<int> halves = [];
        bool high = Sample(samples, 0, bits) >= 0;
        long last = 0;
        for (int index = 1; index < count; index++)
        {
            int value = Sample(samples, index * frame, bits);
            if (high ? value > -Hysteresis : value < Hysteresis) { continue; }
            high = !high;
            long cycle = (long)index * Apple1Timing.ClockHertz / rate;
            halves.Add((int)Math.Max(1, cycle - last));
            last = cycle;
        }

        return new(halves);
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
        long samples = (Cycles * rate / Apple1Timing.ClockHertz) + 1;
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
        bool high = true;
        foreach (int half in _halves)
        {
            cycle += half;
            long end = cycle * rate / Apple1Timing.ClockHertz;
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
