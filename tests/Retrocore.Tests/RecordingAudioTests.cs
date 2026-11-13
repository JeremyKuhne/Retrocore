// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines;

namespace Retrocore.Tests;

/// <summary>
///  Synchronously counts PCM and captures a bounded prefix without allocating during writes.
/// </summary>
internal sealed class RecordingAudioTests : IAudioSink
{
    private readonly float[] _samples = new float[16384];
    private int _captured;

    /// <summary>
    ///  Gets the number of complete stereo frames received.
    /// </summary>
    internal long Frames { get; private set; }

    /// <summary>
    ///  Gets the number of synchronous block writes.
    /// </summary>
    internal int Writes { get; private set; }

    /// <summary>
    ///  Gets the last block's float count.
    /// </summary>
    internal int LastBlockLength { get; private set; }

    /// <summary>
    ///  Gets whether every block contained complete frames and at most 512 floats.
    /// </summary>
    internal bool ValidBlocks { get; private set; } = true;

    /// <summary>
    ///  Gets the captured prefix.
    /// </summary>
    internal ReadOnlySpan<float> Samples => _samples.AsSpan(0, _captured);

    /// <summary>
    ///  Copies the available prefix and updates counters.
    /// </summary>
    /// <param name="interleavedStereo">The borrowed stereo samples.</param>
    public void WriteSamples(ReadOnlySpan<float> interleavedStereo)
    {
        Frames += interleavedStereo.Length / 2;
        Writes++;
        LastBlockLength = interleavedStereo.Length;
        ValidBlocks &= interleavedStereo.Length is > 0 and <= 512 && (interleavedStereo.Length & 1) == 0;
        int count = Math.Min(interleavedStereo.Length, _samples.Length - _captured);
        interleavedStereo[..count].CopyTo(_samples.AsSpan(_captured));
        _captured += count;
    }
}
