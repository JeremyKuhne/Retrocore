// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines;

namespace Retrocore.Tests;

/// <summary>
///  An audio sink that keeps only the loudest sample it was given.
/// </summary>
internal sealed class PeakAudioSink : IAudioSink
{
    /// <summary>
    ///  Gets the largest sample magnitude so far.
    /// </summary>
    public float Peak { get; private set; }

    /// <inheritdoc/>
    public void WriteSamples(ReadOnlySpan<float> interleavedStereo)
    {
        foreach (float sample in interleavedStereo) { Peak = Math.Max(Peak, Math.Abs(sample)); }
    }
}
