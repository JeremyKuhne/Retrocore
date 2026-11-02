// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Trs80;

namespace Retrocore.Tests;

/// <summary>
///  The Model I boots Tandy's ROMs: externally supplied dumps that MAME's hashes identify, never committed.
/// </summary>
/// <remarks>
///  <para>
///   The dumps are read from <c>RETROCORE_TRS80_ROMS</c>, or <c>%USERPROFILE%\Retrocore\trs80-roms\extract</c>:
///   <c>rom-a.z1</c>, <c>rom-b.z2</c> and <c>rom-c.z3</c> (Level II 1.2), the same with <c>_alt</c> (1.3),
///   <c>level1.rom</c> and <c>mcm6670p.z29</c>.
///  </para>
/// </remarks>
[TestClass]
public class Trs80RomTests
{
    /// <summary>
    ///  Level II asks the memory size, reaches READY, and runs a line of BASIC.
    /// </summary>
    [TestMethod]
    public void LevelTwoBootsToReady()
    {
        byte[] level2 = [.. Dump("rom-a.z1"), .. Dump("rom-b.z2"), .. Dump("rom-c.z3")];
        Trs80Machine machine = new(new() { DiskController = false }, new(level2, Dump("mcm6670p.z29")));
        Run(machine, seconds: 1);
        Screen(machine).Should().Contain("MEMORY SIZE?");

        // An empty answer sizes all 48K of RAM, about two seconds.
        Type(machine, "\r");
        Run(machine, seconds: 3);
        Screen(machine).Should().Contain("RADIO SHACK LEVEL II BASIC").And.Contain("READY");

        Type(machine, "PRINT 2+3*4\r");
        Run(machine, seconds: 1);
        Screen(machine).Should().Contain(" 14 ");
    }

    /// <summary>
    ///  Level II 1.3 debounces keys and pauses after each one, and typing still reaches it intact, doubled
    ///  letters included.
    /// </summary>
    [TestMethod]
    public void LevelTwoPointThreeTakesTypedLines()
    {
        byte[] level2 = [.. Dump("rom-a_alt.z1"), .. Dump("rom-b_alt.z2"), .. Dump("rom-c_alt.z3")];
        Trs80Machine machine = new(new() { DiskController = false }, new(level2, Dump("mcm6670p.z29")));
        Run(machine, seconds: 1);
        Screen(machine).Should().Contain("MEM SIZE?");
        Type(machine, "\r");
        Run(machine, seconds: 3);
        Screen(machine).Should().Contain("R/S L2 BASIC");

        Type(machine, "PRINT \"HELLO\";1+2\r");
        Run(machine, seconds: 1);
        Screen(machine).Should().Contain("HELLO 3");
    }

    /// <summary>
    ///  Level II saves a program to tape with CSAVE, and CLOAD reads it back after NEW.
    /// </summary>
    [TestMethod]
    public void LevelTwoSavesAndLoadsCassettes()
    {
        byte[] level2 = [.. Dump("rom-a.z1"), .. Dump("rom-b.z2"), .. Dump("rom-c.z3")];
        Trs80Machine machine = new(new() { DiskController = false }, new(level2, Dump("mcm6670p.z29")));
        Run(machine, seconds: 1);
        Type(machine, "\r");
        Run(machine, seconds: 3);
        Type(machine, "10 PRINT \"SAVED\";7*6\r");

        Media.Trs80.CassetteImage tape = new();
        machine.Bus.Cassette.Record(tape);
        Type(machine, "CSAVE \"A\"\r");
        RunUntil(machine, () => machine.Bus.Cassette.MotorOn, seconds: 5);
        RunUntil(machine, () => !machine.Bus.Cassette.MotorOn, seconds: 30);
        machine.Bus.Cassette.Stop();
        tape.Bytes.Count.Should().BeGreaterThan(256);
        tape.Bytes.Should().Contain(0xA5, "the sync byte after the leader");

        Type(machine, "NEW\r");
        Run(machine, seconds: 1);
        machine.Bus.Cassette.Play(tape);
        Type(machine, "CLOAD \"A\"\r");
        RunUntil(machine, () => machine.Bus.Cassette.MotorOn, seconds: 5);
        RunUntil(machine, () => !machine.Bus.Cassette.MotorOn, seconds: 30);
        Type(machine, "CLS\r");
        Run(machine, seconds: 0.5);
        Type(machine, "RUN\r");
        Run(machine, seconds: 1);
        Screen(machine).Should().Contain("SAVED 42");
    }

    /// <summary>
    ///  Level I reaches its READY prompt in 4K.
    /// </summary>
    [TestMethod]
    public void LevelOneBootsToReady()
    {
        Trs80Configuration configuration = new()
        {
            Rom = Trs80Rom.Level1,
            RamKilobytes = 4,
            ExpansionInterface = false
        };

        Trs80Machine machine = new(configuration, new(Dump("level1.rom"), Dump("mcm6670p.z29")));
        Run(machine, seconds: 2);
        Screen(machine).Should().Contain("READY");
    }

    /// <summary>
    ///  NEWDOS/80 boots from drive 0 through the Percom doubler it probes for, and lists the drive.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   The image is <c>%USERPROFILE%\Retrocore\trs80-disks\NEWDOS_80sssd_jv1.DSK</c>. A bare <c>DIR</c>
    ///   answers DEVICE NOT AVAILABLE on MAME too, so the test names the drive.
    ///  </para>
    /// </remarks>
    [TestMethod]
    public void NewDosBootsAndListsTheDisk()
    {
        string image = Path.Join(
            ExternalTestData.Root,
            "trs80-disks",
            "NEWDOS_80sssd_jv1.DSK");

        if (!File.Exists(image)) { Assert.Inconclusive("The NEWDOS/80 image is missing."); }
        byte[] level2 = [.. Dump("rom-a.z1"), .. Dump("rom-b.z2"), .. Dump("rom-c.z3")];
        Trs80Machine machine = new(new() { Doubler = Trs80Doubler.Percom }, new(level2, Dump("mcm6670p.z29")));
        machine.Bus.Disks.Insert(0, Media.Trs80.Jv1Format.Read(File.ReadAllBytes(image)));
        Run(machine, seconds: 8);
        Screen(machine).Should().Contain("NEWDOS/80 READY");

        Type(machine, "DIR 0\r");
        Run(machine, seconds: 5);
        Screen(machine).Should().Contain("80 TRKS").And.Contain("SUPERZAP/CMD");
    }

    /// <summary>
    ///  NEWDOS/80 also boots from a JV3 image: the JV1 image written as JV3 and read back.
    /// </summary>
    [TestMethod]
    public void NewDosBootsFromJv3()
    {
        string image = Path.Join(
            ExternalTestData.Root,
            "trs80-disks",
            "NEWDOS_80sssd_jv1.DSK");

        if (!File.Exists(image)) { Assert.Inconclusive("The NEWDOS/80 image is missing."); }
        byte[] jv3 = Media.Trs80.Jv3Format.Write(Media.Trs80.Jv1Format.Read(File.ReadAllBytes(image)));
        byte[] level2 = [.. Dump("rom-a.z1"), .. Dump("rom-b.z2"), .. Dump("rom-c.z3")];
        Trs80Machine machine = new(new() { Doubler = Trs80Doubler.Percom }, new(level2, Dump("mcm6670p.z29")));
        machine.Bus.Disks.Insert(0, Media.Trs80.Jv3Format.Read(jv3));
        Run(machine, seconds: 8);
        Type(machine, "DIR 0\r");
        Run(machine, seconds: 5);
        Screen(machine).Should().Contain("NEWDOS/80 READY").And.Contain("SUPERZAP/CMD");
    }

    private static byte[] Dump(string name)
    {
        string directory = Environment.GetEnvironmentVariable("RETROCORE_TRS80_ROMS")
            ?? Path.Join(ExternalTestData.Root, "trs80-roms", "extract");

        string path = Path.Join(directory, name);
        if (!File.Exists(path))
        {
            Assert.Inconclusive($"Set RETROCORE_TRS80_ROMS to the Model I ROM dumps; {name} is missing.");
        }

        return File.ReadAllBytes(path);
    }

    private static void Run(Trs80Machine machine, double seconds) => machine.Run((ulong)(seconds * Trs80Timing.ClockHertz));

    private static void RunUntil(Trs80Machine machine, Func<bool> condition, double seconds)
    {
        for (int step = 0; step < seconds * 100 && !condition(); step++) { machine.Run(Trs80Timing.ClockHertz / 100); }
        condition().Should().BeTrue($"within {seconds} seconds");
    }

    // Types each character, running until the keyboard has pressed and released it.
    private static void Type(Trs80Machine machine, string text)
    {
        foreach (char character in text) { machine.Bus.Keyboard.Type((byte)character); }
        while (machine.Bus.Keyboard.IsTyping) { machine.Run(1000); }
    }

    private static string Screen(Trs80Machine machine)
    {
        char[] screen = new char[Trs80Video.Columns * Trs80Video.Rows];
        for (int index = 0; index < screen.Length; index++)
        {
            byte code = machine.Bus.Video.Read(index);
            screen[index] = code is >= 0x20 and < 0x80 ? (char)code : ' ';
        }

        return new(screen);
    }
}
