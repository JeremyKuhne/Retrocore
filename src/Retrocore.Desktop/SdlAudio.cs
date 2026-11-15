// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using SDL3;
using System.Text.Json.Nodes;
using Touki;

namespace Retrocore.Desktop;

/// <summary>
///  Plays a machine's 16-bit PCM through SDL3, opening the device for the first sound's rate and channels.
/// </summary>
internal sealed class SdlAudio : DisposableBase
{
    // More queued than this and the sound lags the picture: what is queued is dropped.
    private const double MaximumQueuedSeconds = 0.25;

    // The silence a stream starts with, and starts again with after running dry.
    private const double PrimeSeconds = 0.04;

    private IntPtr _stream;
    private int _rate;
    private int _channels;
    private bool _started;
    private bool _failed;
    private float _volume = 0.5f;

    /// <summary>
    ///  Gets whether the device is open.
    /// </summary>
    internal bool IsOpen => _stream != IntPtr.Zero;

    /// <summary>
    ///  Gets the number of times the queue ran dry after sound started.
    /// </summary>
    internal int Underruns { get; private set; }

    /// <summary>
    ///  Gets or sets the volume, 0 to 1.
    /// </summary>
    internal float Volume
    {
        get => _volume;
        set
        {
            _volume = Math.Clamp(value, 0, 1);
            if (_stream != IntPtr.Zero) { SDL.SetAudioStreamGain(_stream, _volume); }
        }
    }

    /// <summary>
    ///  Queues the sound a machine's <c>TakeAudio</c> gave.
    /// </summary>
    /// <param name="audio">The <c>rate</c>, <c>channels</c> and base64 <c>samples</c>.</param>
    internal void Queue(JsonObject audio)
    {
        int rate = audio["rate"]?.GetValue<int>() ?? 0;
        int channels = audio["channels"]?.GetValue<int>() ?? 0;
        string? samples = audio["samples"]?.GetValue<string>();
        if (rate <= 0 || channels <= 0 || samples is null || _failed) { return; }
        if (rate != _rate || channels != _channels) { Open(rate, channels); }
        if (_stream == IntPtr.Zero) { return; }

        int queued = SDL.GetAudioStreamQueued(_stream);
        if (_started && queued == 0) { Underruns++; }
        if (queued > rate * channels * 2 * MaximumQueuedSeconds) { SDL.ClearAudioStream(_stream); }

        // A stream starts with a little silence, so the run thread's few milliseconds between batches never leave
        // the device with nothing to play.
        if (!_started || queued == 0)
        {
            byte[] silence = new byte[(int)(rate * PrimeSeconds) * channels * 2];
            SDL.PutAudioStreamData(_stream, silence, silence.Length);
        }

        byte[] bytes = Convert.FromBase64String(samples);
        SDL.PutAudioStreamData(_stream, bytes, bytes.Length);
        _started = true;
    }

    /// <summary>
    ///  Drops queued sound, as when the speed changes.
    /// </summary>
    internal void Clear()
    {
        if (_stream != IntPtr.Zero) { SDL.ClearAudioStream(_stream); }
        _started = false;
    }

    private void Open(int rate, int channels)
    {
        Close();
        if (!SDL.InitSubSystem(SDL.InitFlags.Audio))
        {
            _failed = true;
            return;
        }

        SDL.AudioSpec spec = new() { Format = SDL.AudioFormat.AudioS16LE, Channels = channels, Freq = rate };
        _stream = SDL.OpenAudioDeviceStream(SDL.AudioDeviceDefaultPlayback, in spec, callback: null, IntPtr.Zero);
        if (_stream == IntPtr.Zero || !SDL.ResumeAudioStreamDevice(_stream))
        {
            _failed = true;
            Close();
            return;
        }

        _rate = rate;
        _channels = channels;
        SDL.SetAudioStreamGain(_stream, _volume);
    }

    private void Close()
    {
        if (_stream != IntPtr.Zero) { SDL.DestroyAudioStream(_stream); }
        _stream = IntPtr.Zero;
        _started = false;
    }

    /// <inheritdoc/>
    protected override void Dispose(bool disposing)
    {
        if (disposing) { Close(); }
    }
}