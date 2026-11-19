// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Chips;

namespace Retrocore.Tests;

/// <summary>
///  The SN76489's registers, tones, noise and attenuation.
/// </summary>
[TestClass]
public class Sn76489Tests
{
    /// <summary>
    ///  A latch byte and a data byte make a 10-bit period; the tone flips every period steps.
    /// </summary>
    [TestMethod]
    public void ToneFlipsEveryPeriod()
    {
        Sn76489 chip = new();
        chip.Write(0x85);       // Tone 1 frequency, low bits 5.
        chip.Write(0x01);       // High bits 1: period $15.
        chip.Write(0x90);       // Tone 1 at full volume.
        chip.Period(0).Should().Be(0x15);
        chip.Attenuation(0).Should().Be(0);

        int flips = 0;
        float last = chip.Output;
        for (int step = 0; step < 0x15 * 10; step++)
        {
            chip.Tick();
            if (chip.Output != last) { flips++; }
            last = chip.Output;
        }

        flips.Should().Be(10);
    }

    /// <summary>
    ///  Attenuation steps 2 dB; 15 is off.
    /// </summary>
    [TestMethod]
    public void AttenuationScalesTheOutput()
    {
        Sn76489 chip = new();
        chip.Write(0x80);
        chip.Write(0x01);
        chip.Write(0x90);
        while (chip.Output == 0) { chip.Tick(); }
        float full = chip.Output;
        chip.Write(0x93);
        chip.Output.Should().BeApproximately(full * MathF.Pow(10, -0.3f), 0.001f);
        chip.Write(0x9F);
        chip.Output.Should().Be(0);
    }

    /// <summary>
    ///  White noise is a 15-bit pseudo-random sequence; periodic noise a pulse every 15 shifts.
    /// </summary>
    [TestMethod]
    public void NoiseShifts()
    {
        Sn76489 chip = new();
        chip.Write(0xE4);       // White noise, the fastest rate.
        chip.Write(0xF0);
        int changes = 0;
        float last = chip.Output;
        for (int step = 0; step < 0x20 * 1000; step++)
        {
            chip.Tick();
            if (chip.Output != last) { changes++; }
            last = chip.Output;
        }

        changes.Should().BeInRange(300, 700, "white noise changes about every other shift");

        chip.Write(0xE0);       // Periodic noise.
        int highs = 0;
        for (int step = 0; step < 0x20 * 150; step++)
        {
            chip.Tick();
            if (chip.Output != 0 && last == 0) { highs++; }
            last = chip.Output;
        }

        highs.Should().Be(10, "one pulse every 15 shifts");
    }
}
