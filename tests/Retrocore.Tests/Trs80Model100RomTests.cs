// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Trs80Model100;
using System.Security.Cryptography;

namespace Retrocore.Tests;

/// <summary>
///  The Model 100's and Tandy 102's own ROMs: booting to the menu, BASIC, the clock, the LCD and power.
/// </summary>
/// <remarks>
///  <para>
///   The ROMs are Microsoft's and Tandy's, so they are not in the repository: the tests read <c>m100.bin</c> and
///   <c>t102.bin</c>, the US Model 100's and Tandy 102's ROMs (MAME's <c>m100rom.m12</c> and <c>m102rom.m12</c>),
///   from <c>RETROCORE_TRS80M100_ROMS</c> or the <c>trs80m100-roms</c> folder of the external test data, and are
///   inconclusive without them. What the tests expect was checked against MAME 0.264's <c>trsm100</c> and
///   <c>tandy102</c> (2026-11-26): the menu and its bytes free at 8, 16, 24 and 32 KB on the Model 100 and at 24
///   and 32 KB on the 102, the only sizes MAME's <c>tandy102</c> offers; the 102 at 8 and 16 KB is expected to show
///   the Model 100's figures, which is not checked against MAME. Also BASIC's banner, and the LCD, which matched
///   MAME's screen dot for dot at the menu but for the clock's seconds.
///  </para>
/// </remarks>
[TestClass]
public sealed class Trs80Model100RomTests
{
    private const string Model100 = "m100.bin";
    private const string Tandy102 = "t102.bin";

    // A hash of the menu's LCD dots below the top line, which shows the time, in a 32 KB Model 100: the dots of MAME
    // 0.264's trsm100 screen, a dot lit where its pixel is not the background.
    private const string MenuDots = "2079036D0A22EC35106A4891D14BE51094D781EE30BE7D43D5A1C88505B5B351";

    private static readonly Dictionary<string, string> s_digests = new()
    {
        [Model100] = "0ACCD7E877AD6AAD6CED81424F69E876093041F633E4900EA9D5B855830D0236",
        [Tandy102] = "21598A9172CBD7803C4B0BBEB096358343AD06B22E608AC98BCD5B2D3F1B7473"
    };

    /// <summary>
    ///  Both ROMs cold-start to the menu, with the bytes free MAME shows for each RAM size on the Model 100 (and, on
    ///  the 102, at the 24 and 32 KB MAME offers; at 8 and 16 KB, the Model 100's figures).
    /// </summary>
    [TestMethod]
    public void BootsToTheMenu()
    {
        foreach (string name in new[] { Model100, Tandy102 })
        {
            foreach ((int kilobytes, int free) in new[] { (8, 5062), (16, 13254), (24, 21446), (32, 29638) })
            {
                Trs80Model100Machine machine = Boot(name, kilobytes);
                string[] screen = machine.ScreenText();
                screen[0].Should().StartWith("Jan 01,1900 Sun").And.EndWith("(C)Microsoft", "a cold start clears the date");
                screen[1].Should().Be(" BASIC     TEXT      TELCOM    ADDRSS");
                screen[2].Should().Be(" SCHEDL    -.-       -.-       -.-");
                screen[7].Should().Be($"Select: _              {free} Bytes free");
            }
        }
    }

    /// <summary>
    ///  The ROMs are known by their digests, and the 102's tells itself apart at <c>PEEK(1)</c>.
    /// </summary>
    [TestMethod]
    public void RomsAreKnown()
    {
        Trs80Model100Roms.Identify(Rom(Model100)).Should().Be(Trs80Model100Variant.Model100);
        Trs80Model100Roms.Identify(Rom(Tandy102)).Should().Be(Trs80Model100Variant.Tandy102);
        Boot(Model100).Bus.Peek(1).Should().Be(51);
        Boot(Tandy102).Bus.Peek(1).Should().Be(167);
    }

    /// <summary>
    ///  ENTER on BASIC starts it with its banner, and it runs what is typed.
    /// </summary>
    [TestMethod]
    public void BasicRunsWhatIsTyped()
    {
        Trs80Model100Machine machine = Boot(Model100);
        Type(machine, "\r");
        machine.RunSeconds(2);
        string[] screen = machine.ScreenText();
        screen[0].Should().Be("TRS-80 Model 100 Software");
        screen[1].Should().Be("Copr. 1983 Microsoft");
        screen[2].Should().Be("29382 Bytes free");
        screen[3].Should().Be("Ok");

        Type(machine, "print 2+2;\"aabbcc112233\";peek(1)\r");
        machine.RunSeconds(2);
        screen = machine.ScreenText();
        screen[4].Should().Be("print 2+2;\"aabbcc112233\";peek(1)");
        screen[5].Should().Be(" 4 aabbcc112233 51");
        screen[6].Should().Be("Ok");
    }

    /// <summary>
    ///  TIME$ and DATE$ set the uPD1990AC through the 81C55, and its time counts on.
    /// </summary>
    [TestMethod]
    public void BasicSetsTheClock()
    {
        Trs80Model100Machine machine = Boot(Model100);
        Type(machine, "\rtime$=\"12:34:56\":date$=\"11/26/26\"\r");
        machine.RunSeconds(1);
        machine.Bus.Clock.Time(2026).Should().BeCloseTo(new DateTime(2026, 11, 26, 12, 34, 57), TimeSpan.FromSeconds(1));

        machine.RunSeconds(5);
        Type(machine, "?time$;\" \";date$\r");
        machine.RunSeconds(2);
        string line = machine.ScreenText().First(text => text.EndsWith("11/26/26", StringComparison.Ordinal));
        line.Should().MatchRegex("^12:35:0[2-5] 11/26/26$");
    }

    /// <summary>
    ///  The menu's LCD dots are the ones pinned, which matched MAME's screen.
    /// </summary>
    [TestMethod]
    public void MenuOnTheLcd()
    {
        Trs80Model100Machine machine = Boot(Model100);
        Convert.ToHexString(SHA256.HashData(Dots(machine, firstRow: 8))).Should().Be(MenuDots);
        for (int driver = 0; driver < 10; driver++) { machine.Lcd[driver].DisplayOn.Should().BeTrue(); }
    }

    /// <summary>
    ///  POWER OFF turns the machine off through port B; at the power switch the ROM finds RAM valid and comes back to
    ///  the menu, or, after POWER OFF,RESUME, to BASIC where it was, its variables kept.
    /// </summary>
    [TestMethod]
    public void PowerOffAndOn()
    {
        Trs80Model100Machine machine = Boot(Model100);
        Type(machine, "\ra=42\rpower off\r");
        machine.RunSeconds(2);
        machine.IsPoweredOff.Should().BeTrue();
        machine.PowerOn();
        machine.RunSeconds(3);
        machine.IsPoweredOff.Should().BeFalse();
        machine.ScreenText()[7].Should().StartWith("Select:");

        Type(machine, "\ra=42\rpower off,resume\r");
        machine.RunSeconds(2);
        machine.IsPoweredOff.Should().BeTrue();
        machine.PowerOn();
        machine.RunSeconds(3);
        Type(machine, "?a\r");
        machine.RunSeconds(2);
        machine.ScreenText().Should().Contain(" 42", "BASIC's variables survive in RAM");
    }

    /// <summary>
    ///  Reads a ROM from the external test data, checking its digest.
    /// </summary>
    /// <param name="name">The file name.</param>
    /// <returns>The ROM.</returns>
    internal static byte[] Rom(string name)
    {
        string directory = Environment.GetEnvironmentVariable("RETROCORE_TRS80M100_ROMS") is { Length: > 0 } configured
            ? configured
            : Path.Join(ExternalTestData.Root, "trs80m100-roms");

        string path = Path.Join(directory, name);
        if (!File.Exists(path)) { Assert.Inconclusive($"The Model 100's ROM ({path}) is missing."); }
        byte[] rom = File.ReadAllBytes(path);
        Convert.ToHexString(SHA256.HashData(rom)).Should().Be(s_digests[name], "{0} should be MAME's dump", name);
        return rom;
    }

    /// <summary>
    ///  Builds a machine and runs it to the menu, the clock set so the date is not the host's.
    /// </summary>
    /// <param name="name">The ROM's file.</param>
    /// <param name="kilobytes">The RAM.</param>
    /// <returns>The machine, at the menu.</returns>
    internal static Trs80Model100Machine Boot(string name, int kilobytes = 32)
    {
        Trs80Model100Machine machine = new(
            new Trs80Model100Configuration
            {
                RamKilobytes = kilobytes,
                StartTime = new DateTime(2026, 11, 26, 9, 30, 0)
            },
            new Trs80Model100Roms(Rom(name)));

        machine.RunSeconds(4);
        return machine;
    }

    /// <summary>
    ///  Types keys and runs until they are all pressed.
    /// </summary>
    /// <param name="machine">The machine.</param>
    /// <param name="text">The keys' codes.</param>
    internal static void Type(Trs80Model100Machine machine, string text)
    {
        foreach (char character in text) { machine.Keyboard.Type((byte)character).Should().BeTrue(); }
        while (machine.Keyboard.IsTyping) { machine.Run(10_000); }
    }

    private static byte[] Dots(Trs80Model100Machine machine, int firstRow)
    {
        byte[] dots = new byte[(Trs80Model100Lcd.Height - firstRow) * Trs80Model100Lcd.Width];
        for (int y = firstRow; y < Trs80Model100Lcd.Height; y++)
        {
            for (int x = 0; x < Trs80Model100Lcd.Width; x++)
            {
                dots[(y - firstRow) * Trs80Model100Lcd.Width + x] = machine.Lcd.Dot(x, y) ? (byte)1 : (byte)0;
            }
        }

        return dots;
    }
}
