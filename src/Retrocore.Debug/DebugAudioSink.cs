// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Runtime.InteropServices;
using Retrocore.Machines;

namespace Retrocore.Debug;

/// <summary>
///  Collects a machine's audio between display frames as 16-bit PCM, for the display panel to play.
/// </summary>
/// <remarks>
///  <para>
///   The panel only plays in time when the machine runs at its real speed; the run loop sends what has collected
///   with each frame. While nothing drains it, such as when stepping, only the latest second is kept.
///  </para>
/// </remarks>
/// <param name="channels">1 to mix to mono, as for the speaker alone; 2 for stereo, as for the Mockingboard.</param>
/// <param name="sampleRate">The samples per second the machine's audio produces.</param>
internal sealed class DebugAudioSink(int channels, int sampleRate) : IAudioSink
{
    private readonly List<short> _samples = new(sampleRate * channels / 10);

    /// <summary>
    ///  Gets the channels each sample frame holds.
    /// </summary>
    public int Channels { get; } = channels;

    /// <summary>
    ///  Gets the sample frames per second.
    /// </summary>
    public int SampleRate { get; } = sampleRate;

    /// <inheritdoc/>
    public void WriteSamples(ReadOnlySpan<float> interleavedStereo)
    {
        for (int index = 0; index + 1 < interleavedStereo.Length; index += 2)
        {
            if (Channels == 1)
            {
                _samples.Add(Pcm((interleavedStereo[index] + interleavedStereo[index + 1]) / 2));
            }
            else
            {
                _samples.Add(Pcm(interleavedStereo[index]));
                _samples.Add(Pcm(interleavedStereo[index + 1]));
            }
        }

        int limit = SampleRate * Channels;
        if (_samples.Count > limit) { _samples.RemoveRange(0, _samples.Count - limit); }
    }

    /// <summary>
    ///  Takes what has collected since the last call.
    /// </summary>
    /// <returns>The samples as base64 little-endian 16-bit PCM, interleaved when stereo, or null for none.</returns>
    public string? Take()
    {
        if (_samples.Count == 0) { return null; }
        string pcm = Convert.ToBase64String(MemoryMarshal.AsBytes(CollectionsMarshal.AsSpan(_samples)));
        _samples.Clear();
        return pcm;
    }

    private static short Pcm(float sample) => (short)(Math.Clamp(sample, -1f, 1f) * short.MaxValue);
}
