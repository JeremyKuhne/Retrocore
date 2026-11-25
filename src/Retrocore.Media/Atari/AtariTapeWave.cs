// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Buffers.Binary;

namespace Retrocore.Media.Atari;

/// <summary>
///  Writes an <see cref="AtariTape"/> as the sound on the tape: the 410's frequency shift keying, mark at 5,327 Hz
///  and space at 3,995 Hz, as a mono 16-bit WAV file, which recorders and MAME play.
/// </summary>
public static class AtariTapeWave
{
    /// <summary>
    ///  The mark (1) tone in hertz.
    /// </summary>
    public const double MarkHertz = 5327;

    /// <summary>
    ///  The space (0) tone in hertz.
    /// </summary>
    public const double SpaceHertz = 3995;

    /// <summary>
    ///  Writes the tape as a WAV file.
    /// </summary>
    /// <param name="tape">The tape.</param>
    /// <param name="sampleRate">Samples a second.</param>
    /// <returns>The file.</returns>
    public static byte[] Write(AtariTape tape, int sampleRate = 44_100)
    {
        ArgumentNullException.ThrowIfNull(tape);
        double duration = tape.Duration + 0.5;
        int samples = (int)(duration * sampleRate);
        byte[] file = new byte[44 + (samples * 2)];
        Span<byte> span = file;
        "RIFF"u8.CopyTo(span);
        BinaryPrimitives.WriteInt32LittleEndian(span[4..], file.Length - 8);
        "WAVEfmt "u8.CopyTo(span[8..]);
        BinaryPrimitives.WriteInt32LittleEndian(span[16..], 16);
        BinaryPrimitives.WriteInt16LittleEndian(span[20..], 1);
        BinaryPrimitives.WriteInt16LittleEndian(span[22..], 1);
        BinaryPrimitives.WriteInt32LittleEndian(span[24..], sampleRate);
        BinaryPrimitives.WriteInt32LittleEndian(span[28..], sampleRate * 2);
        BinaryPrimitives.WriteInt16LittleEndian(span[32..], 2);
        BinaryPrimitives.WriteInt16LittleEndian(span[34..], 16);
        "data"u8.CopyTo(span[36..]);
        BinaryPrimitives.WriteInt32LittleEndian(span[40..], samples * 2);

        // The tone's phase runs on across level changes, as the 410's oscillator's does.
        int block = 0;
        double blockStart = 0;
        double phase = 0;
        for (int sample = 0; sample < samples; sample++)
        {
            double time = (double)sample / sampleRate;
            while (block < tape.Blocks.Count && time - blockStart >= tape.Blocks[block].Duration)
            {
                blockStart += tape.Blocks[block].Duration;
                block++;
            }

            bool mark = block >= tape.Blocks.Count || tape.Blocks[block].LevelAt(time - blockStart);
            phase += (mark ? MarkHertz : SpaceHertz) / sampleRate;
            phase -= Math.Floor(phase);
            short value = (short)(Math.Sin(phase * 2 * Math.PI) * 16_000);
            BinaryPrimitives.WriteInt16LittleEndian(span[(44 + (sample * 2))..], value);
        }

        return file;
    }
}
