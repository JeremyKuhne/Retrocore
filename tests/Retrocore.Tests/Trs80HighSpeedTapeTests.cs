// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Trs80;

namespace Retrocore.Tests;

/// <summary>
///  The 1500 baud tape signal played from a tape image's bytes.
/// </summary>
[TestClass]
public class Trs80HighSpeedTapeTests
{
    /// <summary>
    ///  A tape holding two recordings plays each one's leader and sync byte without start bits, so the second leader's
    ///  bits alternate as the first's do; each byte after a sync byte has a 0 start bit.
    /// </summary>
    [TestMethod]
    public void PlaysEachRecordingsLeaderWithoutStartBits()
    {
        byte[] recording = [.. Enumerable.Repeat((byte)0x55, 256), 0x7F, 0xD3, 0x55, 0x55];
        List<bool> bits = Play([.. recording, .. recording]);

        List<bool> expected = [];
        for (int copy = 0; copy < 2; copy++)
        {
            foreach (byte value in recording.Take(257)) { expected.AddRange(Bits(value)); }
            foreach (byte value in recording.Skip(257)) { expected.Add(item: false); expected.AddRange(Bits(value)); }
        }

        bits.Should().Equal(expected);
    }

    /// <summary>
    ///  A few leader bytes and a $7F inside a recording's file are the file's bytes, with start bits, not another
    ///  recording.
    /// </summary>
    [TestMethod]
    public void TakesAShortRunInAFileAsTheFilesBytes()
    {
        byte[] tape = [0x55, 0x55, 0x7F, 0x55, 0x55, 0x7F];
        List<bool> bits = Play(tape);
        List<bool> expected = [.. Bits(0x55), .. Bits(0x55), .. Bits(0x7F)];
        foreach (byte value in tape.Skip(3)) { expected.Add(item: false); expected.AddRange(Bits(value)); }
        bits.Should().Equal(expected);
    }

    // Plays a tape to its end and returns each cycle's bit, by the length of its high half, less the closing cycle.
    private static List<bool> Play(byte[] bytes)
    {
        Trs80HighSpeedTape tape = new();
        tape.Play(bytes);
        List<bool> bits = [];
        int high = 0;
        for (long tick = 0; !tape.AtEnd && tick < 100_000_000; tick++)
        {
            bool was = tape.Level;
            tape.Tick();
            if (tape.Level) { high++; }
            else if (was)
            {
                bits.Add(high < (Trs80HighSpeedTape.OneHalf + Trs80HighSpeedTape.ZeroHalf) / 2);
                high = 0;
            }
        }

        tape.AtEnd.Should().BeTrue();
        bits.Should().NotBeEmpty();
        bits.RemoveAt(bits.Count - 1);
        return bits;
    }

    private static IEnumerable<bool> Bits(byte value) => Enumerable.Range(0, 8).Select(bit => ((value >> (7 - bit)) & 1) != 0);
}
