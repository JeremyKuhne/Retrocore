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

    private static Trs80Model3Machine Model3(Trs80Model3Variant variant)
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
            DiskController = model4P
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

    private static string Screen(Trs80Model3Machine machine) =>
        new([.. Enumerable.Range(0, 1024).Select(index => (char)machine.Bus.Video.Read(index))]);
}
