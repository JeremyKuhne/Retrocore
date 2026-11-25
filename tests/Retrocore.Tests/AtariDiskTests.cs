// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Atari;
using Retrocore.Machines.Devices;
using Retrocore.Media.Atari;

namespace Retrocore.Tests;

/// <summary>
///  The serial bus and the disk drive: DOS 2.0S from its master disk (<c>%USERPROFILE%\Retrocore\atari8-media</c>),
///  BASIC's disk files, and the drive's commands.
/// </summary>
[TestClass]
public class AtariDiskTests
{
    /// <summary>
    ///  Gets DOS 2.0S's master disk image, or marks the test inconclusive without it.
    /// </summary>
    /// <returns>The image.</returns>
    internal static byte[] MasterDisk()
    {
        string path = Path.Join(ExternalTestData.Root, "atari8-media", "810_Master_Disk_DOS_2.0s_1980_Atari.atr");
        if (!File.Exists(path)) { Assert.Inconclusive($"DOS 2.0S's master disk isn't at {path}."); }
        return File.ReadAllBytes(path);
    }

    /// <summary>
    ///  Makes a machine with one drive and the master disk in it.
    /// </summary>
    /// <param name="basic">Whether Atari BASIC (rev. C) is in the left slot.</param>
    /// <param name="writeProtected">Whether the disk is write-protected.</param>
    /// <param name="kind">The drive: the 810, or the command-level drive.</param>
    /// <returns>The machine.</returns>
    internal static AtariMachine Machine(
        bool basic = false,
        bool writeProtected = false,
        AtariDiskDriveKind kind = AtariDiskDriveKind.Atari810)
    {
        byte[] image = MasterDisk();
        AtariMachine template = AtariMachineTests.Machine(basic: basic ? 'C' : null);
        AtariRoms roms = AtariRoms.LoadFromDirectory(AtariMachineTests.RomDirectory);
        if (kind == AtariDiskDriveKind.Atari810 && roms.DiskDrive.IsEmpty)
        {
            Assert.Inconclusive("The 810's firmware (MAME's atari810 set) isn't beside the OS ROMs.");
        }

        AtariMachine machine = new(roms, left: template.Bus.Left, diskDrives: 1, driveKind: kind);

        machine.Drives[0].Insert(AtariDisk.Load(image, writeProtected), "master.atr");
        return machine;
    }

    private static string Text(string[] screen) => string.Join('\n', screen.Select(line => line.TrimEnd()));

    // Runs until the screen's last line with text is the given one: the command typed above it has finished.
    private static string[] RunUntilLast(AtariMachine machine, string last, double seconds)
    {
        for (int tenth = 0; tenth < seconds * 10; tenth++)
        {
            machine.Run(TimeSpan.FromSeconds(0.1));
            string[] screen = machine.ReadTextScreen();
            if (screen.LastOrDefault(line => line.Trim().Length != 0)?.Trim() == last) { return screen; }
        }

        return machine.ReadTextScreen();
    }

    /// <summary>
    ///  Without a cartridge, DOS 2.0S boots and loads DUP.SYS's menu; A lists the directory.
    /// </summary>
    /// <param name="kind">The drive.</param>
    [TestMethod]
    [DataRow(AtariDiskDriveKind.Atari810)]
    [DataRow(AtariDiskDriveKind.CommandLevel)]
    public void DosBootsAndListsTheDirectory(AtariDiskDriveKind kind)
    {
        AtariMachine machine = Machine(kind: kind);
        string[] screen = AtariMachineTests.RunUntil(machine, line => line.Contains("SELECT ITEM", StringComparison.Ordinal), seconds: 30);
        screen.Should().Contain(line => line.Trim() == "DISK OPERATING SYSTEM II VERSION 2.0S", Text(screen));

        AtariMachineTests.Type(machine, "A\r");
        AtariMachineTests.Type(machine, "\r");
        screen = AtariMachineTests.RunUntil(machine, line => line.Contains("FREE SECTORS", StringComparison.Ordinal), seconds: 20);
        string text = Text(screen);
        screen.Should().Contain(line => line.Trim() == "DOS     SYS 039", text);
        screen.Should().Contain(line => line.Trim() == "DUP     SYS 042", text);
        screen.Should().Contain(line => line.Contains("FREE SECTORS", StringComparison.Ordinal), text);
    }

    /// <summary>
    ///  With BASIC, DOS boots underneath it; a program saved to the disk and loaded back lists the same, and the
    ///  disk is changed.
    /// </summary>
    /// <param name="kind">The drive.</param>
    [TestMethod]
    [DataRow(AtariDiskDriveKind.Atari810)]
    [DataRow(AtariDiskDriveKind.CommandLevel)]
    public void BasicSavesAndLoadsFromDisk(AtariDiskDriveKind kind)
    {
        AtariMachine machine = Machine(basic: true, kind: kind);
        AtariMachineTests.RunUntil(machine, line => line.Trim() == "READY", seconds: 30);
        machine.Bus.Peek(0x0C).Should().NotBe(0, "DOS set DOSINI");

        AtariMachineTests.Type(machine, "10 PRINT \"FROM DISK\"\r");
        AtariMachineTests.Type(machine, "SAVE \"D:TEST.BAS\"\r");
        RunUntilLast(machine, "READY", seconds: 20);
        machine.Drives[0].Disk?.IsDirty.Should().BeTrue();

        AtariMachineTests.Type(machine, "NEW\r");
        AtariMachineTests.Type(machine, "LOAD \"D:TEST.BAS\"\r");
        RunUntilLast(machine, "READY", seconds: 20);
        AtariMachineTests.Type(machine, "RUN\r");
        string[] screen = machine.ReadTextScreen();
        screen.Should().Contain(line => line.Trim() == "FROM DISK", Text(screen));
    }

    /// <summary>
    ///  Saving to a write-protected disk fails with error 144, the device's write protect status.
    /// </summary>
    /// <param name="kind">The drive.</param>
    [TestMethod]
    [DataRow(AtariDiskDriveKind.Atari810)]
    [DataRow(AtariDiskDriveKind.CommandLevel)]
    public void WriteProtectedDiskRefusesASave(AtariDiskDriveKind kind)
    {
        AtariMachine machine = Machine(basic: true, writeProtected: true, kind: kind);
        AtariMachineTests.RunUntil(machine, line => line.Trim() == "READY", seconds: 30);
        AtariMachineTests.Type(machine, "10 REM\r");
        AtariMachineTests.Type(machine, "SAVE \"D:TEST.BAS\"\r");
        string[] screen = AtariMachineTests.RunUntil(machine, line => line.Contains("ERROR", StringComparison.Ordinal), seconds: 20);
        screen.Should().Contain(line => line.Trim() == "ERROR-   144", Text(screen));
        machine.Drives[0].Disk?.IsDirty.Should().BeFalse();
    }

    /// <summary>
    ///  An ATR round-trips, double density's 128-byte boot sectors included, and an XFD reads as single density.
    /// </summary>
    [TestMethod]
    public void ImagesRoundTrip()
    {
        AtariDisk disk = AtariDisk.Create(720, 256);
        byte[] sector = new byte[256];
        sector.AsSpan().Fill(0x5A);
        disk.WriteSector(4, sector);
        disk.WriteSector(1, sector.AsSpan(0, 128));
        AtariDisk copy = AtariDisk.Load(disk.ToAtr());
        copy.SectorSize.Should().Be(256);
        copy.SectorCount.Should().Be(720);
        copy.SizeOf(3).Should().Be(128);
        byte[] read = new byte[256];
        copy.ReadSector(4, read);
        read.Should().Equal(sector);
        disk.ToAtr().Length.Should().Be(16 + 384 + (717 * 256));

        AtariDisk single = AtariDisk.Load(new byte[720 * 128]);
        single.SectorSize.Should().Be(128);
        single.SectorCount.Should().Be(720);
        AtariDisk.Load((AtariDiskCodec.For("xfd") ?? throw new AssertFailedException("XFD")).Encode(single.Snapshot()).Bytes).SectorCount.Should().Be(720);
    }

    /// <summary>
    ///  An ATR too short for its three boot sectors is refused.
    /// </summary>
    /// <param name="sectorSize">The ATR's sector size.</param>
    /// <param name="bodyLength">The bytes after the header.</param>
    [TestMethod]
    [DataRow(256, 0)]
    [DataRow(256, 128)]
    [DataRow(256, 256)]
    [DataRow(256, 512)]
    [DataRow(128, 0)]
    [DataRow(128, 128)]
    [DataRow(128, 256)]
    public void ShortAtrIsRefused(int sectorSize, int bodyLength)
    {
        byte[] image = new byte[16 + bodyLength];
        image[0] = 0x96;
        image[1] = 0x02;
        image[2] = (byte)(bodyLength / 16);
        image[3] = (byte)(bodyLength / 16 >> 8);
        image[4] = (byte)sectorSize;
        image[5] = (byte)(sectorSize >> 8);
        Action load = () => AtariDisk.Load(image);
        load.Should().Throw<InvalidDataException>();
    }

    /// <summary>
    ///  A disk changed between a command and its execution fails the command with Error rather than throwing: one
    ///  too small for the sector, or one whose sector is larger than the data frame the command took.
    /// </summary>
    [TestMethod]
    public void DiskChangedMidCommandFailsIt()
    {
        AtariMachine machine = new(new AtariRoms(new byte[AtariRoms.Size]), diskDrives: 1, driveKind: AtariDiskDriveKind.CommandLevel);
        AtariSioDiskDrive drive = (AtariSioDiskDrive)machine.Drives[0];
        IAtariSioDevice device = drive;
        drive.Head.Motor.Should().BeFalse("the drive hasn't been used");
        drive.Activity.Should().Be(DeviceActivity.Idle);

        drive.Insert(AtariDisk.Create());
        device.Accept(0x57, 700).Should().Be(128);
        drive.Insert(AtariDisk.Create(sectorCount: 3));
        device.Execute(0x57, 700, new byte[128], cycle: 0).Success.Should().BeFalse("the new disk has no sector 700");
        device.Execute(0x52, 700, [], cycle: 0).Success.Should().BeFalse("the new disk has no sector 700");

        drive.Insert(AtariDisk.Create());
        device.Accept(0x50, 4).Should().Be(128);
        drive.Insert(AtariDisk.Create(sectorSize: 256));
        device.Execute(0x50, 4, new byte[128], cycle: 0).Success.Should().BeFalse("the frame is short for the new sector");

        drive.Eject();
        (bool success, byte[] frame, _) = device.Execute(0x52, 1, [], cycle: 0);
        success.Should().BeFalse("the drive is empty");
        frame.Should().BeEmpty("a failed read sends no data frame, not a format's bad sector list");
    }

    /// <summary>
    ///  The SIO checksum adds with the carry wrapped around.
    /// </summary>
    [TestMethod]
    public void ChecksumWrapsTheCarry()
    {
        AtariSioBus.Checksum([0x31, 0x52, 0x68, 0x01]).Should().Be(0xEC);
        AtariSioBus.Checksum([0xFF, 0x02]).Should().Be(0x02);
    }
}
