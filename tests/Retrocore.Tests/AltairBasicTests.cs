// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Security.Cryptography;
using Retrocore.Machines.Altair;

namespace Retrocore.Tests;

/// <summary>
///  Altair BASIC on the Altair 8800: 4K BASIC 3.2 and 4.0 and 8K BASIC 4.0, from memory images, on the 88-2SIO and
///  the 88-SIO, and 8K BASIC's CSAVE and CLOAD through the 88-ACR.
/// </summary>
/// <remarks>
///  <para>
///   Altair BASIC is MITS's and Microsoft's, so the images are not in the repository: the tests read
///   <c>4kbas32.bin</c>, <c>4kbas40.bin</c> and <c>8kbas.bin</c>, the images SIMH's <c>altsw.zip</c> has, from
///   <c>RETROCORE_ALTAIR_BASIC</c> or the <c>altair-basic</c> folder of the external test data, and are inconclusive
///   without them. Digests pin the images. What each prints, its bytes free at 32 KB and 8K BASIC's tape match SIMH's
///   <c>altairz80</c> (open-simh <c>87eb7d5</c>) with the same RAM.
///  </para>
/// </remarks>
[TestClass]
public sealed class AltairBasicTests
{
    private const string Basic32 = "4kbas32.bin";
    private const string Basic40 = "4kbas40.bin";
    private const string Basic8K = "8kbas.bin";

    // What 8K BASIC's CSAVE "P" records for its program: three $D3s and the name, then the program as it is in memory.
    private const string Tape =
        "D3D3D35047190A0096202248454C4C4F22005D191400812049AC31209E20333A962049A6493A82000000";

    private static readonly Dictionary<string, string> s_digests = new()
    {
        [Basic32] = "15DDC7023137106EE7421DF60F182726FEC395F6BCA573040AF39019AC83B508",
        [Basic40] = "3AAA9907F8A2C32452B9B4580C9B4CCED2146D7877129CDCD0B9A50C798FB616",
        [Basic8K] = "DFE4B1576C6AC9FE1A47E9BA0FE697F098209EF8EAB61CD54CFFC626A84152D3"
    };

    /// <summary>
    ///  4K BASIC 3.2 on the 88-2SIO, which sense switch A11 picks.
    /// </summary>
    [TestMethod]
    public void Basic32RunsOnThe2Sio()
    {
        AltairBasicSession basic = new(Basic32, AltairConsole.Serial2Sio, switches: 0x0800);
        basic.Start("", "", "Y");
        basic.Output.Should().Contain("29399 BYTES FREE").And.Contain("BASIC VERSION 3.2").And.Contain("[4K VERSION]");
        Squares(basic);
    }

    /// <summary>
    ///  4K BASIC 3.2 on the 88-SIO, which it uses with the sense switches down.
    /// </summary>
    [TestMethod]
    public void Basic32RunsOnTheSio()
    {
        AltairBasicSession basic = new(Basic32, AltairConsole.Sio, switches: 0);
        basic.Start("", "", "Y");
        basic.Output.Should().Contain("BASIC VERSION 3.2");
        Squares(basic);
    }

    /// <summary>
    ///  4K BASIC 4.0 on the 88-2SIO with the switches down, and on the 88-SIO with A13 up, device 2 in A15-A12.
    /// </summary>
    [TestMethod]
    public void Basic40PicksItsTerminalBySwitches()
    {
        AltairBasicSession basic = new(Basic40, AltairConsole.Serial2Sio, switches: 0);
        basic.Start("", "", "Y");
        basic.Output.Should().Contain("29388 BYTES FREE").And.Contain("4K BASIC 4.0").And.Contain("COPYRIGHT MITS 1976");
        Squares(basic);

        AltairBasicSession sio = new(Basic40, AltairConsole.Sio, switches: 0x2000);
        sio.Start("", "", "Y");
        sio.Output.Should().Contain("4K BASIC 4.0");
        Squares(sio);
    }

    /// <summary>
    ///  8K BASIC 4.0 on the 88-2SIO: its banner after an A for the memory size, and a program.
    /// </summary>
    [TestMethod]
    public void Basic8KRuns()
    {
        AltairBasicSession basic = new(Basic8K, AltairConsole.Serial2Sio, switches: 0);
        basic.Start("A", "", "", "Y");
        basic.Output.Should().Contain("WRITTEN FOR ROYALTIES BY MICRO-SOFT")
            .And.Contain("26244 BYTES FREE")
            .And.Contain("[EIGHT-K VERSION]")
            .And.Contain("COPYRIGHT 1976 BY MITS INC.");

        Squares(basic);
    }

    /// <summary>
    ///  8K BASIC's CSAVE records the program through the 88-ACR, the same bytes SIMH punches, and CLOAD reads it
    ///  back into a cleared program.
    /// </summary>
    [TestMethod]
    public void Basic8KSavesAndLoadsTape()
    {
        AltairBasicSession basic = new(Basic8K, AltairConsole.Serial2Sio, switches: 0);
        basic.Start("A", "", "", "Y");
        basic.Type("10 PRINT \"HELLO\"");
        basic.Type("20 FOR I=1 TO 3:PRINT I*I:NEXT");
        AltairCassette cassette = basic.Machine.Bus.Cassette ?? throw new InvalidOperationException("The 88-ACR is missing.");
        cassette.Record("program.tap");
        basic.Type("CSAVE \"P\"", seconds: 3);
        byte[] tape = cassette.Eject() ?? throw new InvalidOperationException("The tape is missing.");
        Convert.ToHexString(tape).Should().Be(Tape);

        basic.Type("NEW");
        basic.Type("CLOAD \"P\"", seconds: 0.1);
        cassette.Play(tape, "program.tap");
        basic.Machine.Run((ulong)(3 * AltairTiming.ClockHertz));
        cassette.AtEnd.Should().BeTrue();
        basic.Clear();
        basic.Type("RUN");
        basic.Output.Should().Be("RUN\nHELLO\n 1 \n 4 \n 9 \nOK\n");
    }

    // Types a program that prints squares, and runs it.
    private static void Squares(AltairBasicSession basic)
    {
        basic.Type("10 FOR I=1 TO 3");
        basic.Type("20 PRINT I*I");
        basic.Type("30 NEXT I");
        basic.Clear();
        basic.Type("RUN");
        basic.Output.Replace("\n\n", "\n").Should().Be("RUN\n 1 \n 4 \n 9 \nOK\n");
    }

    /// <summary>
    ///  Reads a BASIC image from the external test data, checking its digest.
    /// </summary>
    /// <param name="name">The image's file name.</param>
    /// <returns>The image.</returns>
    internal static byte[] Image(string name)
    {
        string directory = Environment.GetEnvironmentVariable("RETROCORE_ALTAIR_BASIC") is { Length: > 0 } configured
            ? configured
            : Path.Join(ExternalTestData.Root, "altair-basic");

        string path = Path.Join(directory, name);
        if (!File.Exists(path)) { Assert.Inconclusive($"Altair BASIC's image ({path}) is missing."); }
        byte[] image = File.ReadAllBytes(path);
        Convert.ToHexString(SHA256.HashData(image)).Should().Be(s_digests[name], "{0} should be the image SIMH runs", name);
        return image;
    }
}
