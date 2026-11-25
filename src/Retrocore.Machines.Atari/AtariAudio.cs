// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Atari;

/// <summary>
///  The machine's sound: POKEY's four channels and the console speaker that <c>CONSOL</c> bit 3 drives, mixed to the
///  television's one channel and resampled for an <see cref="IAudioSink"/>.
/// </summary>
public sealed class AtariAudio
{
    private readonly AtariBus _bus;
    private readonly float[] _buffer = new float[512];
    private readonly double _cyclesPerSample;
    private readonly float _highPass;
    private IAudioSink? _sink;
    private int _count;
    private double _phase;
    private double _integral;
    private float _previous;
    private float _filtered;

    /// <summary>
    ///  Constructs the sound.
    /// </summary>
    /// <param name="bus">The bus with POKEY and GTIA.</param>
    /// <param name="sampleRate">Samples a second.</param>
    internal AtariAudio(AtariBus bus, int sampleRate = 48000)
    {
        _bus = bus;
        SampleRate = sampleRate;
        _cyclesPerSample = (double)AtariTiming.CpuHertz(bus.Standard) / sampleRate;
        _highPass = MathF.Exp(-2 * MathF.PI * 20 / sampleRate);
    }

    /// <summary>
    ///  Gets the samples a second.
    /// </summary>
    public int SampleRate { get; }

    /// <summary>
    ///  Gets or sets where the samples go, interleaved stereo; null to stop.
    /// </summary>
    public IAudioSink? Sink
    {
        get => _sink;
        set
        {
            if (ReferenceEquals(_sink, value)) { return; }
            _sink = value;
            _count = 0;
            _phase = 0;
            _integral = 0;
            _previous = 0;
            _filtered = 0;
        }
    }

    /// <summary>
    ///  Gets the level now: POKEY's channels and the speaker, 0 to 1.
    /// </summary>
    public float Level => (_bus.Pokey.Output * (0.8f / 60)) + (_bus.Gtia.Speaker ? 0.2f : 0);

    /// <summary>
    ///  Sends the samples so far to the sink.
    /// </summary>
    public void Flush()
    {
        int count = _count;
        _count = 0;
        if (count != 0) { _sink?.WriteSamples(_buffer.AsSpan(0, count)); }
    }

    /// <summary>
    ///  Takes the level for a machine cycle.
    /// </summary>
    internal void Tick()
    {
        if (_sink is null) { return; }
        float level = Level;
        if (_phase + 1 >= _cyclesPerSample)
        {
            double part = _cyclesPerSample - _phase;
            _integral += level * part;
            Emit((float)(_integral / _cyclesPerSample));
            _phase = 1 - part;
            _integral = level * _phase;
            return;
        }

        _integral += level;
        _phase += 1;
    }

    private void Emit(float sample)
    {
        _filtered = _highPass * (_filtered + (sample - _previous));
        _previous = sample;
        float value = Math.Clamp(_filtered, -1, 1);
        _buffer[_count++] = value;
        _buffer[_count++] = value;
        if (_count == _buffer.Length) { Flush(); }
    }
}
