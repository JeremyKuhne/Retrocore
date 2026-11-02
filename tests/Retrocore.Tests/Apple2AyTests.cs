// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Apple2;

namespace Retrocore.Tests;

/// <summary>
///  Directed AY tone, mixer, noise, masked-register and all-shape envelope tests.
/// </summary>
[TestClass]
public class Apple2AyTests
{
    /// <summary>
    ///  Verifies register masks, bus deselection and non-destructive register reads.
    /// </summary>
    [TestMethod]
    public void RegisterMasksAndAddressSelectionFollowTheDataBus()
    {
        Ay38910 ay = new();
        byte[] masks = [255, 15, 255, 15, 255, 15, 31, 255, 31, 31, 31, 255, 255, 15, 255, 255];
        for (byte register = 0; register < 16; register++)
        {
            Set(ay, register, 255);
            ay.Read().Should().Be(masks[register]);
            ay.Read().Should().Be(masks[register]);
        }

        ay.LatchAddress(0x17);
        ay.Write(0);
        ay.Read().Should().Be(255);
        ay.LatchAddress(7);
        ay.Read().Should().Be(255);
        ay.Reset();
        ay.LatchAddress(7);
        ay.Read().Should().Be(0);
        ay.Output.Should().Be(0);
    }

    /// <summary>
    ///  Verifies port input/output direction and latch preservation in input mode.
    /// </summary>
    [TestMethod]
    public void ParallelPortsReadPinsOrOutputLatches()
    {
        Ay38910 ay = new() { PortAInput = 0x5A, PortBInput = 0xA5 };
        Set(ay, 14, 0x12);
        ay.Read().Should().Be(0x5A);
        Set(ay, 15, 0x34);
        ay.Read().Should().Be(0xA5);
        Set(ay, 7, 0xC0);
        ay.PortA.Should().Be(0x12);
        ay.PortB.Should().Be(0x34);
        ay.LatchAddress(14);
        ay.Read().Should().Be(0x12);
        ay.LatchAddress(15);
        ay.Read().Should().Be(0x34);
        Set(ay, 7, 0);
        ay.PortA.Should().Be(0x5A);
        ay.PortB.Should().Be(0xA5);
    }

    /// <summary>
    ///  Verifies all three tone channels toggle at eight clocks times the period, including zero.
    /// </summary>
    /// <param name="channel">The channel index.</param>
    /// <param name="period">The tone period.</param>
    [TestMethod]
    [DataRow(0, 0)]
    [DataRow(0, 1)]
    [DataRow(1, 3)]
    [DataRow(2, 4095)]
    public void TonePeriodAndMixerGatesAreCycleClocked(int channel, int period)
    {
        Ay38910 ay = new();
        Set(ay, (byte)(channel * 2), (byte)period);
        Set(ay, (byte)((channel * 2) + 1), (byte)(period >> 8));
        Set(ay, 7, (byte)(0x3F & ~(1 << channel)));
        Set(ay, (byte)(8 + channel), 15);
        int halfPeriod = Math.Max(1, period) * 8;
        ay.Output.Should().Be(0);
        Advance(ay, halfPeriod - 1);
        ay.Output.Should().Be(0);
        ay.Tick();
        ay.Output.Should().BeApproximately(1f / 3, 0.000001f);
        Advance(ay, halfPeriod);
        ay.Output.Should().Be(0);
        Set(ay, 7, 0x3F);
        ay.Output.Should().BeApproximately(1f / 3, 0.000001f);
        Set(ay, (byte)(8 + channel), 0);
        ay.Output.Should().Be(0);
    }

    /// <summary>
    ///  Verifies all DAC levels are increasing and all channels combine without overflow.
    /// </summary>
    [TestMethod]
    public void FixedVolumeLadderAndChannelSumAreNormalized()
    {
        Ay38910 ay = new();
        Set(ay, 7, 0x3F);
        float previous = 0;
        for (byte level = 1; level < 16; level++)
        {
            Set(ay, 8, level);
            ay.Output.Should().BeGreaterThan(previous);
            previous = ay.Output;
        }

        Set(ay, 9, 15);
        Set(ay, 10, 15);
        ay.Output.Should().Be(1);
    }

    /// <summary>
    ///  Verifies the 17-bit polynomial sequence and noise clock divider against a directed vector.
    /// </summary>
    /// <param name="period">The programmed noise period.</param>
    [TestMethod]
    [DataRow(0)]
    [DataRow(1)]
    [DataRow(7)]
    [DataRow(31)]
    public void NoiseUsesTheSeventeenBitPolynomialAndMixerGate(int period)
    {
        Ay38910 ay = new();
        Set(ay, 6, (byte)period);
        Set(ay, 7, 0x37);
        Set(ay, 8, 15);
        uint[] states =
        [
            0x10000, 0x08000, 0x04000, 0x02000, 0x01000, 0x00800, 0x00400,
            0x00200, 0x00100, 0x00080, 0x00040, 0x00020, 0x00010, 0x00008,
            0x10004, 0x08002, 0x04001, 0x12000
        ];

        int clocks = Math.Max(1, period) * 16;
        uint previous = 1;
        foreach (uint state in states)
        {
            Advance(ay, clocks - 1);
            ay.NoiseState.Should().Be(previous);
            ay.Tick();
            ay.NoiseState.Should().Be(state);
            ay.Output.Should().Be((state & 1) != 0 ? 1f / 3 : 0);
            previous = state;
        }

        Set(ay, 7, 0x3F);
        ay.Output.Should().BeApproximately(1f / 3, 0.000001f);
    }

    /// <summary>
    ///  Verifies full first/second ramps and held endpoints for every AY envelope shape.
    /// </summary>
    /// <param name="shape">The four-bit shape.</param>
    [TestMethod]
    [DataRow(0)]
    [DataRow(1)]
    [DataRow(2)]
    [DataRow(3)]
    [DataRow(4)]
    [DataRow(5)]
    [DataRow(6)]
    [DataRow(7)]
    [DataRow(8)]
    [DataRow(9)]
    [DataRow(10)]
    [DataRow(11)]
    [DataRow(12)]
    [DataRow(13)]
    [DataRow(14)]
    [DataRow(15)]
    public void EveryEnvelopeShapeHasItsDocumentedRampsAndEndpoints(int shape)
    {
        Ay38910 ay = new();
        Set(ay, 7, 0x3F);
        Set(ay, 8, 16);
        Set(ay, 11, 1);
        Set(ay, 13, (byte)shape);
        for (int step = 0; step < 64; step++)
        {
            int expected = ExpectedEnvelope(shape, step);
            ay.EnvelopeLevel.Should().Be(expected);
            if (expected == 0)
            {
                ay.Output.Should().Be(0);
            }
            else
            {
                ay.Output.Should().BeGreaterThan(0);
            }

            Advance(ay, 15);
            ay.EnvelopeLevel.Should().Be(expected);
            ay.Tick();
        }
    }

    /// <summary>
    ///  Verifies envelope high-byte periods, the half-period zero case, restart and fixed volume.
    /// </summary>
    [TestMethod]
    public void EnvelopePeriodZeroAndShapeWritesRestartTheGenerator()
    {
        Ay38910 ay = new();
        Set(ay, 13, 12);
        Advance(ay, 7);
        ay.EnvelopeLevel.Should().Be(0);
        ay.Tick();
        ay.EnvelopeLevel.Should().Be(1);
        Set(ay, 11, 2);
        Set(ay, 12, 1);
        Set(ay, 13, 12);
        Advance(ay, (258 * 16) - 1);
        ay.EnvelopeLevel.Should().Be(0);
        ay.Tick();
        ay.EnvelopeLevel.Should().Be(1);
        Set(ay, 13, 12);
        ay.EnvelopeLevel.Should().Be(0);
        Set(ay, 7, 0x3F);
        Set(ay, 8, 15);
        ay.Output.Should().BeApproximately(1f / 3, 0.000001f);
        Set(ay, 8, 16);
        ay.Output.Should().Be(0);
        Set(ay, 13, 9);
        ay.Output.Should().BeApproximately(1f / 3, 0.000001f);
        ay.Reset();
        ay.Output.Should().Be(0);
        ay.NoiseState.Should().Be(1);
    }

    private static int ExpectedEnvelope(int shape, int step)
    {
        if (step < 16)
        {
            return (shape & 4) == 0 ? 15 - step : step;
        }

        int ramp = step % 16;
        return shape switch
        {
            <= 7 or 9 or 15 => 0,
            8 => 15 - ramp,
            10 => (step / 16 & 1) != 0 ? ramp : 15 - ramp,
            11 or 13 => 15,
            12 => ramp,
            14 => (step / 16 & 1) != 0 ? 15 - ramp : ramp,
            _ => throw new ArgumentOutOfRangeException(nameof(shape))
        };
    }

    private static void Set(Ay38910 ay, byte register, byte value)
    {
        ay.LatchAddress(register);
        ay.Write(value);
    }

    private static void Advance(Ay38910 ay, int cycles)
    {
        for (int cycle = 0; cycle < cycles; cycle++)
        {
            ay.Tick();
        }
    }
}
