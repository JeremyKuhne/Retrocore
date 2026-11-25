// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media.Atari;

/// <summary>
///  A block of an Atari cassette: a gap of mark tone, then a record's bytes at a baud rate or, for raw tone, a run of
///  alternating space and mark durations.
/// </summary>
/// <param name="Gap">The gap of mark tone before the block, in milliseconds.</param>
/// <param name="Baud">The bytes' rate in bits a second.</param>
/// <param name="Data">
///  The record's bytes, each sent as ten bits: a start bit, the bits low first and a stop bit.
/// </param>
/// <param name="Durations">
///  For raw tone, the durations in tenths of a millisecond of alternating space (0) and mark (1), space first; or
///  null for a record.
/// </param>
public sealed record AtariTapeBlock(int Gap, int Baud, byte[] Data, ushort[]? Durations)
{
    /// <summary>
    ///  Gets the block's length in seconds, gap included.
    /// </summary>
    public double Duration => (Gap / 1000.0) + (Durations is not null
        ? (Ends() is [.., long last] ? last : 0) / 10_000.0
        : Data.Length * 10.0 / Baud);

    /// <summary>
    ///  Gets the level of the data line at a time into the block: 1 for mark, 0 for space.
    /// </summary>
    /// <param name="seconds">The time since the block's gap began.</param>
    /// <returns>The level; mark past the block's end.</returns>
    public bool LevelAt(double seconds)
    {
        double time = seconds - (Gap / 1000.0);
        if (time < 0) { return true; }
        if (Durations is not null)
        {
            // The run each time falls in, found among the runs' ends; even runs are space, odd mark.
            long[] ends = Ends();
            double tenths = time * 10_000;
            int low = 0;
            int high = ends.Length;
            while (low < high)
            {
                int middle = (low + high) / 2;
                if (tenths < ends[middle]) { high = middle; } else { low = middle + 1; }
            }

            return low >= ends.Length || (low & 1) != 0;
        }

        long bit = (long)(time * Baud);
        long index = bit / 10;
        if (index >= Data.Length) { return true; }
        return (bit % 10) switch
        {
            0 => false,
            9 => true,
            long position => ((Data[index] >> (int)(position - 1)) & 1) != 0
        };
    }

    // Where each raw-tone run ends, in tenths of a millisecond from the block's data, worked out once per array:
    // the recorder asks every machine cycle.
    private long[] Ends()
    {
        if (_ends is { } cached && ReferenceEquals(cached.Source, Durations)) { return cached.Ends; }
        ushort[] durations = Durations ?? [];
        long[] ends = new long[durations.Length];
        long total = 0;
        for (int i = 0; i < durations.Length; i++)
        {
            total += durations[i];
            ends[i] = total;
        }

        _ends = (durations, ends);
        return ends;
    }

    private (ushort[] Source, long[] Ends)? _ends;
}
