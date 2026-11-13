// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Coco;

/// <summary>
///  The Color Computer's sound: the analog multiplexer's source while PIA 1's CB2 enables it, plus the single-bit
///  output on PIA 1's PB1, as 48 kHz stereo samples.
/// </summary>
/// <remarks>
///  <para>
///   PIA 0's CA2 and CB2 select the source: 0 the 6-bit DAC, 1 the cassette, 2 the cartridge port, 3 nothing. Each
///   sample is the level averaged over its time, then a 20 Hz high-pass filter removes the DC a speaker would.
///  </para>
/// </remarks>
public sealed class CocoAudio
{
    private const double UnitsPerSecond = CocoTiming.CrystalHertz / 8;

    private readonly float[] _buffer = new float[512];
    private readonly double _unitsPerSample;
    private readonly float _highPass;
    private IAudioSink? _sink;
    private int _count;
    private double _phase;
    private double _integral;
    private float _previous;
    private float _filtered;

    /// <summary>
    ///  Creates the sound output.
    /// </summary>
    /// <param name="sampleRate">The sample rate in hertz.</param>
    public CocoAudio(int sampleRate = 48000)
    {
        SampleRate = sampleRate;
        _unitsPerSample = UnitsPerSecond / sampleRate;
        _highPass = MathF.Exp(-2 * MathF.PI * 20 / sampleRate);
    }

    /// <summary>
    ///  Gets the sample rate in hertz.
    /// </summary>
    public int SampleRate { get; }

    /// <summary>
    ///  Gets or sets where samples go; null turns sound off.
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
    ///  Adds a span of time at a level.
    /// </summary>
    /// <param name="units">Time units.</param>
    /// <param name="level">The level, -1 to 1.</param>
    internal void Tick(int units, float level)
    {
        if (_sink is null) { return; }
        double remaining = units;
        while (_phase + remaining >= _unitsPerSample)
        {
            double part = _unitsPerSample - _phase;
            _integral += level * part;
            remaining -= part;
            Emit((float)(_integral / _unitsPerSample));
            _integral = 0;
            _phase = 0;
        }

        _integral += level * remaining;
        _phase += remaining;
    }

    /// <summary>
    ///  Sends buffered samples to the sink.
    /// </summary>
    public void Flush()
    {
        int count = _count;
        _count = 0;
        if (count != 0) { _sink?.WriteSamples(_buffer.AsSpan(0, count)); }
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
