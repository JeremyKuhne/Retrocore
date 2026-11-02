// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Apple2;

/// <summary>
///  Cycle-clocked AY-3-8910 digital tone, noise, envelope and parallel ports.
/// </summary>
/// <remarks>
///  Original implementation following the General Instrument February 1979 data manual.
///  Tone half-periods are 8 clocks; noise shifts every 16 clocks; a 16-step envelope ramp
///  takes 256 times its period. Zero tone/noise periods mean one; zero envelope means half
///  the period-one ramp. The DAC uses an ideal 3 dB ladder, not a measured analog model.
///  The MIT license of true-grue/ayumi was verified; no implementation is copied here.
///  <see href="https://archive.org/details/AY-3-8910-8912_Feb-1979">GI data manual</see>.
/// </remarks>
internal sealed class Ay38910
{
    private static readonly byte[] s_masks = [255, 15, 255, 15, 255, 15, 31, 255, 31, 31, 31, 255, 255, 15, 255, 255];
    private static readonly float[] s_levels = CreateLevels();
    private readonly byte[] _registers = new byte[16];
    private readonly int[] _toneCounters = new int[3];
    private readonly bool[] _tones = new bool[3];
    private int _divider;
    private int _noiseCounter;
    private uint _noise;
    private int _envelopeCounter;
    private int _envelopeStep;
    private bool _envelopeRising;
    private bool _envelopeHolding;
    private int _address;

    /// <summary>
    ///  Creates a reset PSG.
    /// </summary>
    internal Ay38910() => Reset();

    /// <summary>
    ///  Gets the mono sum of three channels, normalized from zero to one.
    /// </summary>
    internal float Output
    {
        get
        {
            float output = 0;
            int mixer = _registers[7];
            for (int channel = 0; channel < 3; channel++)
            {
                bool tone = _tones[channel] || (mixer & (1 << channel)) != 0;
                bool noise = (_noise & 1) != 0 || (mixer & (8 << channel)) != 0;
                int volume = _registers[8 + channel];
                int level = (volume & 16) == 0 ? volume & 15 : _envelopeStep;
                if (tone && noise)
                {
                    output += s_levels[level];
                }
            }

            return output / 3;
        }
    }

    /// <summary>
    ///  Gets the current 16-level envelope amplitude.
    /// </summary>
    internal int EnvelopeLevel => _envelopeStep;

    /// <summary>
    ///  Gets the 17-bit noise state for digital conformance checks.
    /// </summary>
    internal uint NoiseState => _noise;

    /// <summary>
    ///  Gets or sets the external port A pins.
    /// </summary>
    internal byte PortAInput { get; set; } = 255;

    /// <summary>
    ///  Gets or sets the external port B pins.
    /// </summary>
    internal byte PortBInput { get; set; } = 255;

    /// <summary>
    ///  Gets port A pins, with mixer bit 6 selecting output when set.
    /// </summary>
    internal byte PortA => (_registers[7] & 64) != 0 ? _registers[14] : PortAInput;

    /// <summary>
    ///  Gets port B pins, with mixer bit 7 selecting output when set.
    /// </summary>
    internal byte PortB => (_registers[7] & 128) != 0 ? _registers[15] : PortBInput;

    /// <summary>
    ///  Latches an address; a nonzero high nibble deselects the PSG.
    /// </summary>
    /// <param name="address">The bus address byte.</param>
    internal void LatchAddress(byte address) => _address = address < 16 ? address : -1;

    /// <summary>
    ///  Reads the selected register or pulled-up bus when deselected, without side effects.
    /// </summary>
    /// <returns>The selected data or 255 when deselected.</returns>
    internal byte Read() => _address switch
    {
        < 0 => 255,
        14 => PortA,
        15 => PortB,
        _ => _registers[_address]
    };

    /// <summary>
    ///  Writes the selected register, masking unused bits. Shape writes always restart the ramp.
    /// </summary>
    /// <param name="value">The bus data byte.</param>
    internal void Write(byte value)
    {
        if (_address < 0)
        {
            return;
        }

        _registers[_address] = (byte)(value & s_masks[_address]);
        if (_address == 13)
        {
            _envelopeCounter = 0;
            _envelopeRising = (value & 4) != 0;
            _envelopeStep = _envelopeRising ? 0 : 15;
            _envelopeHolding = false;
        }
    }

    /// <summary>
    ///  Advances one PSG input clock.
    /// </summary>
    internal void Tick()
    {
        if (++_divider != 8)
        {
            return;
        }

        _divider = 0;
        for (int channel = 0; channel < 3; channel++)
        {
            int period = _registers[channel * 2] | (_registers[(channel * 2) + 1] << 8);
            if (++_toneCounters[channel] >= Math.Max(1, period))
            {
                _toneCounters[channel] = 0;
                _tones[channel] = !_tones[channel];
            }
        }

        if (++_noiseCounter >= Math.Max(1, (int)_registers[6]) * 2)
        {
            _noiseCounter = 0;
            uint feedback = (_noise ^ (_noise >> 3)) & 1;
            _noise = (_noise >> 1) | (feedback << 16);
        }

        int envelopePeriod = _registers[11] | (_registers[12] << 8);
        if (++_envelopeCounter >= Math.Max(1, envelopePeriod * 2))
        {
            _envelopeCounter = 0;
            StepEnvelope();
        }
    }

    /// <summary>
    ///  Resets registers, counters and output. External port levels remain caller-owned.
    /// </summary>
    internal void Reset()
    {
        Array.Clear(_registers);
        Array.Clear(_toneCounters);
        Array.Clear(_tones);
        _divider = _noiseCounter = _envelopeCounter = 0;
        _noise = 1;
        _address = 0;
        _envelopeStep = 15;
        _envelopeRising = _envelopeHolding = false;
    }

    private void StepEnvelope()
    {
        if (_envelopeHolding)
        {
            return;
        }

        int next = _envelopeStep + (_envelopeRising ? 1 : -1);
        if (next is >= 0 and <= 15)
        {
            _envelopeStep = next;
            return;
        }

        int shape = _registers[13];
        if ((shape & 8) == 0)
        {
            _envelopeStep = 0;
            _envelopeHolding = true;
            return;
        }

        if ((shape & 2) != 0)
        {
            _envelopeRising = !_envelopeRising;
        }

        if ((shape & 1) != 0)
        {
            _envelopeHolding = true;
            _envelopeStep = _envelopeRising ? 15 : 0;
        }
        else
        {
            _envelopeStep = _envelopeRising ? 0 : 15;
        }
    }

    private static float[] CreateLevels()
    {
        float[] levels = new float[16];
        for (int i = 1; i < levels.Length; i++)
        {
            levels[i] = MathF.Pow(10, (i - 15) * 0.15f);
        }

        return levels;
    }
}
