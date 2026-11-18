// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.IO.Compression;
using Retrocore.Machines.Commodore;
using Retrocore.Media.Commodore;

namespace Retrocore.Tests;

/// <summary>
///  The 4040 dual drive on the PET's IEEE-488 bus, running its own DOS and controller ROMs. It needs MAME's
///  <c>c4040</c> set with the PET sets, and the <c>pet_flop</c> software list's <c>2040demo</c> in
///  <c>%USERPROFILE%\Retrocore\pet-media</c>.
/// </summary>
[TestClass]
public class PetDiskTests
{
    private static string DemoZip => Path.Join(
        ExternalTestData.Root, "pet-media", "extract", "pet_flop", "pet_flop", "2040demo.zip");

    /// <summary>
    ///  Makes a PET, BASIC 2 unless asked, with one 4040 as device 8, or marks the test inconclusive without the
    ///  dumps.
    /// </summary>
    /// <param name="ramKilobytes">The PET's RAM.</param>
    /// <param name="model">The model.</param>
    /// <returns>The machine.</returns>
    internal static PetMachine Machine(int ramKilobytes = 32, PetModel model = PetModel.Pet2001Basic2)
    {
        string drive = Path.Join(PetMachineTests.RomRoot, "c4040");
        string pet = PetMachineTests.RomDirectory(model);
        if (!File.Exists(Path.Join(drive, "901468-14.uj1"))
            || !File.Exists(Path.Join(pet, PetMachineTests.KernalChip(model))))
        {
            Assert.Inconclusive("Set RETROCORE_PET_ROMS to a folder with MAME's PET sets and c4040 unzipped.");
        }

        return new(
            PetRoms.LoadFromDirectory(pet, model),
            model,
            ramKilobytes,
            Cbm4040Roms.LoadFromDirectory(drive));
    }

    /// <summary>
    ///  Reads the 2040 demo disk's D64 image, or marks the test inconclusive without it.
    /// </summary>
    /// <returns>The image.</returns>
    internal static byte[] DemoImage()
    {
        if (!File.Exists(DemoZip)) { Assert.Inconclusive("The pet_flop software list's 2040demo.zip is missing."); }
        using ZipArchive zip = ZipFile.OpenRead(DemoZip);
        using Stream stream = zip.GetEntry("2040-demo.d64")?.Open() ?? throw new InvalidDataException("No D64.");
        using MemoryStream memory = new();
        stream.CopyTo(memory);
        return memory.ToArray();
    }

    /// <summary>
    ///  Types a command and runs until <c>READY.</c> comes back, for up to a limit.
    /// </summary>
    /// <param name="machine">The machine.</param>
    /// <param name="command">The command, without its RETURN.</param>
    /// <param name="seconds">The most emulated seconds to wait.</param>
    /// <returns>The screen.</returns>
    internal static string[] Command(PetMachine machine, string command, int seconds = 60)
    {
        foreach (char c in command + "\r")
        {
            machine.Keyboard.Type((byte)c).Should().BeTrue($"the PET has a key for {c}");
        }

        while (machine.Keyboard.IsTyping) { machine.Run(TimeSpan.FromSeconds(0.05)); }

        // A command longer than a row wraps, so the echo's last row holds only the command's last 40 or fewer.
        string tail = command[((command.Length - 1) / 40 * 40)..];
        for (int tenth = 0; tenth < seconds * 10; tenth++)
        {
            machine.Run(TimeSpan.FromSeconds(0.1));
            string[] screen = machine.ReadTextScreen();
            int line = Array.FindLastIndex(screen, text => text.TrimEnd().EndsWith(tail, StringComparison.Ordinal));
            if (line >= 0 && screen.Skip(line + 1).Any(text => text.StartsWith("READY.", StringComparison.Ordinal)))
            {
                return screen;
            }
        }

        return machine.ReadTextScreen();
    }

    /// <summary>
    ///  <c>LOAD "$0",8</c> reads the demo disk's directory, which LIST shows.
    /// </summary>
    [TestMethod]
    public void DirectoryLists()
    {
        PetMachine machine = Machine();
        Cbm4040 unit = machine.Disks[0];
        unit.Drive0.Insert(D64Format.Read(DemoImage()), "2040-demo", "D64");
        PetMachineTests.RunToReady(machine);

        string[] screen = Command(machine, "LOAD\"$0\",8");
        screen.Should().Contain(line => line.TrimEnd() == "LOADING", string.Join('\n', screen));
        screen = Command(machine, "LIST");
        string text = string.Join('\n', screen);
        screen.Should().Contain(line => line.TrimEnd() == " 27   \"DUM 3.4\"          PRG", text);
        screen.Should().Contain(line => line.TrimEnd() == " 11   \"PERFORMANCE TEST\" PRG", text);
        screen.Should().Contain(line => line.TrimEnd() == " 395 BLOCKS FREE.", text);
    }

    /// <summary>
    ///  On a blank disk, the N command formats it; a program saves, loads back and runs, and the S, R and V
    ///  commands scratch, rename and validate, each answering on the command channel.
    /// </summary>
    [TestMethod]
    public void FormatSaveLoadAndCommands()
    {
        PetMachine machine = Machine();
        CommodoreDisk disk = CommodoreDisk.Blank();
        machine.Disks[0].Drive0.Insert(disk, "blank", "D64", changed: true);
        PetMachineTests.RunToReady(machine);

        DiskCommand(machine, "N0:RETROCORE,RC", seconds: 120).Should().Be(" 0 OK 0  0");

        Command(machine, "NEW");
        Command(machine, "10 PRINT\"SAVED\";6*7");
        Command(machine, "SAVE\"0:FIRST\",8");
        Command(machine, "SAVE\"0:SECOND\",8");

        Command(machine, "NEW");
        string[] screen = Command(machine, "LOAD\"0:FIRST\",8");
        screen.Should().Contain(line => line.TrimEnd() == "LOADING", string.Join('\n', screen));
        screen = Command(machine, "RUN");
        screen.Should().Contain(line => line.TrimEnd() == "SAVED 42", string.Join('\n', screen));

        DiskCommand(machine, "R0:THIRD=SECOND").Should().Be(" 0 OK 0  0");
        DiskCommand(machine, "S0:FIRST").Should().Be(" 1 FILES SCRATCHED 1  0");
        DiskCommand(machine, "V0", seconds: 120).Should().Be(" 0 OK 0  0");

        Command(machine, "NEW");
        Command(machine, "LOAD\"$0\",8");
        screen = Command(machine, "LIST");
        string text = string.Join('\n', screen);
        screen.Should().Contain(line => line.Contains("\"RETROCORE       \" RC", StringComparison.Ordinal), text);
        screen.Should().Contain(line => line.TrimEnd() == " 1    \"THIRD\"            PRG", text);
        screen.Should().NotContain(line => line.Contains("FIRST", StringComparison.Ordinal), text);

        // The image written back holds what the DOS wrote, and a G64 holds it as well.
        (byte[] image, IReadOnlyList<string> unreadable) = D64Format.Write(disk);
        unreadable.Should().BeEmpty();
        image[0x165A2..0x165A4].Should().Equal((byte)'R', (byte)'C');
        (byte[] fromG64, IReadOnlyList<string> lost) = D64Format.Write(G64Format.Read(G64Format.Write(disk)));
        lost.Should().BeEmpty();
        fromG64.Should().Equal(image);
    }

    /// <summary>
    ///  With the disk's notch covered, SAVE fails with the DOS's WRITE PROTECT ON, and the disk is unchanged.
    /// </summary>
    [TestMethod]
    public void WriteProtectRefusesSave()
    {
        PetMachine machine = Machine();
        CommodoreDisk disk = D64Format.Read(DemoImage());
        machine.Disks[0].Drive0.Insert(disk, "2040-demo", "D64");
        machine.Disks[0].Drive0.SetWriteProtected(writeProtected: true);
        long version = disk.Version;
        PetMachineTests.RunToReady(machine);

        Command(machine, "10 PRINT 1");
        Command(machine, "SAVE\"0:PROTECTED\",8");
        DiskCommand(machine, "").Should().StartWith(" 26 WRITE PROTECT ON ");
        disk.Version.Should().Be(version);
    }

    /// <summary>
    ///  Sends a command on the command channel and reads its answer: runs a program that opens the channel with
    ///  the command and inputs the error number, message, track and sector, which waits until the drive is done.
    ///  The program replaces the one in memory.
    /// </summary>
    /// <param name="machine">The machine.</param>
    /// <param name="command">The command, without quotes; empty to read the channel alone.</param>
    /// <param name="seconds">The most emulated seconds to wait.</param>
    /// <returns>What the program prints, as <c>" 0 OK 0  0"</c>.</returns>
    internal static string DiskCommand(PetMachine machine, string command, int seconds = 60)
    {
        Command(machine, "NEW");
        string open = command.Length == 0 ? "OPEN15,8,15" : $"OPEN15,8,15,\"{command}\"";
        Command(machine, $"1 {open}:INPUT#15,E,E$,T,S:CLOSE15:PRINT\"=\";E;E$;T;S");
        string[] screen = Command(machine, "RUN", seconds);
        string line = screen.LastOrDefault(text => text.StartsWith('=')) ?? string.Join('\n', screen);
        return line[1..].TrimEnd();
    }

    /// <summary>
    ///  BASIC 4's <c>DIRECTORY</c> lists the demo disk without loading over the program, on both keyboards.
    /// </summary>
    /// <param name="model">The model.</param>
    [TestMethod]
    [DataRow(PetModel.Pet4032)]
    [DataRow(PetModel.Pet4032Business)]
    public void Basic4DirectoryLists(PetModel model)
    {
        PetMachine machine = Machine(model: model);
        machine.Disks[0].Drive0.Insert(D64Format.Read(DemoImage()), "2040-demo", "D64");
        PetMachineTests.RunToReady(machine);

        Command(machine, "10 REM KEPT");
        string[] screen = Command(machine, "DIRECTORY");
        string text = string.Join('\n', screen);
        screen.Should().Contain(line => line.TrimEnd() == " 27   \"DUM 3.4\"          PRG", text);
        screen.Should().Contain(line => line.TrimEnd() == " 395 BLOCKS FREE.", text);

        screen = Command(machine, "LIST");
        screen.Should().Contain(line => line.TrimEnd() == " 10 REM KEPT", string.Join('\n', screen));
    }

    /// <summary>
    ///  BASIC 4's disk commands on a blank disk: <c>HEADER</c> formats it once answered, <c>DSAVE</c> and
    ///  <c>DLOAD</c> save and load a program, <c>DS$</c> reads the drive's status, and <c>RENAME</c> and
    ///  <c>SCRATCH</c> work on the file.
    /// </summary>
    [TestMethod]
    public void Basic4DiskCommands()
    {
        PetMachine machine = Machine(model: PetModel.Pet4032);
        CommodoreDisk disk = CommodoreDisk.Blank();
        machine.Disks[0].Drive0.Insert(disk, "blank", "D64", changed: true);
        PetMachineTests.RunToReady(machine);

        Answer(machine, "HEADER\"RETROCORE\",D0,IRC", "Y", seconds: 120);
        Status(machine).Should().Be("00, OK,00,00");

        Command(machine, "10 PRINT\"FROM DISK\"");
        Command(machine, "DSAVE\"PROGRAM\"");
        Status(machine).Should().Be("00, OK,00,00");
        Command(machine, "NEW");
        Command(machine, "DLOAD\"PROGRAM\"");
        string[] screen = Command(machine, "RUN");
        screen.Should().Contain(line => line.TrimEnd() == "FROM DISK", string.Join('\n', screen));

        Command(machine, "RENAME\"PROGRAM\"TO\"RENAMED\"");
        Status(machine).Should().Be("00, OK,00,00");
        Answer(machine, "SCRATCH\"RENAMED\"", "Y");
        Status(machine).Should().Be("01, FILES SCRATCHED,01,00");
    }

    // Types a command that asks ARE YOU SURE?, answers it, and waits for READY.
    private static void Answer(PetMachine machine, string command, string answer, int seconds = 60)
    {
        foreach (char c in command + "\r") { machine.Keyboard.Type((byte)c); }
        for (int tenth = 0; tenth < 100; tenth++)
        {
            machine.Run(TimeSpan.FromSeconds(0.1));
            if (machine.ReadTextScreen().Any(line => line.Contains("SURE", StringComparison.Ordinal))) { break; }
        }

        string[] screen = Command(machine, answer, seconds);
        screen.Should().Contain(line => line.StartsWith("READY.", StringComparison.Ordinal), string.Join('\n', screen));
    }

    // Prints DS$, the drive's last status.
    private static string Status(PetMachine machine)
    {
        string[] screen = Command(machine, "PRINT\"=\"DS$");
        return (screen.LastOrDefault(text => text.StartsWith('=')) ?? string.Join('\n', screen))[1..].TrimEnd();
    }
}
