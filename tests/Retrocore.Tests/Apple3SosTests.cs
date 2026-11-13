// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Apple3;
using Retrocore.Media;

namespace Retrocore.Tests;

/// <summary>
///  SOS 1.3 on the Apple III, from Apple's disks: the System Utilities boot, format and copy, on floppies and on a
///  ProFile, and Business BASIC runs and saves a program.
/// </summary>
/// <remarks>
///  <para>
///   The disks are in <c>RETROCORE_APPLE3_DISKS</c> or <c>%USERPROFILE%\Retrocore\apple3-disks</c>; the tests are
///   inconclusive without them or the ROM. Each waits for text on the screen rather than for a time.
///  </para>
/// </remarks>
[TestClass]
public class Apple3SosTests
{
    private const string Utilities = "Apple3SOS1.3SysUtils.dsk";
    private const string BusinessBasic = "Apple3BusBasic1.23.dsk";

    private static string Disks => Environment.GetEnvironmentVariable("RETROCORE_APPLE3_DISKS")
        ?? Path.Join(ExternalTestData.Root, "apple3-disks");

    /// <summary>
    ///  The System Utilities format a blank disk in .D2, copy the boot disk onto it, and the copy boots to their menu.
    /// </summary>
    [TestMethod]
    public void UtilitiesFormatAndCopyADiskThatBoots()
    {
        Apple3Machine machine = Boot(Utilities);
        machine.Drives[1].Insert(WozDisk.CreateBlank(), "blank", "WOZ");
        RunUntil(machine, "Please select a command", seconds: 90);

        Type(machine, "D");
        RunUntil(machine, "Device Handling Commands Menu", seconds: 10);
        Type(machine, "F");
        RunUntil(machine, "with the new volume name", seconds: 10);
        Type(machine, "\r");
        machine.Run(TimeSpan.FromSeconds(1));
        Type(machine, "TEST\r");
        RunUntil(machine, "Formatting successful", seconds: 60);

        Type(machine, "\u001B");
        RunUntil(machine, "Device Handling Commands Menu", seconds: 10);
        Type(machine, "C");
        RunUntil(machine, "With the new volume name", seconds: 10);
        Type(machine, ".D1\r");
        machine.Run(TimeSpan.FromSeconds(1));
        Type(machine, ".D2\r");
        machine.Run(TimeSpan.FromSeconds(1));
        Type(machine, "\r");
        RunUntil(machine, "Destroy old /TEST", seconds: 20);
        Type(machine, "Y");
        RunUntil(machine, "Copy successful", seconds: 120);

        WozDisk copy = machine.Drives[1].Eject() ?? throw new InvalidOperationException("The copy left the drive.");
        Apple3Machine second = Apple3MachineTests.Machine();
        second.Drives[0].Insert(WozDisk.Load(copy.Export()), "copy", "WOZ");
        RunUntil(second, "Please select a command", seconds: 90);
        Screen(second).Should().Contain("Apple /// Utilities");
    }

    /// <summary>
    ///  With a ProFile card in slot 4, where the System Utilities disk's SOS.DRIVER has .PROFILE, the Utilities format
    ///  the ProFile, copy SOS.KERNEL onto it and list it; the file's bytes are the floppy's, and a second boot lists the
    ///  volume SOS wrote.
    /// </summary>
    [TestMethod]
    public void UtilitiesFormatAProFileAndCopyAFileToIt()
    {
        Apple3Machine machine = Boot(Utilities);
        byte[] blocks = new byte[512 * 9728];
        machine.Bus.InstallProFile(4).Drive.Insert(new MemoryBlockDevice(blocks, isReadOnly: false), "profile", "PO");
        RunUntil(machine, "Please select a command", seconds: 90);

        Type(machine, "D");
        RunUntil(machine, "Device Handling Commands Menu", seconds: 10);
        Type(machine, "F");
        RunUntil(machine, "with the new volume name", seconds: 10);
        Type(machine, ".PROFILE\r");
        machine.Run(TimeSpan.FromSeconds(1));
        Type(machine, "HARD\r");
        RunUntil(machine, "Formatting successful", seconds: 60);

        Type(machine, "\u001B");
        RunUntil(machine, "Device Handling Commands Menu", seconds: 10);
        Type(machine, "\u001B");
        RunUntil(machine, "F - File handling commands", seconds: 10);
        Type(machine, "F");
        RunUntil(machine, "File Handling Commands Menu", seconds: 10);
        Type(machine, "C");
        RunUntil(machine, "Copy the files:", seconds: 10);
        Type(machine, "SOS.KERNEL\r");
        machine.Run(TimeSpan.FromSeconds(1));
        Type(machine, "/HARD/SOS.KERNEL\r");
        RunUntil(machine, "---> /HARD/SOS.KERNEL", seconds: 60);

        Type(machine, "\u001B");
        RunUntil(machine, "File Handling Commands Menu", seconds: 10);
        ListHard(machine);
        Screen(machine).Should().Contain("SOS.KERNEL");

        // What SOS wrote through .PROFILE is a SOS volume holding the floppy's file.
        byte[] image = Image(machine.Bus.ProFileIn(4)?.Drive);
        SosVolume hard = SosVolume.ReadBlocks(image);
        hard.Name.Should().Be("HARD");
        byte[] floppy = SosVolume.Read(File.ReadAllBytes(Path.Join(Disks, Utilities)), proDosOrder: false).ReadFile("SOS.KERNEL");
        hard.ReadFile("SOS.KERNEL").Should().Equal(floppy);

        // A fresh machine reads the volume from the ProFile.
        Apple3Machine second = Boot(Utilities);
        second.Bus.InstallProFile(4).Drive.Insert(new MemoryBlockDevice(image, isReadOnly: false), "profile", "PO");
        RunUntil(second, "Please select a command", seconds: 90);
        Type(second, "F");
        RunUntil(second, "File Handling Commands Menu", seconds: 10);
        ListHard(second);
        Screen(second).Should().Contain("SOS.KERNEL");
    }

    /// <summary>
    ///  Business BASIC runs a typed program, with shifted symbols, and saves it where an unlocked and deleted file
    ///  was.
    /// </summary>
    [TestMethod]
    public void BusinessBasicRunsAndSavesAProgram()
    {
        Apple3Machine machine = Boot(BusinessBasic);
        RunUntil(machine, "TOTAL BLOCKS", seconds: 90);
        machine.Run(TimeSpan.FromSeconds(2));

        Type(machine, "HOME\r10 PRINT 6*7;\"!\"\rRUN\r");
        RunUntil(machine, "42!", seconds: 10);

        Type(machine, "UNLOCK RENUMBER.DOC\rDELETE RENUMBER.DOC\rSAVE SIX\rCATALOG\r");
        RunUntil(machine, "BLOCKS FREE", seconds: 30);
        Screen(machine).Should().Contain(" SIX ");
    }

    private static Apple3Machine Boot(string disk)
    {
        string path = Path.Join(Disks, disk);
        if (!File.Exists(path)) { Assert.Inconclusive($"Set RETROCORE_APPLE3_DISKS to a folder with {disk}."); }
        Apple3Machine machine = Apple3MachineTests.Machine();

        // A converted image is read-only; a writable copy takes the tests' writes.
        WozDisk media = SectorDiskConverter.Convert(File.ReadAllBytes(path), proDosOrder: false);
        machine.Drives[0].Insert(WozDisk.Load(media.Export(), writable: true), disk, "DSK");
        return machine;
    }

    // From the File Handling menu, lists /HARD's files on the screen.
    private static void ListHard(Apple3Machine machine)
    {
        Type(machine, "L");
        RunUntil(machine, "List the directory information", seconds: 10);
        Type(machine, "/HARD\r");
        machine.Run(TimeSpan.FromSeconds(1));
        Type(machine, "\r");
        machine.Run(TimeSpan.FromSeconds(1));
        Type(machine, "\r");
        RunUntil(machine, "1 files listed", seconds: 30);
    }

    // The blocks in a ProFile's image.
    private static byte[] Image(Machines.Apple2.ProFileDrive? drive)
    {
        IBlockDevice device = drive?.Image ?? throw new InvalidOperationException("The ProFile has no image.");
        byte[] image = new byte[device.BlockCount * 512];
        for (uint block = 0; block < device.BlockCount; block++)
        {
            device.ReadBlock(block, image.AsSpan((int)block * 512, 512));
        }

        return image;
    }

    private static void Type(Apple3Machine machine, string keys)
    {
        foreach (char key in keys) { machine.Bus.QueueKey((byte)key); }
    }

    private static string Screen(Apple3Machine machine) => string.Join('\n', machine.ReadTextScreen());

    private static void RunUntil(Apple3Machine machine, string text, int seconds)
    {
        for (int tenth = 0; tenth < seconds * 10; tenth++)
        {
            if (Screen(machine).Contains(text, StringComparison.Ordinal)) { return; }
            machine.Run(TimeSpan.FromSeconds(0.1));
        }

        Screen(machine).Should().Contain(text);
    }
}
