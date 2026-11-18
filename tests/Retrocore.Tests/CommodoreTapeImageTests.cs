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
    ///  A .prg becomes the tape SAVE writes: a header block and the program, each twice, after their leaders, each byte
    ///  a long and a medium pulse, eight bits from the lowest and odd parity, each copy ending in its checksum.
    /// </summary>
    [TestMethod]
    public void APrgBecomesTheTapeSaveWrites()
    {
        byte[] program = [0x0B, 0x04, 0x0A, 0x00, 0x99, 0x22, 0x48, 0x49, 0x22, 0x00, 0x00, 0x00];
        CommodoreTape tape = CommodoreTapeBuilder.FromPrg("hello", [0x01, 0x04, .. program]);
        IReadOnlyList<int> pulses = tape.Pulses;
        int at = 0;

        // The header: its leader, then its two copies.
        Leader(0x6A00);
        byte[] header = Copy(0x80, 192);
        End();
        Leader(79);
        Copy(0x00, 192).Should().Equal(header);
        Leader(80);
        header[..5].Should().Equal((byte)1, (byte)0x01, (byte)0x04, (byte)0x0D, (byte)0x04);
        System.Text.Encoding.ASCII.GetString(header, 5, 16).Should().Be("HELLO           ");

        // The program the same way, after its shorter leader.
        Leader(0x1500);
        Copy(0x80, program.Length).Should().Equal(program);
        End();
        Leader(79);
        Copy(0x00, program.Length).Should().Equal(program);
        Leader(80);
        at.Should().Be(pulses.Count, "nothing follows the second copy");

        Action noAddress = () => CommodoreTapeBuilder.FromPrg("x", [0x01, 0x04]);
        noAddress.Should().Throw<ArgumentException>();
        Action longName = () => CommodoreTapeBuilder.FromProgram("SEVENTEEN LETTERS", 0x0401, [0]);
        longName.Should().Throw<ArgumentException>();
        Action pastTheTop = () => CommodoreTapeBuilder.FromProgram("x", 0xFFFF, [0, 0]);
        pastTheTop.Should().Throw<ArgumentException>();

        void Leader(int count)
        {
            for (int i = 0; i < count; i++) { pulses[at++].Should().Be(CommodoreTapeBuilder.Short); }
        }

        void End()
        {
            pulses[at++].Should().Be(CommodoreTapeBuilder.Long);
            pulses[at++].Should().Be(CommodoreTapeBuilder.Short);
        }

        // A copy: its sync bytes from $x9 down to $x1, its data, and the data's XOR.
        byte[] Copy(byte sync, int length)
        {
            for (int count = 9; count >= 1; count--) { Byte().Should().Be((byte)(sync | count)); }
            byte[] data = new byte[length];
            byte checksum = 0;
            for (int i = 0; i < length; i++)
            {
                data[i] = Byte();
                checksum ^= data[i];
            }

            Byte().Should().Be(checksum);
            return data;
        }

        byte Byte()
        {
            pulses[at++].Should().Be(CommodoreTapeBuilder.Long);
            pulses[at++].Should().Be(CommodoreTapeBuilder.Medium);
            int value = 0;
            bool parity = true;
            for (int bit = 0; bit < 8; bit++)
            {
                bool one = Bit();
                parity ^= one;
                if (one) { value |= 1 << bit; }
            }

            Bit().Should().Be(parity, "odd parity");
            return (byte)value;
        }

        // A short and a medium for 0, a medium and a short for 1.
        bool Bit()
        {
            int first = pulses[at++];
            int second = pulses[at++];
            (first, second).Should().BeOneOf(
                (CommodoreTapeBuilder.Short, CommodoreTapeBuilder.Medium),
                (CommodoreTapeBuilder.Medium, CommodoreTapeBuilder.Short));

            return first == CommodoreTapeBuilder.Medium;
        }
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
