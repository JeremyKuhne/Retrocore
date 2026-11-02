// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Apple2;

/// <summary>
///  Integrates speaker and Mockingboard levels into stereo PCM at 1,020,500 CPU clocks/second.
/// </summary>
/// <remarks>
///  Each CPU level is held for one clock and integrated over exact fractional sample boundaries.
///  A 20 Hz high-pass removes DC; each AY side has half the output headroom, as does the speaker.
///  This is a box-filter resampler, not a model of the analog speaker or reconstruction circuit.
///  No audio is buffered while no sink is attached. Members are used on the emulation thread.
/// </remarks>
public sealed class Apple2Audio
{
    private readonly AudioSampleClock _clock;
    private readonly float[] _buffer = new float[512];
    private readonly float _highPass;
    private IAudioSink? _sink;
    private int _count;
    private double _leftIntegral;
    private double _rightIntegral;
    private float _previousLeft;
    private float _previousRight;
    private float _filteredLeft;
    private float _filteredRight;

    /// <summary>
    ///  Creates an allocation-free per-cycle mixer.
    /// </summary>
    /// <param name="sampleRate">PCM frames/second, from 1 through 1,020,500.</param>
    public Apple2Audio(int sampleRate = 48000)
    {
        _clock = new(sampleRate);
        SampleRate = sampleRate;
        _highPass = MathF.Exp(-2 * MathF.PI * 20 / sampleRate);
    }

    /// <summary>
    ///  Gets the PCM frame rate.
    /// </summary>
    public int SampleRate { get; }

    /// <summary>
    ///  Gets or sets whether the Mockingboard's two AY chips are mixed in. Without them only the speaker sounds,
    ///  and the AYs' output, three channels each worked out every cycle, is never read.
    /// </summary>
    public bool MixMockingboard { get; set; } = true;

    /// <summary>
    ///  Gets or sets the caller-owned synchronous sink. Changing it discards queued PCM
    ///  and filter history without changing the fractional clock.
    /// </summary>
    public IAudioSink? Sink
    {
        get => _sink;
        set
        {
            if (ReferenceEquals(_sink, value))
            {
                return;
            }

            _sink = value;
            ClearSignal();
        }
    }

    /// <summary>
    ///  Integrates one CPU clock, reading the Mockingboard's levels only when a sink will hear them and they are
    ///  mixed in.
    /// </summary>
    /// <param name="speaker">The current speaker latch.</param>
    /// <param name="mockingboard">The Mockingboard whose AY levels to mix.</param>
    public void Tick(bool speaker, Mockingboard mockingboard)
    {
        if (_sink is null)
        {
            _clock.Tick();
            return;
        }

        if (!MixMockingboard)
        {
            Tick(speaker, 0, 0);
            return;
        }

        Tick(speaker, mockingboard.Left, mockingboard.Right);
    }

    /// <summary>
    ///  Integrates one CPU clock. AY inputs are normalized unipolar levels from zero to one.
    /// </summary>
    /// <param name="speaker">The current speaker latch.</param>
    /// <param name="left">Left AY level.</param>
    /// <param name="right">Right AY level.</param>
    public void Tick(bool speaker, float left, float right)
    {
        int phase = _clock.Phase;
        bool sampleReady = _clock.Tick();
        if (_sink is null)
        {
            return;
        }

        float speakerLevel = speaker ? 0.5f : -0.5f;
        left = speakerLevel + (left * 0.5f);
        right = speakerLevel + (right * 0.5f);
        int weight = sampleReady ? AudioSampleClock.ClockRate - phase : SampleRate;
        _leftIntegral += left * (double)weight;
        _rightIntegral += right * (double)weight;
        if (!sampleReady)
        {
            return;
        }

        float sampleLeft = (float)(_leftIntegral / AudioSampleClock.ClockRate);
        float sampleRight = (float)(_rightIntegral / AudioSampleClock.ClockRate);
        _leftIntegral = left * (double)_clock.Phase;
        _rightIntegral = right * (double)_clock.Phase;
        _filteredLeft = _highPass * (_filteredLeft + (sampleLeft - _previousLeft));
        _filteredRight = _highPass * (_filteredRight + (sampleRight - _previousRight));
        _previousLeft = sampleLeft;
        _previousRight = sampleRight;
        _buffer[_count++] = Math.Clamp(_filteredLeft, -1, 1);
        _buffer[_count++] = Math.Clamp(_filteredRight, -1, 1);
        if (_count == _buffer.Length)
        {
            Flush();
        }
    }

    /// <summary>
    ///  Delivers the partial block without rounding up an incomplete sample or resetting phase.
    /// </summary>
    public void Flush()
    {
        int count = _count;
        _count = 0;
        if (count != 0)
        {
            _sink?.WriteSamples(_buffer.AsSpan(0, count));
        }
    }

    /// <summary>
    ///  Discards pending PCM and resets sample phase and filters, preserving the sink.
    /// </summary>
    public void Reset()
    {
        _clock.Reset();
        ClearSignal();
    }

    private void ClearSignal()
    {
        _count = 0;
        _leftIntegral = _rightIntegral = 0;
        _previousLeft = _previousRight = 0;
        _filteredLeft = _filteredRight = 0;
    }
}
