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
    ///  A TAP image cut short, before the bytes its header promises or inside a pulse's three-byte length, is refused
    ///  rather than read as a shorter tape that would save without them.
    /// </summary>
    [TestMethod]
    public void ACutShortTapIsRefused()
    {
        byte[] image = TapFormat.Write([352, 3000, 512]);
        Action shorter = () => TapFormat.Read(image.AsSpan(0, image.Length - 1));
        shorter.Should().Throw<InvalidDataException>().WithMessage("*holds 6 bytes of pulses, but only 5*");

        // The long pulse's zero and its length's first byte, with the header saying only those two bytes follow.
        byte[] inside = image[..22];
        inside[16] = 2;
        Action cut = () => TapFormat.Read(inside);
        cut.Should().Throw<InvalidDataException>().WithMessage("*inside a pulse's three-byte length*");
    }

    /// <summary>
    ///  A WAV file whose samples are cut short is refused rather than read as a shorter tape.
    /// </summary>
    [TestMethod]
    public void ACutShortWaveIsRefused()
    {
        byte[] wave = CommodoreWave.Write([1000, 2000, 3000], rate: 1_000_000);
        Action read = () => CommodoreWave.Read(wave.AsSpan(0, wave.Length - 100));
        read.Should().Throw<InvalidDataException>().WithMessage("*data chunk says*");

        // Cut before its data chunk, it has no samples at all, and is no empty tape.
        Action headerOnly = () => CommodoreWave.Read(wave.AsSpan(0, 36));
        headerOnly.Should().Throw<InvalidDataException>().WithMessage("*no data chunk*");
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
