// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Diagnostics;
using System.Globalization;
using System.IO.Compression;
using Retrocore.Machines.Chips;
using Retrocore.Machines.Commodore;
using Retrocore.Machines.Commodore.Vic20;
using Retrocore.Machines.Devices;
using Retrocore.Media;
using Retrocore.Media.Commodore;

namespace Retrocore.Tests;

/// <summary>
///  The VIC-20's Datasette, through the kernal's own tape routines, and the TAP images it writes at its clocks.
/// </summary>
/// <remarks>
///  <para>
///   The tapes are MAME's <c>vic1001_cass</c> list, unzipped under <c>%USERPROFILE%\Retrocore\vic20-media\extract</c>;
///   the tests that need them are inconclusive without them.
///  </para>
/// </remarks>
[TestClass]
public class Vic20TapeTests
{
    private const string Program = "10 PRINT \"TAPE\";6*7\r";

    /// <summary>
    ///  A program saved to tape loads back, runs, and VERIFY finds it the same, at both standards' clocks.
    /// </summary>
    /// <param name="standard">The video standard.</param>
    [TestMethod]
    [DataRow(VicVideoStandard.Ntsc)]
    [DataRow(VicVideoStandard.Pal)]
    public void SavedProgramLoadsAndVerifies(VicVideoStandard standard)
    {
        Vic20Machine machine = Vic20MachineTests.Machine(standard);
        Vic20MachineTests.RunToReady(machine);
        CommodoreTape tape = Save(machine);

        Vic20MachineTests.Type(machine, "NEW\r");
        machine.Cassette.Rewind();
        machine.Cassette.Play();
        Vic20MachineTests.Type(machine, "LOAD \"PROG\"\r");
        WaitForReady(machine);
        machine.ReadTextScreen().Should().Contain(line => line.TrimEnd() == "FOUND PROG", Screen(machine));
        Vic20MachineTests.Type(machine, "RUN\r");
        machine.ReadTextScreen().Should().Contain(line => line.TrimEnd() == "TAPE 42", Screen(machine));

        machine.Cassette.Rewind();
        Vic20MachineTests.Type(machine, "VERIFY \"PROG\"\r");
        WaitForReady(machine);
        machine.ReadTextScreen().Should().Contain(line => line.TrimEnd() == "OK", Screen(machine));
        tape.Pulses.Count.Should().BeGreaterThan(20_000, "a file is a header and a program, each written twice");
    }

    /// <summary>
    ///  A tape the NTSC machine saves loads on the PAL one, 8% faster, and the other way, as the kernal's reader allows.
    /// </summary>
    /// <param name="from">The standard that saves.</param>
    /// <param name="to">The standard that loads.</param>
    [TestMethod]
    [DataRow(VicVideoStandard.Ntsc, VicVideoStandard.Pal)]
    [DataRow(VicVideoStandard.Pal, VicVideoStandard.Ntsc)]
    public void TapeLoadsOnTheOtherStandard(VicVideoStandard from, VicVideoStandard to)
    {
        Vic20Machine source = Vic20MachineTests.Machine(from);
        Vic20MachineTests.RunToReady(source);
        CommodoreTape tape = Save(source);

        Vic20Machine machine = Vic20MachineTests.Machine(to);
        Vic20MachineTests.RunToReady(machine);
        machine.Cassette.Insert(tape, "prog.tap", "TAP");
        machine.Cassette.Play();
        Vic20MachineTests.Type(machine, "LOAD\r");
        WaitForReady(machine);
        Vic20MachineTests.Type(machine, "RUN\r");
        machine.ReadTextScreen().Should().Contain(line => line.TrimEnd() == "TAPE 42", Screen(machine));
    }

    /// <summary>
    ///  A tape built from a program file, at the PET's pulse lengths, loads, its lines where the VIC-20's BASIC starts.
    /// </summary>
    [TestMethod]
    public void ProgramFileTapeLoads()
    {
        Vic20Machine source = Vic20MachineTests.Machine();
        Vic20MachineTests.RunToReady(source);
        Vic20MachineTests.Type(source, Program);
        int end = source.Bus.Peek(0x2D) | (source.Bus.Peek(0x2E) << 8);
        byte[] prg = [0x01, 0x10, .. Enumerable.Range(0x1001, end - 0x1001).Select(a => source.Bus.Peek((ushort)a))];

        Vic20Machine machine = Vic20MachineTests.Machine();
        Vic20MachineTests.RunToReady(machine);
        machine.Cassette.Insert(CommodoreTapeBuilder.FromPrg("built", prg), "built.prg", "PRG");
        machine.Cassette.Play();
        Vic20MachineTests.Type(machine, "LOAD\r");
        WaitForReady(machine);
        machine.ReadTextScreen().Should().Contain(line => line.TrimEnd() == "FOUND BUILT", Screen(machine));

        Vic20MachineTests.Type(machine, "RUN\r");
        machine.ReadTextScreen().Should().Contain(line => line.TrimEnd() == "TAPE 42", Screen(machine));
    }

    /// <summary>
    ///  A program file loaded straight into memory, from an unexpanded machine onto one with 8K, goes to BASIC's start
    ///  there with its lines relinked, and runs.
    /// </summary>
    [TestMethod]
    public void ProgramFileLoadsIntoMemory()
    {
        Vic20Machine source = Vic20MachineTests.Machine();
        Vic20MachineTests.RunToReady(source);
        Vic20MachineTests.Type(source, Program + "20 PRINT \"END\"\r");
        int end = source.Bus.Peek(0x2D) | (source.Bus.Peek(0x2E) << 8);
        byte[] prg = [0x01, 0x10, .. Enumerable.Range(0x1001, end - 0x1001).Select(a => source.Bus.Peek((ushort)a))];

        Vic20Machine machine = Vic20MachineTests.Machine(expansion: Vic20Expansion.Ram8K);
        Vic20MachineTests.RunToReady(machine);
        (ushort start, ushort loadedEnd) = machine.LoadProgram(prg);
        start.Should().Be(0x1201);
        loadedEnd.Should().Be((ushort)(0x1201 + prg.Length - 2));
        Vic20MachineTests.Type(machine, "LIST\rRUN\r");
        string[] screen = machine.ReadTextScreen();
        screen.Should().Contain(line => line.TrimEnd() == "20 PRINT \"END\"", Screen(machine));
        screen.Should().Contain(line => line.TrimEnd() == "TAPE 42", Screen(machine));
        screen.Should().Contain(line => line.TrimEnd() == "END", Screen(machine));
    }

    /// <summary>
    ///  MAME's two tapes load: 3D Maze, a TAP image, and Speakeasy's first file, from a WAV recording.
    /// </summary>
    /// <param name="software">The list's name for the tape.</param>
    /// <param name="found">The name LOAD finds.</param>
    [TestMethod]
    [DataRow("3dmaze", "FOUND 3D MAZE")]
    [DataRow("speakez", "FOUND PHONEME EDITOR")]
    public void MameTapeLoads(string software, string found)
    {
        (string name, byte[] image) = Unzip(software);
        (CommodoreTape tape, CommodoreTapeCodec codec) = CommodoreTapeCodec.Load(image);
        Vic20Machine machine = Vic20MachineTests.Machine();
        Vic20MachineTests.RunToReady(machine);
        machine.Cassette.Insert(tape, name, codec.Format);
        machine.Cassette.Play();
        Vic20MachineTests.Type(machine, "LOAD\r");
        WaitForReady(machine);

        string[] screen = machine.ReadTextScreen();
        screen.Should().Contain(line => line.TrimEnd().StartsWith(found, StringComparison.Ordinal), Screen(machine));
        screen.Should().NotContain(line => line.Contains("ERROR", StringComparison.Ordinal), Screen(machine));
        (machine.Bus.Peek(0x2D) | (machine.Bus.Peek(0x2E) << 8)).Should().BeGreaterThan(0x1010, "a program loaded");
    }

    /// <summary>
    ///  A TAP image the VIC-20 writes names it and its standard, counts its clock's cycles, and reads back to the same
    ///  pulses.
    /// </summary>
    /// <param name="standard">The video standard.</param>
    /// <param name="video">The header's video byte.</param>
    [TestMethod]
    [DataRow(VicVideoStandard.Ntsc, TapFormat.Ntsc)]
    [DataRow(VicVideoStandard.Pal, TapFormat.Pal)]
    public void TapImageCountsTheVic20sCycles(VicVideoStandard standard, byte video)
    {
        Vic20Machine machine = Vic20MachineTests.Machine(standard);
        CommodoreDatasette deck = machine.Cassette;
        deck.TapMachine.Should().Be(TapFormat.Vic20Machine);
        deck.TapVideo.Should().Be(video);

        int[] pulses = [352, 504, 672, 7, 2041, 2040, 16, 1_000_000];
        CommodoreTapeCodec codec = new("TAP", deck.TapMachine, deck.TapVideo);
        EncodedImage image = codec.Encode(new CommodoreTape(pulses).Snapshot());
        image.IsLossless.Should().BeTrue();
        image.Bytes[13].Should().Be(TapFormat.Vic20Machine);
        image.Bytes[14].Should().Be(video);
        TapFormat.Read(image.Bytes).Pulses.Should().Equal(pulses);

        // A pulse of a whole number of 8-cycle units is a byte after the 20-byte header.
        int pulse = (int)Math.Round(44 * 8 * 1_000_000 / TapFormat.Clock(TapFormat.Vic20Machine, video));
        byte[] one = TapFormat.Write([pulse], TapFormat.Vic20Machine, video);
        one.Should().HaveCount(21);
        one[20].Should().Be(44);
        CommodoreTapeCodec.Load(image.Bytes).Codec.Machine.Should().Be(TapFormat.Vic20Machine);
    }

    /// <summary>
    ///  MAME's VIC-20 loads a tape ours saved, as TAP and as WAV, to the same bytes.
    /// </summary>
    /// <param name="format">The image format.</param>
    [TestMethod]
    [TestCategory("Conformance")]
    [DataRow("TAP")]
    [DataRow("WAV")]
    public void MameLoadsSavedTape(string format)
    {
        string mame = Environment.GetEnvironmentVariable("RETROCORE_MAME")
            ?? Path.Join(ExternalTestData.Root, "mame", "mame.exe");

        string roms = Path.Join(Path.GetDirectoryName(Vic20MachineTests.RomRoot), "mame");
        if (!File.Exists(mame) || !File.Exists(Path.Join(roms, "vic20.zip")))
        {
            Assert.Inconclusive("MAME or the VIC-20 ROM sets are missing.");
        }

        Vic20Machine machine = Vic20MachineTests.Machine();
        Vic20MachineTests.RunToReady(machine);
        CommodoreTape tape = Save(machine);
        int end = machine.Bus.Peek(0x2D) | (machine.Bus.Peek(0x2E) << 8);
        byte[] image = new CommodoreTapeCodec(format, machine.Cassette.TapMachine, machine.Cassette.TapVideo)
            .Encode(tape.Snapshot()).Bytes;

        string work = Directory.CreateTempSubdirectory("retrocore-mame").FullName;
        try
        {
            string path = Path.Join(work, "prog." + format.ToLowerInvariant());
            File.WriteAllBytes(path, image);
            string output = Path.Join(work, "memory.bin");
            ProcessStartInfo start = new(mame)
            {
                WorkingDirectory = work,
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            };

            string[] arguments =
            [
                "vic20", "-iec8", "", "-cass", path, "-rompath", roms, "-cfg_directory", work,
                "-nvram_directory", work, "-video", "none", "-sound", "none", "-nothrottle", "-skip_gameinfo",
                "-seconds_to_run", "90", "-autoboot_script", FindTool("PetTapeLoad.lua"), "-autoboot_delay", "0"
            ];

            foreach (string argument in arguments) { start.ArgumentList.Add(argument); }
            start.Environment["RETRO_END"] = 60.ToString(CultureInfo.InvariantCulture);
            start.Environment["RETRO_OUT"] = output;
            start.Environment["RETRO_CPU"] = "ue10";
            PetOracleTests.RunToExit(start);

            byte[] memory = File.ReadAllBytes(output).AsSpan(1000).ToArray();
            (memory[0x2D] | (memory[0x2E] << 8)).Should().Be(end, "MAME loaded the whole program");
            for (int address = 0x1001; address < end; address++)
            {
                memory[address].Should().Be(machine.Bus.Peek((ushort)address), $"${address:X4} loaded the same");
            }
        }
        finally
        {
            Directory.Delete(work, recursive: true);
        }
    }

    /// <summary>
    ///  The Datasette is the machine's device and a medium slot: a recording changes its tape, and a protected tape
    ///  will not record.
    /// </summary>
    [TestMethod]
    public void DatasetteIsTheMachinesDevice()
    {
        Vic20Machine machine = Vic20MachineTests.Machine();
        machine.Devices.Should().Equal(machine.Cassette);
        machine.Cassette.Info.SaveFormats.Should().Equal("tap", "wav");
        Vic20MachineTests.RunToReady(machine);
        CommodoreTape tape = Save(machine);
        machine.Cassette.Media.Should().Be(new MediaState("blank", "TAP", WriteProtected: false, Changed: true));

        tape.IsWriteProtected = true;
        FluentActions.Invoking(machine.Cassette.Record).Should().Throw<InvalidOperationException>();
    }

    /// <summary>
    ///  Runs until the cursor waits at a fresh <c>READY.</c>, the last thing on the screen, for up to five minutes.
    /// </summary>
    /// <param name="machine">The machine.</param>
    internal static void WaitForReady(Vic20Machine machine)
    {
        for (int tenth = 0; tenth < 3000; tenth++)
        {
            machine.Run(TimeSpan.FromSeconds(0.1));
            string[] screen = machine.ReadTextScreen();
            int last = Array.FindLastIndex(screen, line => line.Trim().Length != 0);
            if (last >= 0 && screen[last].StartsWith("READY.", StringComparison.Ordinal)) { return; }
        }
    }

    // Types the program and saves it as PROG onto a blank tape.
    private static CommodoreTape Save(Vic20Machine machine)
    {
        CommodoreTape tape = new();
        machine.Cassette.Insert(tape, "blank", "TAP", changed: true);
        Vic20MachineTests.Type(machine, Program);
        machine.Cassette.Record();
        Vic20MachineTests.Type(machine, "SAVE \"PROG\"\r");
        WaitForReady(machine);
        machine.Cassette.Stop();
        return tape;
    }

    private static (string Name, byte[] Image) Unzip(string software)
    {
        string zip = Path.Join(ExternalTestData.Root, "vic20-media", "extract", "vic1001_cass", "vic1001_cass", software + ".zip");
        if (!File.Exists(zip))
        {
            Assert.Inconclusive("MAME's vic1001_cass list is missing; see vic20-media's README.");
        }

        using ZipArchive archive = ZipFile.OpenRead(zip);
        using MemoryStream stream = new();
        using (Stream entry = archive.Entries[0].Open()) { entry.CopyTo(stream); }
        return (archive.Entries[0].Name, stream.ToArray());
    }

    private static string FindTool(string name)
    {
        for (DirectoryInfo? directory = new(AppContext.BaseDirectory); directory is not null; directory = directory.Parent)
        {
            string candidate = Path.Join(directory.FullName, "tools", name);
            if (File.Exists(candidate)) { return candidate; }
        }

        throw new FileNotFoundException(name);
    }

    private static string Screen(Vic20Machine machine) => string.Join('\n', machine.ReadTextScreen());
}
