// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Coco;
using Retrocore.Media.Trs80;

namespace Retrocore.Tests;

/// <summary>
///  The Color Computer's disk controller cartridge running Disk Extended Color BASIC.
/// </summary>
[TestClass]
public class CocoDiskTests
{
    /// <summary>
    ///  Disk BASIC formats a blank disk, saves a program, lists the directory and loads the program back.
    /// </summary>
    /// <param name="model">The model.</param>
    [TestMethod]
    [DataRow(CocoModel.Coco2)]
    [DataRow(CocoModel.Coco3)]
    public void FormatsSavesAndLoads(CocoModel model)
    {
        CocoMachine machine = Create(model);
        CocoMachineTests.Screen(machine).Should().Contain("DISK EXTENDED COLOR BASIC");

        FloppyDisk disk = new();
        machine.Bus.DiskController?.Drives[0].Insert(disk, "blank", "dsk");
        CocoMachineTests.Type(machine, "dskini0\r");
        double seconds = WaitForOk(machine, limit: 120);
        Console.WriteLine($"DSKINI took {seconds:F1} s");
        CocoMachineTests.Screen(machine).Should().NotContain("ERROR");
        disk.Cylinders.Should().Be(JvcFormat.Tracks);

        // DSKINI leaves what JvcFormat.Formatted makes.
        JvcFormat.Write(disk).Should().Equal(JvcFormat.Write(JvcFormat.Formatted()));

        CocoMachineTests.Type(machine, "10 print \"saved\";6*7\rsave \"hello\"\r");
        WaitForOk(machine, limit: 10);
        CocoMachineTests.Type(machine, "new\rdir\r");
        WaitForOk(machine, limit: 10);
        CocoMachineTests.Screen(machine).Should().Contain("HELLO").And.Contain("BAS");

        CocoMachineTests.Type(machine, "load \"hello\"\r");
        WaitForOk(machine, limit: 10);
        CocoMachineTests.Type(machine, "run\r");
        string screen = CocoMachineTests.Screen(machine);
        Console.WriteLine(screen);
        screen.Should().Contain("SAVED 42");

        // The disk reads back as a JVC image Disk BASIC's own format matches.
        byte[] image = JvcFormat.Write(disk);
        image.Should().HaveCount(JvcFormat.Tracks * JvcFormat.SectorsPerTrack * JvcFormat.SectorSize);
    }

    /// <summary>
    ///  A disk formatted by <see cref="JvcFormat.Formatted"/> reads as an empty disk with all its space free.
    /// </summary>
    [TestMethod]
    public void FormattedDiskIsEmpty()
    {
        CocoMachine machine = Create(CocoModel.Coco2);
        machine.Bus.DiskController?.Drives[0].Insert(JvcFormat.Formatted(), "formatted", "dsk");
        CocoMachineTests.Type(machine, "print free(0)\r");
        WaitForOk(machine, limit: 10);
        CocoMachineTests.Screen(machine).Should().Contain(" 68 ");
    }

    /// <summary>
    ///  JVC images keep their sectors through a write and read.
    /// </summary>
    [TestMethod]
    public void JvcRoundTrips()
    {
        byte[] image = new byte[JvcFormat.Tracks * JvcFormat.SectorsPerTrack * JvcFormat.SectorSize];
        new Random(7).NextBytes(image);
        JvcFormat.Write(JvcFormat.Read(image)).Should().Equal(image);

        // A header of two sides doubles the tracks' sectors.
        byte[] sided = [JvcFormat.SectorsPerTrack, 2, .. image, .. image];
        FloppyDisk disk = JvcFormat.Read(sided);
        disk.Sides.Should().Be(2);
        disk.Track(0, 1)[0].Data.Should().Equal(image[(18 * 256)..(19 * 256)]);
        JvcFormat.Write(disk).Should().Equal(sided);
    }

    /// <summary>
    ///  A disk with tracks of more sectors than a JVC track holds is not written, rather than losing the rest.
    /// </summary>
    [TestMethod]
    public void JvcRefusesTracksItCannotKeep()
    {
        byte[] image = [19, .. new byte[19 * JvcFormat.SectorSize]];
        FloppyDisk disk = JvcFormat.Read(image);
        disk.Track(0, 0).Should().HaveCount(19);
        Action write = () => JvcFormat.Write(disk);
        write.Should().Throw<InvalidOperationException>().WithMessage("*19 sectors*");
    }

    /// <summary>
    ///  Runs until the screen's last line with text is OK.
    /// </summary>
    /// <param name="machine">The machine.</param>
    /// <param name="limit">The most seconds to run.</param>
    /// <returns>The seconds it took.</returns>
    internal static double WaitForOk(CocoMachine machine, double limit)
    {
        ulong start = machine.Processor.CycleCount;
        ulong end = start + (ulong)(limit * CocoTiming.ClockHertz);
        while (machine.Processor.CycleCount < end)
        {
            string last = machine.Bus.TextRows().Select(row => row.Trim()).LastOrDefault(row => row.Length > 0) ?? "";
            if (last == "OK") { return (machine.Processor.CycleCount - start) / CocoTiming.ClockHertz; }
            machine.Run((ulong)(CocoTiming.ClockHertz / 10));
        }

        throw new AssertFailedException($"BASIC did not finish in {limit} s:\n{CocoMachineTests.Screen(machine)}");
    }

    private static CocoMachine Create(CocoModel model)
    {
        int kilobytes = model == CocoModel.Coco3 ? 128 : 64;
        CocoMachine machine = new(
            new() { Model = model, RamKilobytes = kilobytes },
            CocoTestRoms.Load(model),
            new CocoDiskController(CocoTestRoms.DiskBasic()));

        machine.Run(3 * (ulong)CocoTiming.ClockHertz);
        return machine;
    }
}
