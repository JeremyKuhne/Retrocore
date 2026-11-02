// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Apple2;
using SDL3;
using System.Runtime.InteropServices;
using Touki;

namespace AppleSharp;

/// <summary>
///  Caller-owned SDL3 float/stereo output. SDL copies each batch; no emulator span is retained.
/// </summary>
internal sealed class SdlAudioSink : DisposableBase, IAudioSink
{
    private readonly IntPtr _stream;

    /// <summary>
    ///  Opens and starts the default output device with SDL's native conversion.
    /// </summary>
    /// <param name="sampleRate">The emulator's PCM sample rate.</param>
    internal SdlAudioSink(int sampleRate)
    {
        SDL.AudioSpec spec = new() { Format = SDL.AudioFormat.AudioF32LE, Channels = 2, Freq = sampleRate };
        _stream = SDL.OpenAudioDeviceStream(SDL.AudioDeviceDefaultPlayback, in spec, callback: null, IntPtr.Zero);
        if (_stream == IntPtr.Zero) { throw new InvalidOperationException("SDL3 audio: " + SDL.GetError()); }
        if (!SDL.ResumeAudioStreamDevice(_stream))
        {
            string error = SDL.GetError();
            SDL.DestroyAudioStream(_stream);
            throw new InvalidOperationException("SDL3 audio: " + error);
        }
    }

    /// <inheritdoc/>
    public void WriteSamples(ReadOnlySpan<float> interleavedStereo)
    {
        ObjectDisposedException.ThrowIf(Disposed, this);
        ReadOnlySpan<byte> bytes = MemoryMarshal.AsBytes(interleavedStereo);
        if (!SDL.PutAudioStreamData(_stream, bytes, bytes.Length))
        {
            throw new InvalidOperationException("SDL3 audio queue: " + SDL.GetError());
        }
    }

    /// <summary>
    ///  Removes queued sound when the user pauses, resets, mutes or changes the emulated machine.
    /// </summary>
    internal void Clear()
    {
        if (!SDL.ClearAudioStream(_stream))
        {
            throw new InvalidOperationException("SDL3 audio clear: " + SDL.GetError());
        }
    }

    /// <inheritdoc/>
    protected override void Dispose(bool disposing)
    {
        if (disposing) { SDL.DestroyAudioStream(_stream); }
    }
}
