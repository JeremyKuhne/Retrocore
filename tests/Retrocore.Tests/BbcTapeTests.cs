// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.IO.Compression;
using Retrocore.Machines.Acorn;
using Retrocore.Machines.Devices;
using Retrocore.Media.Acorn;

namespace Retrocore.Tests;

/// <summary>
///  The BBC Micro's cassette filing system through the serial ULA and the 6850, at tone level, and RS-423.
/// </summary>
[TestClass]
public class BbcTapeTests
{
    // 10 PRINT "BUILT", tokenized: a line is &0D, its number high and low, its length, then its text.
    private static readonly byte[] s_program =
        [0x0D, 0x00, 0x0A, 0x0C, 0xF1, 0x22, (byte)'B', (byte)'U', (byte)'I', (byte)'L', (byte)'T', 0x22, 0x0D, 0xFF];

    /// <summary>
    ///  Gets the Welcome tape from MAME's software list, or marks the test inconclusive.
    /// </summary>
    /// <returns>The tape.</returns>
    internal static AcornTape WelcomeTape()
    {
        string zip = Path.Join(ExternalTestData.Root, "bbc-media", "extract", "bbcb_cass", "bbcb_cass", "welcome.zip");
        if (!File.Exists(zip)) { Assert.Inconclusive("The bbcb_cass software list is missing from bbc-media."); }
        using ZipArchive archive = ZipFile.OpenRead(zip);
        ZipArchiveEntry entry = archive.Entries.Single(entry => entry.Name.EndsWith(".uef", StringComparison.OrdinalIgnoreCase));
        using Stream stream = entry.Open();
        using MemoryStream bytes = new();
        stream.CopyTo(bytes);
        return UefFormat.Read(bytes.ToArray());
    }

    /// <summary>
    ///  *CAT reads the Welcome tape's first file, block by block.
    /// </summary>
    [TestMethod]
    public void CatalogReadsTheWelcomeTape()
    {
        BbcMachine machine = BbcMachineTests.Machine();
        BbcMachineTests.RunToPrompt(machine);
        machine.Cassette.Insert(WelcomeTape(), "welcome.uef");
        machine.Cassette.Play();
        BbcMachineTests.Type(machine, "*CAT\r");
        machine.Run(TimeSpan.FromSeconds(15));
        string text = string.Join('\n', machine.ReadTextScreen());
        machine.ReadTextScreen().Should().Contain(line => line.StartsWith("INTRO      0", StringComparison.Ordinal), text);
        machine.Cassette.Activity.Should().Be(DeviceActivity.Reading);
    }

    /// <summary>
    ///  CHAIN "" loads the Welcome tape's introduction and runs it, which stops the motor.
    /// </summary>
    [TestMethod]
    public void ChainRunsTheWelcomeTape()
    {
        BbcMachine machine = BbcMachineTests.Machine();
        BbcMachineTests.RunToPrompt(machine);
        machine.Cassette.Insert(WelcomeTape(), "welcome.uef");
        machine.Cassette.Play();
        BbcMachineTests.Type(machine, "CHAIN \"\"\r");
        machine.Run(TimeSpan.FromSeconds(90));
        string[] screen = machine.ReadTextScreen();
        screen.Should().Contain(line => line.Trim() == "Press the STOP button", string.Join('\n', screen));
        machine.Cassette.Motor.Should().BeFalse();
    }

    /// <summary>
    ///  SAVE records a program on a blank tape, as UEF that reads back the same, and LOAD brings it back at the rate
    ///  it was saved: *TAPE (1200 baud) or *TAPE3 (300).
    /// </summary>
    /// <param name="command">The rate's command.</param>
    /// <param name="seconds">Enough emulated time to save or load it.</param>
    [TestMethod]
    [DataRow("*TAPE", 30)]
    [DataRow("*TAPE3", 60)]
    public void SaveThenLoad(string command, int seconds)
    {
        BbcMachine machine = BbcMachineTests.Machine();
        BbcMachineTests.RunToPrompt(machine);
        AcornTape tape = new();
        machine.Cassette.Insert(tape, "blank.uef", changed: true);
        BbcMachineTests.Type(machine, command + "\r");
        BbcMachineTests.Type(machine, "10 FOR I%=1 TO 3:PRINT \"LINE \";I%:NEXT\r20 REM " + new string('X', 250) + "\r");

        machine.Cassette.Record();
        BbcMachineTests.Type(machine, "SAVE \"PROG\"\r\r");
        machine.Run(TimeSpan.FromSeconds(seconds));
        machine.ReadTextScreen().Should().Contain(line => line.StartsWith("PROG       01 01", StringComparison.Ordinal));
        machine.Cassette.Media?.Changed.Should().BeTrue();
        UefFormat.Read(UefFormat.Write(tape.HalfCycles)).HalfCycles.Should().Equal(tape.HalfCycles);

        machine.Cassette.Stop();
        machine.Cassette.Rewind();
        machine.Cassette.Play();
        BbcMachineTests.Type(machine, "NEW\rLOAD \"PROG\"\r");
        machine.Run(TimeSpan.FromSeconds(seconds));
        BbcMachineTests.Type(machine, "RUN\r");
        string[] screen = machine.ReadTextScreen();
        screen.Should().Contain(line => line.TrimEnd() == "LINE 3", string.Join('\n', screen));
    }

    /// <summary>
    ///  A file built as the MOS would save it, from its data and <c>.inf</c> description, CHAINs.
    /// </summary>
    [TestMethod]
    public void BuiltTapeChains()
    {
        BbcMachine machine = BbcMachineTests.Machine();
        BbcMachineTests.RunToPrompt(machine);
        AcornTapeFile file = AcornTapeFile.FromInf("$.BUILT FFFF0E00 FFFF8023", s_program);
        machine.Cassette.Insert(AcornTapeBuilder.Build([file]), "built.uef");
        machine.Cassette.Play();
        BbcMachineTests.Type(machine, "CHAIN \"BUILT\"\r");
        machine.Run(TimeSpan.FromSeconds(12));
        string[] screen = machine.ReadTextScreen();
        screen.Should().Contain(line => line.TrimEnd() == "BUILT", string.Join('\n', screen));
    }

    /// <summary>
    ///  With RS-423 as the input stream (*FX2,1), characters from the line are typed; with RS-423 also an output
    ///  stream (*FX3,1), the screen's text goes out on it.
    /// </summary>
    [TestMethod]
    public void Rs423CarriesInputAndOutput()
    {
        BbcMachine machine = BbcMachineTests.Machine();
        BbcMachineTests.RunToPrompt(machine);
        List<byte> sent = [];
        machine.Bus.Acia.Transmitted = sent.Add;
        BbcMachineTests.Type(machine, "*FX3,1\r*FX2,1\r");
        machine.Bus.SerialUla.Rs423.Should().BeTrue();

        Queue<byte> line = new("PRINT 6*7\r"u8.ToArray());
        for (int step = 0; step < 400 && line.Count != 0; step++)
        {
            if (machine.Bus.Acia.CanReceive) { machine.Bus.Acia.Receive(line.Dequeue()); }
            machine.Run(TimeSpan.FromMilliseconds(5));
        }

        machine.Run(TimeSpan.FromSeconds(0.5));
        System.Text.Encoding.ASCII.GetString([.. sent]).Should().Contain("42");
        machine.ReadTextScreen().Should().Contain(line => line.Trim() == "42");
    }
}
