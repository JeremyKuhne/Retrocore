// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Diagnostics;
using System.Globalization;
using System.IO.Compression;
using Retrocore.Machines.Commodore;
using Retrocore.Machines.Devices;
using Retrocore.Media;
using Retrocore.Media.Commodore;

namespace Retrocore.Tests;

/// <summary>
///  The PET's Datasettes, through the kernal's own tape routines, and the tape images they read and write.
/// </summary>
/// <remarks>
///  <para>
///   The recordings and program files are MAME's software lists, unzipped under
///   <c>%USERPROFILE%\Retrocore\pet-media\extract</c>; the tests that need them are inconclusive without them.
///  </para>
/// </remarks>
[TestClass]
public class PetTapeTests
{
    private const string Program = "10 PRINT \"TAPE\";6*7\r";

    /// <summary>
    ///  A program saved to tape loads back, runs, and VERIFY finds it the same.
    /// </summary>
    /// <param name="model">The model.</param>
    /// <param name="port">The cassette port.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, 1)]
    [DataRow(PetModel.Pet2001, 2)]
    [DataRow(PetModel.Pet2001Basic2, 1)]
    [DataRow(PetModel.Pet2001Basic2, 2)]
    public void SavedProgramLoadsAndVerifies(PetModel model, int port)
    {
        PetMachine machine = PetMachineTests.Machine(model);
        PetMachineTests.RunToReady(machine);
        PetDatasette deck = port == 1 ? machine.Bus.Cassette1 : machine.Bus.Cassette2;
        CommodoreTape tape = Save(machine, deck);

        PetMachineTests.Type(machine, "NEW\r");
        deck.Rewind();
        deck.Play();
        PetMachineTests.Type(machine, $"LOAD \"PROG\",{port}\r");
        WaitForReady(machine);
        PetMachineTests.Type(machine, "RUN\r");
        machine.ReadTextScreen().Should().Contain(line => line.TrimEnd() == "TAPE 42", Screen(machine));

        deck.Rewind();
        PetMachineTests.Type(machine, $"VERIFY \"PROG\",{port}\r");
        WaitForReady(machine);
        machine.ReadTextScreen().Should().Contain(line => line.TrimEnd() == "OK", Screen(machine));
        tape.Pulses.Count.Should().BeGreaterThan(40_000, "a file is a header and a program, each written twice");
    }

    /// <summary>
    ///  A tape built from a program file loads into each model.
    /// </summary>
    /// <param name="model">The model.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001)]
    [DataRow(PetModel.Pet2001Basic2)]
    public void ProgramFileTapeLoads(PetModel model)
    {
        PetMachine source = PetMachineTests.Machine();
        PetMachineTests.RunToReady(source);
        PetMachineTests.Type(source, Program);
        int end = source.Bus.Ram[0x2A] | (source.Bus.Ram[0x2B] << 8);
        byte[] prg = [0x01, 0x04, .. source.Bus.Ram[0x401..end]];

        PetMachine machine = PetMachineTests.Machine(model);
        PetMachineTests.RunToReady(machine);
        machine.Bus.Cassette1.Insert(CommodoreTapeBuilder.FromPrg("built", prg), "built.prg", "PRG");
        machine.Bus.Cassette1.Play();
        PetMachineTests.Type(machine, "LOAD\r");
        WaitForReady(machine);
        machine.ReadTextScreen().Should().Contain(line => line.TrimEnd() == "FOUND BUILT", Screen(machine));

        PetMachineTests.Type(machine, "RUN\r");
        machine.ReadTextScreen().Should().Contain(line => line.TrimEnd() == "TAPE 42", Screen(machine));
    }

    /// <summary>
    ///  A program from MAME's quickload list, built into a tape, loads byte for byte where its file says.
    /// </summary>
    [TestMethod]
    public void QuickloadProgramLoadsByteForByte()
    {
        byte[] prg = Unzip("pet_quik", "hardcore");
        PetMachine machine = PetMachineTests.Machine(PetModel.Pet2001Basic2);
        PetMachineTests.RunToReady(machine);
        machine.Bus.Cassette1.Insert(CommodoreTapeBuilder.FromPrg("hardcore", prg), "hardcore.prg", "PRG");
        machine.Bus.Cassette1.Play();
        PetMachineTests.Type(machine, "LOAD\r");
        WaitForReady(machine);

        int start = prg[0] | (prg[1] << 8);
        machine.Bus.Ram.Slice(start, prg.Length - 2).SequenceEqual(prg.AsSpan(2)).Should().BeTrue(Screen(machine));
        (machine.Bus.Ram[0x2A] | (machine.Bus.Ram[0x2B] << 8)).Should().Be(start + prg.Length - 2, Screen(machine));
    }

    /// <summary>
    ///  A 1980 recording from MAME's cassette list, a WAV file, loads into each model.
    /// </summary>
    /// <param name="model">The model.</param>
    /// <param name="variables">
    ///  Where the BASIC keeps the end of the program: <c>$7C</c> in BASIC 1, <c>$2A</c> in BASIC 2.
    /// </param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, 0x7C)]
    [DataRow(PetModel.Pet2001Basic2, 0x2A)]
    public void RecordingLoads(PetModel model, int variables)
    {
        CommodoreTape tape = CommodoreWave.Read(Unzip("pet_cass", "mecou"));
        PetMachine machine = PetMachineTests.Machine(model);
        PetMachineTests.RunToReady(machine);
        machine.Bus.Cassette1.Insert(tape, "Count'Em", "WAV");
        machine.Bus.Cassette1.Play();
        PetMachineTests.Type(machine, "LOAD\r");
        WaitForReady(machine);

        string[] screen = machine.ReadTextScreen();
        screen.Should().Contain(line => line.TrimEnd() == "FOUND COUNT'EM", Screen(machine));
        screen.Should().NotContain(line => line.Contains("ERROR", StringComparison.Ordinal), Screen(machine));
        (machine.Bus.Ram[variables] | (machine.Bus.Ram[variables + 1] << 8)).Should().Be(0x0C17);
    }

    /// <summary>
    ///  A TAP image keeps every pulse: lengths of 8 µs units in a byte, others after a zero.
    /// </summary>
    [TestMethod]
    public void TapImageKeepsEveryPulse()
    {
        int[] pulses = [352, 504, 672, 7, 2041, 2040, 16, 1_000_000];
        byte[] image = TapFormat.Write(pulses);
        image.AsSpan(0, 12).SequenceEqual("C64-TAPE-RAW"u8).Should().BeTrue();
        image[12].Should().Be(1);
        image[13].Should().Be(TapFormat.PetMachine);
        image[20].Should().Be(352 / 8);
        TapFormat.Read(image).Pulses.Should().Equal(pulses);
    }

    /// <summary>
    ///  A C64 image's units are 8 of the C64's cycles, 985,248 a second on PAL, so a byte of 47 is 382 µs; in a
    ///  version 0 image a zero is a pause of 256 units.
    /// </summary>
    [TestMethod]
    public void TapImageFromTheC64UsesItsClock()
    {
        byte[] image = new byte[22];
        "C64-TAPE-RAW"u8.CopyTo(image);
        image[16] = 2;
        image[20] = 47;
        TapFormat.Read(image).Pulses.Should().Equal(382, 2079);
    }

    /// <summary>
    ///  A saved tape written as WAV, its pulses rounded to 1/44,100 second, still loads.
    /// </summary>
    [TestMethod]
    public void TapeSavedAsWaveLoads()
    {
        PetMachine machine = PetMachineTests.Machine();
        PetMachineTests.RunToReady(machine);
        CommodoreTape tape = Save(machine, machine.Bus.Cassette1);
        EncodedImage wave = new CommodoreTapeCodec("WAV").Encode(tape.Snapshot());
        wave.Losses.Should().ContainSingle();

        PetMachineTests.Type(machine, "NEW\r");
        machine.Bus.Cassette1.Insert(CommodoreWave.Read(wave.Bytes), "prog.wav", "WAV");
        machine.Bus.Cassette1.Play();
        PetMachineTests.Type(machine, "LOAD\r");
        WaitForReady(machine);
        PetMachineTests.Type(machine, "RUN\r");
        machine.ReadTextScreen().Should().Contain(line => line.TrimEnd() == "TAPE 42", Screen(machine));
    }

    /// <summary>
    ///  The Datasette is a medium slot: a recording changes its tape, a save to TAP holds all of it and marks it
    ///  saved, a protected tape will not record, and each tape put in or taken out is a new mount.
    /// </summary>
    [TestMethod]
    public void DatasetteSavesItsTape()
    {
        PetMachine machine = PetMachineTests.Machine();
        PetDatasette deck = machine.Bus.Cassette1;
        IMediumSlot slot = deck;
        deck.Media.Should().BeNull();
        deck.Info.SaveFormats.Should().Equal("tap", "wav");

        int generation = slot.MountGeneration;
        PetMachineTests.RunToReady(machine);
        CommodoreTape tape = Save(machine, deck);
        slot.MountGeneration.Should().NotBe(generation);
        slot.Medium.Should().BeSameAs(tape);
        deck.Media.Should().Be(new MediaState("blank", "TAP", WriteProtected: false, Changed: true));
        EncodedImage image = new CommodoreTapeCodec().Encode(tape.Snapshot());
        image.IsLossless.Should().BeTrue();
        TapFormat.Read(image.Bytes).Pulses.Should().Equal(tape.Pulses);

        slot.Saved("prog.tap", "TAP", whole: true);
        deck.Media.Should().Be(new MediaState("prog.tap", "TAP", WriteProtected: false, Changed: false));

        tape.IsWriteProtected = true;
        FluentActions.Invoking(deck.Record).Should().Throw<InvalidOperationException>();
        deck.Eject().Should().BeSameAs(tape);
        deck.Media.Should().BeNull();
    }

    /// <summary>
    ///  MAME loads a tape the PET saved, as TAP and as WAV, to the same bytes.
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

        string roms = Path.Join(Path.GetDirectoryName(PetMachineTests.RomRoot), "mame");
        if (!File.Exists(mame) || !File.Exists(Path.Join(roms, "pet2001n.zip")))
        {
            Assert.Inconclusive("MAME or the PET ROM sets are missing.");
        }

        PetMachine machine = PetMachineTests.Machine();
        PetMachineTests.RunToReady(machine);
        CommodoreTape tape = Save(machine, machine.Bus.Cassette1);
        int end = machine.Bus.Ram[0x2A] | (machine.Bus.Ram[0x2B] << 8);
        byte[] image = new CommodoreTapeCodec(format).Encode(tape.Snapshot()).Bytes;

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
                "pet2001n", "-ieee8", "", "-cass1", path, "-rompath", roms, "-cfg_directory", work,
                "-nvram_directory", work, "-video", "none", "-sound", "none", "-nothrottle", "-skip_gameinfo",
                "-seconds_to_run", "60", "-autoboot_script", FindTool("PetTapeLoad.lua"), "-autoboot_delay", "0"
            ];

            foreach (string argument in arguments) { start.ArgumentList.Add(argument); }
            start.Environment["RETRO_END"] = 40.ToString(CultureInfo.InvariantCulture);
            start.Environment["RETRO_OUT"] = output;
            using (Process process = Process.Start(start) ?? throw new InvalidOperationException("MAME did not start."))
            {
                process.StandardOutput.ReadToEnd();
                process.WaitForExit(300_000).Should().BeTrue("MAME finishes");
            }

            byte[] memory = File.ReadAllBytes(output).AsSpan(1000).ToArray();
            (memory[0x2A] | (memory[0x2B] << 8)).Should().Be(end, "MAME loaded the whole program");
            memory.AsSpan(0x401, end - 0x401).SequenceEqual(machine.Bus.Ram[0x401..end]).Should().BeTrue();
        }
        finally
        {
            Directory.Delete(work, recursive: true);
        }
    }

    /// <summary>
    ///  Runs until the cursor waits at a fresh <c>READY.</c>, the last thing on the screen, for up to five minutes.
    /// </summary>
    /// <param name="machine">The machine.</param>
    internal static void WaitForReady(PetMachine machine)
    {
        for (int tenth = 0; tenth < 3000; tenth++)
        {
            machine.Run(TimeSpan.FromSeconds(0.1));
            string[] screen = machine.ReadTextScreen();
            int last = Array.FindLastIndex(screen, line => line.Trim().Length != 0);
            if (last >= 0 && screen[last].StartsWith("READY.", StringComparison.Ordinal)) { return; }
        }
    }

    // Types the program and saves it as PROG onto a blank tape in the deck.
    private static CommodoreTape Save(PetMachine machine, PetDatasette deck)
    {
        CommodoreTape tape = new();
        deck.Insert(tape, "blank", "TAP", changed: true);
        PetMachineTests.Type(machine, Program);
        deck.Record();
        PetMachineTests.Type(machine, $"SAVE \"PROG\",{deck.Port}\r");
        WaitForReady(machine);
        deck.Stop();
        return tape;
    }

    private static byte[] Unzip(string list, string software)
    {
        string zip = Path.Join(ExternalTestData.Root, "pet-media", "extract", list, list, software + ".zip");
        if (!File.Exists(zip)) { Assert.Inconclusive($"MAME's {list} list is missing; see pet-media's README."); }
        using ZipArchive archive = ZipFile.OpenRead(zip);
        using MemoryStream stream = new();
        using (Stream entry = archive.Entries[0].Open()) { entry.CopyTo(stream); }
        return stream.ToArray();
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

    private static string Screen(PetMachine machine) => string.Join('\n', machine.ReadTextScreen());
}
