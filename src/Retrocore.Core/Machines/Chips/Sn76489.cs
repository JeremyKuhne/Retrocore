// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Chips;

/// <summary>
///  A Texas Instruments SN76489 sound generator: three square-wave tone channels and a noise channel, each with a
///  4-bit attenuator, mixed to one output.
/// </summary>
/// <remarks>
///  <para>
///   A byte with bit 7 set latches a register (bits 4-6: tone 1 frequency, tone 1 attenuation, tone 2 frequency, tone
///   2 attenuation, tone 3 frequency, tone 3 attenuation, noise control, noise attenuation) and writes its low four
///   bits. A byte with bit 7 clear writes the latched register again: a tone's frequency gets bits 4-9 of its 10-bit
///   period, any other register its low four bits.
///  </para>
///  <para>
///   The chip divides its clock by 16; <see cref="Tick"/> is one step of that divided clock. A tone's counter counts
///   its period down and flips the channel's output when it runs out, so the tone is the divided clock over twice the
///   period; a period of 0 counts as 1,024. The noise control's bits 0-1 shift the noise generator every 16, 32 or 64
///   steps, or each time tone 3 flips; bit 2 chooses white noise (a 15-bit shift register fed back from its two low
///   bits) or periodic noise (one bit circulating). Writing the noise control restarts the shift register.
///  </para>
///  <para>
///   An attenuation of 0 is full volume and each step below it 2 dB less, to 15, which is off.
///  </para>
/// </remarks>
public sealed class Sn76489
{
    private static readonly float[] s_volumes = MakeVolumes();

    private readonly ushort[] _periods = new ushort[3];
    private readonly int[] _counters = new int[4];
    private readonly byte[] _attenuations = [15, 15, 15, 15];
    private readonly bool[] _outputs = new bool[4];
    private int _latched;
    private byte _noise;
    private ushort _shifter = 0x4000;
    private bool _noiseClock;
    private bool _toneClock;

    /// <summary>
    ///  Creates a chip as power-on leaves it, here with every channel off.
    /// </summary>
    public Sn76489()
    {
    }

    /// <summary>
    ///  Gets the mixed output, from 0 (silence) to 1 (every channel high at full volume).
    /// </summary>
    public float Output
    {
        get
        {
            float sum = 0;
            for (int channel = 0; channel < 4; channel++)
            {
                if (_outputs[channel]) { sum += s_volumes[_attenuations[channel]]; }
            }

            return sum / 4;
        }
    }

    /// <summary>
    ///  Gets a tone channel's 10-bit period.
    /// </summary>
    /// <param name="channel">The tone channel, 0-2.</param>
    /// <returns>The period.</returns>
    public ushort Period(int channel) => _periods[channel];

    /// <summary>
    ///  Gets a channel's attenuation: 0 loudest, 15 off.
    /// </summary>
    /// <param name="channel">0-2 the tones, 3 the noise.</param>
    /// <returns>The attenuation.</returns>
    public byte Attenuation(int channel) => _attenuations[channel];

    /// <summary>
    ///  Gets the noise control: bits 0-1 the shift rate, bit 2 white noise.
    /// </summary>
    public byte NoiseControl => _noise;

    /// <summary>
    ///  Sets every channel's attenuation, as the chip's power-on state leaves it; power-on leaves the real chip's
    ///  registers as they happen to come up, often loud.
    /// </summary>
    /// <param name="attenuation">The attenuation, 0-15.</param>
    public void SetAllAttenuations(byte attenuation) => _attenuations.AsSpan().Fill((byte)(attenuation & 15));

    /// <summary>
    ///  Writes a byte, as the chip latches its data bus while WE is low.
    /// </summary>
    /// <param name="value">The byte.</param>
    public void Write(byte value)
    {
        if ((value & 0x80) != 0)
        {
            _latched = (value >> 4) & 7;
            WriteRegister(value & 0x0F, high: false);
        }
        else
        {
            WriteRegister(value & 0x3F, high: true);
        }
    }

    /// <summary>
    ///  Advances one step of the clock divided by 16.
    /// </summary>
    public void Tick()
    {
        for (int channel = 0; channel < 3; channel++)
        {
            if (--_counters[channel] <= 0)
            {
                _counters[channel] = _periods[channel] == 0 ? 0x400 : _periods[channel];
                _outputs[channel] = !_outputs[channel];
                if (channel == 2 && (_noise & 3) == 3 && (_toneClock = !_toneClock)) { Shift(); }
            }
        }

        if ((_noise & 3) != 3 && --_counters[3] <= 0)
        {
            _counters[3] = 0x10 << (_noise & 3);
            if (_noiseClock = !_noiseClock) { Shift(); }
        }
    }

    private static float[] MakeVolumes()
    {
        float[] volumes = new float[16];
        for (int step = 0; step < 15; step++) { volumes[step] = MathF.Pow(10, -0.1f * step); }
        return volumes;
    }

    private void WriteRegister(int data, bool high)
    {
        int channel = _latched >> 1;
        if ((_latched & 1) != 0)
        {
            _attenuations[channel] = (byte)(data & 15);
            return;
        }

        if (channel < 3)
        {
            _periods[channel] = high
                ? (ushort)((_periods[channel] & 0x0F) | ((data & 0x3F) << 4))
                : (ushort)((_periods[channel] & 0x3F0) | (data & 0x0F));

            return;
        }

        _noise = (byte)(data & 7);
        _shifter = 0x4000;
        _outputs[3] = false;
    }

    // The noise generator's output follows the shift register's low bit.
    private void Shift()
    {
        int feedback = (_noise & 4) != 0 ? (_shifter ^ (_shifter >> 1)) & 1 : _shifter & 1;
        _shifter = (ushort)((_shifter >> 1) | (feedback << 14));
        _outputs[3] = (_shifter & 1) != 0;
    }
}
