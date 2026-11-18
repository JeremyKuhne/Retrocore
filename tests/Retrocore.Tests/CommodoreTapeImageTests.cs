// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Media;
using Retrocore.Media.Commodore;

namespace Retrocore.Tests;

/// <summary>
///  Commodore tape images: a tape's snapshot keeps every pulse, and TAP and WAV images keep what they can and list the
///  rest.
/// </summary>
[TestClass]
public class CommodoreTapeImageTests
{
    /// <summary>
    ///  Every pulse survives a WAV file, the first and the last too: at a sample a microsecond nothing rounds.
    /// </summary>
    /// <param name="pulses">The pulses, in microseconds.</param>
    [TestMethod]
    [DataRow(new[] { 1000, 2000, 3000 })]
    [DataRow(new[] { 1500 })]
    public void EveryPulseSurvivesAWave(int[] pulses) =>
        CommodoreWave.Read(CommodoreWave.Write(pulses, rate: 1_000_000)).Pulses.Should().Equal(pulses);

    /// <summary>
    ///  A pause longer than a TAP image holds stays whole in the tape's snapshot and its WAV file, and a TAP save lists
    ///  it as a loss rather than shortening it unsaid.
    /// </summary>
    [TestMethod]
    public void APauseTooLongForTapIsALoss()
    {
        CommodoreTape tape = new([352, 20_000_000, 352]);
        MediumSnapshot snapshot = tape.Snapshot();
        CommodoreTape.FromSnapshot(snapshot.Image.Span).Pulses.Should().Equal(tape.Pulses);

        EncodedImage tap = new CommodoreTapeCodec("TAP").Encode(snapshot);
        tap.Losses.Should().Equal("1 pause longer than 16.777215 s, the longest a TAP image holds, shortened to that.");
        TapFormat.Read(tap.Bytes).Pulses.Should().Equal(352, TapFormat.LongestPulse, 352);

        CommodoreWave.Read(new CommodoreTapeCodec("WAV").Encode(snapshot).Bytes).Pulses[1].Should().BeCloseTo(20_000_000, 23);
    }

    /// <summary>
    ///  A tape whose pulses TAP holds saves as TAP with no loss and reads back the same.
    /// </summary>
    [TestMethod]
    public void TapHoldsOrdinaryPulses()
    {
        CommodoreTape tape = new([352, 512, 672, 3000, 1_000_000]);
        EncodedImage tap = new CommodoreTapeCodec("TAP").Encode(tape.Snapshot());
        tap.Losses.Should().BeEmpty();
        CommodoreTapeCodec.Load(tap.Bytes).Tape.Pulses.Should().Equal(tape.Pulses);
    }
}
