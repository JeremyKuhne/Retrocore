// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Commodore;

namespace Retrocore.Tests;

/// <summary>
///  The PET 2001 and 4032 on their own ROMs, which need the dumps: MAME's <c>pet2001</c>, <c>pet2001n</c>,
///  <c>pet4016</c> and <c>pet4032b</c> sets, unzipped, in <c>RETROCORE_PET_ROMS</c> (a folder holding them) or
///  <c>%USERPROFILE%\Retrocore\pet-roms\extract</c>.
/// </summary>
[TestClass]
public class PetMachineTests
{
    /// <summary>
    ///  Gets the folder holding each MAME set's chips in a folder named for the set.
    /// </summary>
    internal static string RomRoot => Environment.GetEnvironmentVariable("RETROCORE_PET_ROMS")
        ?? Path.Join(ExternalTestData.Root, "pet-roms", "extract");

    /// <summary>
    ///  Gets the folder of a model's MAME set.
    /// </summary>
    /// <param name="model">The model.</param>
    /// <returns>The folder.</returns>
    internal static string RomDirectory(PetModel model) => Path.Join(RomRoot, model switch
    {
        PetModel.Pet2001 => "pet2001",
        PetModel.Pet2001Basic2 => "pet2001n",
        PetModel.Pet4032 => "pet4016",
        _ => "pet4032b"
    });

    /// <summary>
    ///  Gets a chip each model's set must hold.
    /// </summary>
    /// <param name="model">The model.</param>
    /// <returns>The chip's file name.</returns>
    internal static string KernalChip(PetModel model) => model switch
    {
        PetModel.Pet2001 => "901447-07.h7",
        PetModel.Pet2001Basic2 => "901465-03.ud9",
        PetModel.Pet4032 => "901447-29.ud8",
        _ => "901474-02.ud8"
    };

    /// <summary>
    ///  Makes a machine at power-on, or marks the test inconclusive without the dumps.
    /// </summary>
    /// <param name="model">The model.</param>
    /// <param name="ramKilobytes">4, 8, 16 or 32.</param>
    /// <returns>The machine.</returns>
    internal static PetMachine Machine(PetModel model = PetModel.Pet2001Basic2, int ramKilobytes = 8)
    {
        string directory = RomDirectory(model);
        if (!File.Exists(Path.Join(directory, KernalChip(model))))
        {
            Assert.Inconclusive(
                "Set RETROCORE_PET_ROMS to a folder with MAME's pet2001, pet2001n, pet4016 and pet4032b sets unzipped.");
        }

        return new(PetRoms.LoadFromDirectory(directory, model), model, ramKilobytes);
    }

    /// <summary>
    ///  Runs until the screen shows <c>READY.</c>, for up to ten emulated seconds.
    /// </summary>
    /// <param name="machine">The machine.</param>
    /// <returns>The screen.</returns>
    internal static string[] RunToReady(PetMachine machine)
    {
        for (int tenth = 0; tenth < 100; tenth++)
        {
            machine.Run(TimeSpan.FromSeconds(0.1));
            string[] screen = machine.ReadTextScreen();
            if (screen.Any(line => line.StartsWith("READY.", StringComparison.Ordinal))) { return screen; }
        }

        return machine.ReadTextScreen();
    }

    /// <summary>
    ///  Types text and waits until the keyboard is done, and half a second more.
    /// </summary>
    /// <param name="machine">The machine.</param>
    /// <param name="text">The text, with carriage returns for RETURN.</param>
    internal static void Type(PetMachine machine, string text)
    {
        foreach (char c in text) { machine.Keyboard.Type((byte)c).Should().BeTrue($"the PET has a key for {c}"); }
        while (machine.Keyboard.IsTyping) { machine.Run(TimeSpan.FromSeconds(0.05)); }
        machine.Run(TimeSpan.FromSeconds(0.5));
    }

    /// <summary>
    ///  Each BASIC starts with its banner and the bytes free for the RAM size.
    /// </summary>
    /// <param name="model">The model.</param>
    /// <param name="ramKilobytes">The RAM size.</param>
    /// <param name="banner">The first line.</param>
    /// <param name="free">The second line.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, 4, "*** COMMODORE BASIC ***", " 3071 BYTES FREE")]
    [DataRow(PetModel.Pet2001, 8, "*** COMMODORE BASIC ***", " 7167 BYTES FREE")]
    [DataRow(PetModel.Pet2001, 32, "*** COMMODORE BASIC ***", " 31743 BYTES FREE")]
    [DataRow(PetModel.Pet2001Basic2, 8, "### COMMODORE BASIC ###", " 7167 BYTES FREE")]
    [DataRow(PetModel.Pet2001Basic2, 16, "### COMMODORE BASIC ###", " 15359 BYTES FREE")]
    [DataRow(PetModel.Pet2001Basic2, 32, "### COMMODORE BASIC ###", " 31743 BYTES FREE")]
    [DataRow(PetModel.Pet4032, 8, "*** COMMODORE BASIC 4.0 ***", " 7167 BYTES FREE")]
    [DataRow(PetModel.Pet4032, 16, "*** COMMODORE BASIC 4.0 ***", " 15359 BYTES FREE")]
    [DataRow(PetModel.Pet4032, 32, "*** COMMODORE BASIC 4.0 ***", " 31743 BYTES FREE")]
    [DataRow(PetModel.Pet4032Business, 32, "*** COMMODORE BASIC 4.0 ***", " 31743 BYTES FREE")]
    public void BootsToReady(PetModel model, int ramKilobytes, string banner, string free)
    {
        PetMachine machine = Machine(model, ramKilobytes);
        string[] screen = RunToReady(machine);
        string text = string.Join('\n', screen);
        screen.Should().Contain(line => line.Trim() == banner.Trim(), text);
        screen.Should().Contain(line => line.TrimEnd() == free, text);
        screen.Should().Contain(line => line.StartsWith("READY.", StringComparison.Ordinal), text);
    }

    /// <summary>
    ///  A program typed at the keyboard is stored and runs.
    /// </summary>
    /// <param name="model">The model.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001)]
    [DataRow(PetModel.Pet2001Basic2)]
    [DataRow(PetModel.Pet4032)]
    [DataRow(PetModel.Pet4032Business)]
    public void TypedProgramRuns(PetModel model)
    {
        PetMachine machine = Machine(model);
        RunToReady(machine);

        Type(machine, "10 PRINT \"HELLO\";2+3*4;\"<=>?!#$%&'()+-/:;@[]\"\rRUN\r");
        string[] screen = machine.ReadTextScreen();
        screen.Should().Contain(
            line => line.TrimEnd() == "HELLO 14 <=>?!#$%&'()+-/:;@[]",
            string.Join('\n', screen));
    }

    /// <summary>
    ///  POKE 59468,14 sets the VIA's CA2 high, which shows the character set with lowercase; 12 sets it back.
    /// </summary>
    [TestMethod]
    public void Poke59468ChoosesTheCharacterSet()
    {
        PetMachine machine = Machine();
        RunToReady(machine);
        machine.Video.Lowercase.Should().BeFalse();

        Type(machine, "POKE 59468,14\r");
        machine.Video.Lowercase.Should().BeTrue();

        Type(machine, "POKE 59468,12\r");
        machine.Video.Lowercase.Should().BeFalse();
    }

    /// <summary>
    ///  A write to video RAM while the beam draws a line shows, in the scanned frame, under the beam on that line
    ///  alone; with snow off, it does not.
    /// </summary>
    /// <param name="snow">Whether snow is shown.</param>
    [TestMethod]
    [DataRow(data: true)]
    [DataRow(data: false)]
    public void VideoRamAccessDuringTheDisplayShowsSnow(bool snow)
    {
        PetMachine machine = Machine();
        RunToReady(machine);
        machine.Video.Snow = snow;

        // Line 100 is the 5th line of row 12; the beam is at column 10.
        int target = PetTiming.BlankingCycles + (100 * PetTiming.CyclesPerLine) + PetTiming.FirstColumnCycle + 10;
        while (machine.Bus.FrameCycle != target) { machine.StepCycle(); }
        ushort address = (ushort)(0x8000 + (12 * 40) + 30);
        byte old = machine.Bus.VideoRam[(12 * 40) + 30];
        machine.Bus.Write(address, value: 0xA0);
        machine.StepCycle();
        machine.Bus.Write(address, old);
        while (machine.Bus.FrameCycle != 0) { machine.StepCycle(); }

        byte[] scanned = new byte[320 * 200 * 4];
        machine.Video.Render(scanned, scanned: true);
        byte[] now = machine.Video.RenderBitmap();

        // The snowed character is a reversed space at column 10: every dot of the line lit.
        Enumerable.Range(80, 8).All(x => scanned[((100 * 320) + x) * 4] != 0).Should().Be(snow);
        Enumerable.Range(80, 8).All(x => now[((100 * 320) + x) * 4] == 0).Should().BeTrue();
        Enumerable.Range(80, 8).All(x => scanned[((101 * 320) + x) * 4] == 0).Should().BeTrue("only that line");
    }

    /// <summary>
    ///  The VIA's shift register, free-running on timer 2, drives CB2 as a square wave, which the sound plays.
    /// </summary>
    [TestMethod]
    public void ShiftRegisterOnCb2MakesATone()
    {
        PetMachine machine = Machine();
        RunToReady(machine);
        RecordingAudioTests sink = new();
        machine.Audio.Sink = sink;

        // ACR $10: shift out free-running at timer 2's rate; the pattern $0F; timer 2 at 100 cycles a bit.
        Type(machine, "POKE 59467,16:POKE 59466,15:POKE 59464,100\r");
        machine.Audio.Sink = null;
        machine.Audio.Sink = sink = new();
        machine.Run(TimeSpan.FromSeconds(0.1));
        machine.Audio.Flush();
        ReadOnlySpan<float> samples = sink.Samples;

        // A bit every second timeout, 2 × 102 cycles: 8 bits make one wave, about 613 Hz, so some 123 crossings in
        // 0.1 s.
        int crossings = 0;
        for (int i = 2; i < samples.Length; i += 2)
        {
            if ((samples[i] > 0) != (samples[i - 2] > 0)) { crossings++; }
        }

        crossings.Should().BeInRange(115, 130);
    }
}
