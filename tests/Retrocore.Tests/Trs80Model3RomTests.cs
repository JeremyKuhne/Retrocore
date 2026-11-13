// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug;
using Retrocore.Machines.Trs80;

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
    ///  The Model II's newest boot ROM passes its tests, finds no hard disk and asks for a diskette.
    /// </summary>
    [TestMethod]
    public void Model2AsksForADiskette()
    {
        string roms = Path.Join(AppContext.BaseDirectory, "Inputs", "Trs80");
        byte[] boot = Trs80SdkModules.AssembleModel2Boot(Path.Join(roms, "Model2Boot.asm"), 5).Sections[0].Bytes.ToArray();
        byte[] characters = Trs80SdkModules.AssembleModel2CharacterGenerator(Path.Join(roms, "Model2CharacterGenerator.asm"))
            .Sections[0].Bytes.ToArray();

        Trs80Model2Machine machine = new(new Trs80Model2Configuration(), new Trs80Model2Roms(boot, characters));
        machine.Run(Trs80Model2Timing.ClockHertz * 3UL);
        string screen = new([.. Enumerable.Range(0, 80 * 24).Select(index => (char)(machine.Bus.Video.Read(index) & 0x7F))]);
        screen.Should().Contain("INSERT DISKETTE");
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

    private static string Screen(Trs80Model3Machine machine) =>
        new([.. Enumerable.Range(0, 1024).Select(index => (char)machine.Bus.Video.Read(index))]);
}
