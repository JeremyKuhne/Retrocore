// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Security.Cryptography;
using Retrocore.Machines.Altair;

namespace Retrocore.Tests;

/// <summary>
///  Altair BASIC on the Altair 8800: 4K BASIC 3.2 and 4.0, 8K BASIC 4.0 and Extended BASIC 4.0, from memory images,
///  on the 88-2SIO and the 88-SIO; 8K BASIC's CSAVE and CLOAD through the 88-ACR; and MITS's own tapes, loaded through
///  the 88-ACR with the bootstrap keyed in at the front panel.
/// </summary>
/// <remarks>
///  <para>
///   Altair BASIC is MITS's and Microsoft's, so the images are not in the repository: the tests read
///   <c>4kbas32.bin</c>, <c>4kbas40.bin</c>, <c>8kbas.bin</c> and <c>exbas.bin</c>, the images in SIMH's
///   <c>altsw.zip</c>, from <c>RETROCORE_ALTAIR_BASIC</c> or the <c>altair-basic</c> folder of the external test
///   data, and MITS's tapes, from altairclone.com's "MITS Tapes" CP/M disk, from its <c>tapes</c> folder; each test
///   is inconclusive without its file. Digests pin the images and tapes. What each prints, its bytes free at 32 KB
///   and 8K BASIC's tape match SIMH's <c>altairz80</c> (open-simh <c>87eb7d5</c>) with the same RAM.
///  </para>
/// </remarks>
[TestClass]
public sealed class AltairBasicTests
{
    private const string Basic32 = "4kbas32.bin";
    private const string Basic40 = "4kbas40.bin";
    private const string Basic8K = "8kbas.bin";
    private const string BasicExtended = "exbas.bin";

    // What 8K BASIC's CSAVE "P" records for its program: three $D3s and the name, then the program as it is in memory.
    private const string Tape =
        "D3D3D35047190A0096202248454C4C4F22005D191400812049AC31209E20333A962049A6493A82000000";

    private static readonly Dictionary<string, string> s_digests = new()
    {
        ["tapes/4KBAS32.TAP"] = "0C9850FE5F4FD36CDA7DAEEC4123D987AE5252EEEC69D14EF661E79A58CD9DC3",
        ["tapes/4KBAS40.TAP"] = "20D104EBC703054A8F7A6E766639E14AB85560FD78D82F2915B2C493EAC11A0E",
        ["tapes/8KBAS40.TAP"] = "E610937291D20860FF12068E5BB41EDECDD7473097E1344CF504046E120CBB6A",
        ["tapes/8KBAS32.TAP"] = "677FBB00C53C843A98F4272F26AB93E3E236805F2F3A1B3645F0C7EF68C668F4",
        ["tapes/EXTBAS41.TAP"] = "05539C6BD3E662473764BD6FC072B30988E032FA0A7F0F4D84DC0D29440A3E37",
        [Basic32] = "6946B7718068DAA0C70219071824C78937C0C79554B5579B7F118B826D8968ED",
        [Basic40] = "3AAA9907F8A2C32452B9B4580C9B4CCED2146D7877129CDCD0B9A50C798FB616",
        [Basic8K] = "DFE4B1576C6AC9FE1A47E9BA0FE697F098209EF8EAB61CD54CFFC626A84152D3",
        [BasicExtended] = "5A01407CA65C1B0CD49BF2E4D88DA292315DADDE8D3FE89CA8794645916EEEE0"
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
    ///  Extended BASIC 4.0 on the 88-2SIO: integer variables, statements on a line, and powers.
    /// </summary>
    [TestMethod]
    public void BasicExtendedRuns()
    {
        AltairBasicSession basic = new(BasicExtended, AltairConsole.Serial2Sio, switches: 0);
        basic.Start("", "Y");
        basic.Output.Should().Contain("18094 BYTES FREE")
            .And.Contain("[EXTENDED VERSION]")
            .And.Contain("COPYRIGHT 1977 BY MITS INC.");

        basic.Type("10 DEFINT I:FOR I=1 TO 3:PRINT I*I;:NEXT");
        basic.Clear();
        basic.Type("RUN");
        basic.Type("PRINT 2^10");
        basic.Output.Should().Be("RUN\n 1  4  9 \nOK\nPRINT 2^10\n 1024 \nOK\n");
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

    /// <summary>
    ///  MITS's own tapes load through the 88-ACR with MITS's bootstrap keyed in at the front panel, and BASIC comes up
    ///  as from its image: the 3.2 loaders take the 88-ACR with A15 up, and the 4.x loaders take device 3, the 88-ACR,
    ///  in A11-A8. 8K BASIC 3.2 and Extended BASIC 4.1, which SIMH's images lack, come only from tapes; 4.1 asks
    ///  whether there is a line printer, and C answers that there is none but the console.
    /// </summary>
    /// <param name="tape">The tape in the external test data's <c>altair-basic/tapes</c> folder.</param>
    /// <param name="loadAddress">The bootstrap's load address.</param>
    /// <param name="console">The board the terminal is on.</param>
    /// <param name="switches">The sense switches, for the loader and BASIC.</param>
    /// <param name="answers">The answers to BASIC's questions, separated by bars.</param>
    /// <param name="banner">What BASIC prints when it is ready.</param>
    [TestMethod]
    [DataRow("4KBAS32.TAP", 0x0FAE, AltairConsole.Sio, 0x8000, "||Y", "29399 BYTES FREE")]
    [DataRow("4KBAS40.TAP", 0x0FC2, AltairConsole.Serial2Sio, 0x0300, "||Y", "29388 BYTES FREE")]
    [DataRow("8KBAS40.TAP", 0x1FC2, AltairConsole.Serial2Sio, 0x0300, "||Y", "26244 BYTES FREE")]
    [DataRow("8KBAS32.TAP", 0x1FAE, AltairConsole.Sio, 0x8000, "||Y", "26696 BYTES FREE")]
    [DataRow("EXTBAS41.TAP", 0x3FC2, AltairConsole.Serial2Sio, 0x0300, "|C|Y", "ALTAIR BASIC REV. 4.1")]
    public void BasicLoadsFromMitsTape(
        string tape,
        int loadAddress,
        AltairConsole console,
        int switches,
        string answers,
        string banner)
    {
        byte[] bytes = Image($"tapes/{tape}");
        AltairBasicSession basic = AltairBasicSession.FromTape(bytes, (ushort)loadAddress, console, (ushort)switches);
        basic.Output.Should().Contain("MEMORY SIZE?");
        basic.Start(answers.Split('|'));
        basic.Output.Should().Contain(banner);
        Squares(basic);
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
