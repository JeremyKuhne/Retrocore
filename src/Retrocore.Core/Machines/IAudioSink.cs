// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines;

/// <summary>
///  Receives normalized floating-point PCM, ordered left, right, left, right.
/// </summary>
/// <remarks>
///  Writes are synchronous. Implementations must consume or copy the span before returning,
///  and must not retain it. The caller owns the sink and its lifetime.
/// </remarks>
public interface IAudioSink
{
    /// <summary>
    ///  Consumes a block containing complete stereo frames.
    /// </summary>
    /// <param name="interleavedStereo">The borrowed PCM block.</param>
    void WriteSamples(ReadOnlySpan<float> interleavedStereo);
}
