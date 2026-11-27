// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Trs80Model100;

/// <summary>
///  The Model 100's sound: its piezo buzzer, as 48 kHz stereo.
/// </summary>
/// <remarks>
///  <para>
///   Each sample is the buzzer's level averaged over its time, then a 20 Hz high-pass filter removes the DC the
///   buzzer would not make.
///  </para>
/// </remarks>
public sealed class Trs80Model100Audio
{
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
    ///  Creates the sound output.
    /// </summary>
    /// <param name="sampleRate">The sample rate in hertz, at most a sample a CPU cycle.</param>
    /// <exception cref="ArgumentOutOfRangeException">The rate is not 1 to the CPU's clock.</exception>
    public Trs80Model100Audio(int sampleRate = 48000)
    {
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(sampleRate);
        ArgumentOutOfRangeException.ThrowIfGreaterThan(sampleRate, Trs80Model100Timing.ClockHertz);
        SampleRate = sampleRate;
        _cyclesPerSample = (double)Trs80Model100Timing.ClockHertz / sampleRate;
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
    ///  Sends buffered samples to the sink.
    /// </summary>
    public void Flush()
    {
        int count = _count;
        _count = 0;
        if (count != 0) { _sink?.WriteSamples(_buffer.AsSpan(0, count)); }
    }

    /// <summary>
    ///  Adds one CPU cycle at a level.
    /// </summary>
    /// <param name="high">Whether the buzzer's input is high.</param>
    internal void Tick(bool high)
    {
        if (_sink is null) { return; }
        float level = high ? 0.5f : -0.5f;
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
