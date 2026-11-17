// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug;
using Retrocore.Machines.Trs80;
using Retrocore.Media.Trs80;

namespace Retrocore.Tests;

/// <summary>
///  The Model III, 4, 4P and Model II running the SDK's builds of their ROMs, which are byte-identical to the real
///  ones.
/// </summary>
[TestClass]
public class Trs80Model3RomTests
{
    /// <summary>
    ///  The Model III and Model 4 boot without a disk controller to BASIC, through Cass? and Memory Size?, and run a
    ///  statement.
    /// </summary>
    /// <param name="variant">The model.</param>
    [TestMethod]
    [DataRow(Trs80Model3Variant.Model3)]
    [DataRow(Trs80Model3Variant.Model4)]
    public void BootsToBasic(Trs80Model3Variant variant)
    {
        Trs80Model3Machine machine = Model3(variant);
        machine.Run(Trs80Model3Timing.ClockHertz);
        Screen(machine).Should().Contain("Cass");
        Type(machine, "\r");
        Screen(machine).Should().Contain("Memory Size?");
        Type(machine, "\r");
        machine.Run(Trs80Model3Timing.ClockHertz * 2UL);
        Screen(machine).Should().Contain("Radio Shack Model III Basic");
        Type(machine, "PRINT 6*7\r");
        Screen(machine).Should().Contain(" 42 ");

        // No RS-232 board is fitted: its UART's status reads $FF, which the ROM's RS-232 set-up takes as none.
        machine.Bus.In(0xEA).Should().Be(0xFF);
    }

    /// <summary>
    ///  CSAVE records at the speed Cass? chose, H for 1500 baud and L for 500, and CLOAD reads the tape back. Each tape
    ///  is in the usual CAS layout for its speed: the leader ($55 bytes at 1500 baud, zeros at 500), the sync byte
    ///  ($7F or $A5), then the file.
    /// </summary>
    /// <param name="variant">The model.</param>
    /// <param name="speed">The answer to Cass?.</param>
    /// <param name="leader">The tape's first byte.</param>
    [TestMethod]
    [DataRow(Trs80Model3Variant.Model3, "H", 0x55)]
    [DataRow(Trs80Model3Variant.Model3, "L", 0x00)]
    [DataRow(Trs80Model3Variant.Model4, "H", 0x55)]
    public void SavesAndLoadsAtEachSpeed(Trs80Model3Variant variant, string speed, int leader)
    {
        Trs80Model3Machine machine = Model3(variant);
        machine.Run(Trs80Model3Timing.ClockHertz);
        Type(machine, speed + "\r");
        Type(machine, "\r");
        machine.Run(Trs80Model3Timing.ClockHertz * 2UL);
        Type(machine, "10 PRINT \"HI\";6*7\r");

        CassetteImage tape = new();
        machine.Bus.Cassette.Record(tape);
        Type(machine, "CSAVE \"A\"\r");
        RunUntil(machine, () => !machine.Bus.Cassette.MotorOn, seconds: 60);
        machine.Bus.Cassette.Stop();
        tape.Bytes.Should().NotBeEmpty();
        tape.Bytes[0].Should().Be((byte)leader);

        // The leader, 256 bytes at 1500 baud as the ROM writes it, and the sync byte ($7F at 1500 baud, $A5 at 500),
        // then the file: three $D3 and its name.
        byte syncByte = leader == 0x55 ? (byte)0x7F : (byte)0xA5;
        int sync = tape.Bytes.ToList().IndexOf(syncByte);
        if (leader == 0x55) { sync.Should().Be(256); }
        tape.Bytes.Take(sync).Should().AllSatisfy(value => value.Should().Be((byte)leader));
        tape.Bytes.Skip(sync + 1).Take(4).Should().Equal(0xD3, 0xD3, 0xD3, (byte)'A');

        Type(machine, "NEW\r");
        machine.Bus.Cassette.Play(tape);
        Type(machine, "CLOAD \"A\"\r");
        RunUntil(machine, () => !machine.Bus.Cassette.MotorOn, seconds: 60);
        machine.Bus.Cassette.AtEnd.Should().BeTrue("CLOAD read the whole tape");
        machine.Run(Trs80Model3Timing.ClockHertz);
        Type(machine, "RUN\r");
        Screen(machine).Should().Contain("HI 42");
    }

    /// <summary>
    ///  A 1500 baud CAS image written by hand in the usual layout loads: 256 leader bytes, the sync byte, then the file,
    ///  10 PRINT "HI";6*7 named A.
    /// </summary>
    [TestMethod]
    public void LoadsAHighSpeedCasImage()
    {
        byte[] file =
        [
            0xD3, 0xD3, 0xD3, (byte)'A',
            0xF8, 0x43, 0x0A, 0x00, 0xB2, 0x20, 0x22, 0x48, 0x49, 0x22, 0x3B, 0x36, 0xCF, 0x37, 0x00,
            0x00, 0x00
        ];

        CassetteImage tape = new([.. Enumerable.Repeat((byte)0x55, 256), 0x7F, .. file]);
        Trs80Model3Machine machine = Model3(Trs80Model3Variant.Model3);
        machine.Run(Trs80Model3Timing.ClockHertz);
        Type(machine, "H\r");
        Type(machine, "\r");
        machine.Run(Trs80Model3Timing.ClockHertz * 2UL);
        machine.Bus.Cassette.Play(tape);
        Type(machine, "CLOAD \"A\"\r");
        RunUntil(machine, () => !machine.Bus.Cassette.MotorOn, seconds: 30);
        machine.Run(Trs80Model3Timing.ClockHertz);
        Type(machine, "RUN\r");
        Screen(machine).Should().Contain("HI 42");
    }

    /// <summary>
    ///  Two programs saved one after the other at 1500 baud share a tape, each with its own leader and sync byte, and
    ///  CLOAD finds the second by its name, past the first.
    /// </summary>
    [TestMethod]
    public void LoadsTheSecondProgramOnAHighSpeedTape()
    {
        Trs80Model3Machine machine = Model3(Trs80Model3Variant.Model3);
        machine.Run(Trs80Model3Timing.ClockHertz);
        Type(machine, "H\r");
        Type(machine, "\r");
        machine.Run(Trs80Model3Timing.ClockHertz * 2UL);

        CassetteImage tape = new();
        machine.Bus.Cassette.Record(tape);
        Type(machine, "10 PRINT \"FIRST\"\r");
        Type(machine, "CSAVE \"A\"\r");
        RunUntil(machine, () => !machine.Bus.Cassette.MotorOn, seconds: 60);
        Type(machine, "NEW\r");
        Type(machine, "10 PRINT \"HI\";6*7\r");
        Type(machine, "CSAVE \"B\"\r");
        RunUntil(machine, () => !machine.Bus.Cassette.MotorOn, seconds: 60);
        machine.Bus.Cassette.Stop();

        // The second recording's leader and sync byte follow the first's file.
        List<byte> bytes = [.. tape.Bytes];
        int second = bytes.FindIndex(257, value => value == 0x55);
        second.Should().BePositive();
        bytes.Skip(second).Take(256).Should().AllSatisfy(value => value.Should().Be(0x55));
        bytes[second + 256].Should().Be(0x7F);

        Type(machine, "NEW\r");
        machine.Bus.Cassette.Play(tape);
        Type(machine, "CLOAD \"B\"\r");
        RunUntil(machine, () => machine.Bus.Cassette.AtEnd, seconds: 60);
        machine.Run(Trs80Model3Timing.ClockHertz);
        Type(machine, "RUN\r");
        Screen(machine).Should().Contain("HI 42");
    }

    /// <summary>
    ///  The Model III with Level I BASIC boots to READY, runs a statement, saves and loads a program on tape at 250
    ///  baud, the leader zeros and the sync byte $A5, and the reset button stops a running program every time.
    /// </summary>
    [TestMethod]
    public void Level1BootsAndUsesTheTape()
    {
        string roms = Path.Join(AppContext.BaseDirectory, "Inputs", "Trs80");
        byte[] system = Trs80SdkModules.AssembleLevel1(Path.Join(roms, "Level1.asm"), model: 3).Sections[0].Bytes.ToArray();
        byte[] characters = Trs80SdkModules
            .AssembleModel3CharacterGenerator(Path.Join(roms, "Model3CharacterGenerator.asm"), model4P: false)
            .Sections[0].Bytes.ToArray();

        Trs80Model3Machine machine = new(
            new Trs80Model3Configuration { Rom = Trs80Rom.Level1, DiskController = false },
            new Trs80Model3Roms(system, characters));

        machine.Run(Trs80Model3Timing.ClockHertz);
        Screen(machine).Should().Contain("READY");
        Type(machine, "PRINT 6*7\r");
        Screen(machine).Should().Contain("42");
        Type(machine, "10 PRINT \"HI\";6*7\r");

        CassetteImage tape = new();
        machine.Bus.Cassette.Record(tape);
        Type(machine, "CSAVE\r");
        RunUntil(machine, () => !machine.Bus.Cassette.MotorOn, seconds: 60);
        machine.Bus.Cassette.Stop();
        int sync = tape.Bytes.ToList().IndexOf(0xA5);
        sync.Should().BePositive();
        tape.Bytes.Take(sync).Should().AllSatisfy(value => value.Should().Be(0));

        Type(machine, "NEW\r");
        machine.Run(Trs80Model3Timing.ClockHertz);
        machine.Bus.Cassette.Play(tape);
        Type(machine, "CLOAD\r");
        RunUntil(machine, () => !machine.Bus.Cassette.MotorOn, seconds: 60);
        machine.Run(Trs80Model3Timing.ClockHertz);
        Type(machine, "RUN\r");
        Screen(machine).Should().Contain("HI 42");

        // The reset button stops a running program each time it is pressed, though Level I's NMI handler does not
        // read port $E4.
        Type(machine, "NEW\r");
        Type(machine, "10 GOTO 10\r");
        for (int press = 1; press <= 2; press++)
        {
            Type(machine, "RUN\r");
            Screen(machine).Should().Contain("RUN");
            machine.Reset();
            machine.Run(Trs80Model3Timing.ClockHertz);

            // The handler clears the screen and BASIC prints READY afresh.
            Screen(machine).Should().NotContain("RUN", $"press {press} reached the NMI handler");
            Screen(machine).Should().Contain("READY");
        }
    }

    /// <summary>
    ///  Each DOS boots from its disk image in drive 0, takes the date and lists its directory. The images are in
    ///  <c>trs80-disks</c> under <see cref="ExternalTestData.Root"/>; the test is inconclusive without one.
    /// </summary>
    /// <param name="variant">The model.</param>
    /// <param name="image">The image's file name.</param>
    /// <param name="ready">The DOS's prompt.</param>
    /// <param name="listed">A file its directory lists.</param>
    [TestMethod]
    [DataRow(Trs80Model3Variant.Model3, "TRSDOS13.dmk", "TRSDOS Ready", "MEMTEST/CMD")]
    [DataRow(Trs80Model3Variant.Model3, "LDOS513.dsk", "LDOS Ready", "ALEDIT/CMD")]
    [DataRow(Trs80Model3Variant.Model4, "TRSDOS60.dmk", "TRSDOS Ready", "REPAIR/CMD")]
    [DataRow(Trs80Model3Variant.Model4, "TRSDOS62.imd", "TRSDOS Ready", "REPAIR/CMD")]
    [DataRow(Trs80Model3Variant.Model4, "LSDOS63J.dsk", "LS-DOS Ready", "REPAIR/CMD")]
    [DataRow(Trs80Model3Variant.Model4P, "LSDOS63J.dsk", "LS-DOS Ready", "REPAIR/CMD")]
    public void BootsItsDos(Trs80Model3Variant variant, string image, string ready, string listed)
    {
        string path = Path.Join(ExternalTestData.Root, "trs80-disks", image);
        if (!File.Exists(path)) { Assert.Inconclusive($"{path} is missing."); }

        Trs80Model3Machine machine = Model3(variant, diskController: true);
        (FloppyDisk disk, string format) = Trs80DiskImage.Read(File.ReadAllBytes(path), Path.GetExtension(path));
        machine.Drives[0].Insert(disk, image, format);

        ShowsWithin(machine, "Date", seconds: 20);
        Type(machine, "11/14/86\r");
        Type(machine, "\r");
        ShowsWithin(machine, ready, seconds: 20);
        Type(machine, "DIR\r");
        ShowsWithin(machine, listed, seconds: 20);
    }

    /// <summary>
    ///  The 4P's boot ROM, with no disk in the drive, says so in English, German and French.
    /// </summary>
    [TestMethod]
    public void Model4PAsksForADisk()
    {
        Trs80Model3Machine machine = Model3(Trs80Model3Variant.Model4P);
        machine.Run(Trs80Model3Timing.ClockHertz * 8UL);
        Screen(machine).Should().Contain("The Floppy Disk Drive Is Not Ready");
    }

    /// <summary>
    ///  Each Model II boot ROM passes its tests, finds no hard disk and asks for a diskette. Versions 2 and 3 take
    ///  the hard disk board's port <c>$C2</c> reading zero as no board, as it does with none fitted.
    /// </summary>
    /// <param name="version">The boot ROM's version.</param>
    [TestMethod]
    [DataRow(1)]
    [DataRow(2)]
    [DataRow(3)]
    [DataRow(5)]
    public void Model2AsksForADiskette(int version)
    {
        string roms = Path.Join(AppContext.BaseDirectory, "Inputs", "Trs80");
        byte[] boot = Trs80SdkModules.AssembleModel2Boot(Path.Join(roms, "Model2Boot.asm"), version).Sections[0].Bytes.ToArray();
        byte[] characters = Trs80SdkModules.AssembleModel2CharacterGenerator(Path.Join(roms, "Model2CharacterGenerator.asm"))
            .Sections[0].Bytes.ToArray();

        Trs80Model2Machine machine = new(new Trs80Model2Configuration(), new Trs80Model2Roms(boot, characters));
        machine.Run(Trs80Model2Timing.ClockHertz * 3UL);
        string screen = new([.. Enumerable.Range(0, 80 * 24).Select(index => (char)(machine.Bus.Video.Read(index) & 0x7F))]);
        screen.Should().Contain("INSERT DISKETTE", $"version {version} boots from the floppy");
    }

    private static Trs80Model3Machine Model3(Trs80Model3Variant variant, bool? diskController = null)
    {
        string roms = Path.Join(AppContext.BaseDirectory, "Inputs", "Trs80");
        bool model4P = variant == Trs80Model3Variant.Model4P;
        byte[] system = (variant switch
        {
            Trs80Model3Variant.Model4P => Trs80SdkModules.AssembleModel4PBoot(Path.Join(roms, "Model4PBoot.asm")),
            Trs80Model3Variant.Model4 => Trs80SdkModules.AssembleModel3(Path.Join(roms, "Model3.asm"), 4),
            _ => Trs80SdkModules.AssembleModel3(Path.Join(roms, "Model3.asm"), 3)
        }).Sections[0].Bytes.ToArray();

        byte[] characters = Trs80SdkModules
            .AssembleModel3CharacterGenerator(Path.Join(roms, "Model3CharacterGenerator.asm"), model4P)
            .Sections[0].Bytes.ToArray();

        Trs80Model3Configuration configuration = new()
        {
            Variant = variant,
            RamKilobytes = Trs80Model3Configuration.DefaultRam(variant),
            DiskController = diskController ?? model4P
        };

        return new(configuration, new Trs80Model3Roms(system, characters));
    }

    // Types the keys, waits until the keyboard has pressed them all, then lets the ROM act on the last.
    private static void Type(Trs80Model3Machine machine, string text)
    {
        foreach (char character in text) { machine.Bus.Keyboard.Type((byte)character).Should().BeTrue(); }
        for (int ticks = 0; machine.Bus.Keyboard.IsTyping && ticks < 3000; ticks++)
        {
            machine.Run(Trs80Model3Timing.CyclesPerTick);
        }

        machine.Run(Trs80Model3Timing.ClockHertz);
    }

    // Runs, a tick at a time, until a condition holds, for at most some seconds of the machine's time.
    private static void RunUntil(Trs80Model3Machine machine, Func<bool> done, int seconds)
    {
        machine.Run(Trs80Model3Timing.CyclesPerTick * 3);
        for (int ticks = 0; !done() && ticks < seconds * 30; ticks++) { machine.Run(Trs80Model3Timing.CyclesPerTick); }
        done().Should().BeTrue($"it finished within {seconds} seconds");
    }

    // Runs a second at a time until the screen shows the text, for at most some seconds of the machine's time.
    private static void ShowsWithin(Trs80Model3Machine machine, string text, int seconds)
    {
        for (int second = 0; second < seconds && !Text(machine).Contains(text, StringComparison.Ordinal); second++)
        {
            machine.Run(Trs80Model3Timing.ClockHertz);
        }

        Text(machine).Should().Contain(text, $"it shows within {seconds} seconds");
    }

    // The screen as shown, 64x16 or 80x24, a line to a row.
    private static string Text(Trs80Model3Machine machine)
    {
        Trs80Model3Video video = machine.Bus.Video;
        int columns = video.Eighty ? 80 : 64;
        return string.Join('\n', Enumerable.Range(0, video.Rows)
            .Select(row => new string([.. Enumerable.Range(0, columns).Select(column => (char)(video.Displayed(row, column) & 0x7F))])));
    }

    private static string Screen(Trs80Model3Machine machine) =>
        new([.. Enumerable.Range(0, 1024).Select(index => (char)machine.Bus.Video.Read(index))]);
}
