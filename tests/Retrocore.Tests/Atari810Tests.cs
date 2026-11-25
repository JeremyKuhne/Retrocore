// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Atari;
using Retrocore.Media.Atari;
using Retrocore.Media.Floppy;

namespace Retrocore.Tests;

/// <summary>
///  The 810 at the hardware level: its firmware formats, parks its head and times out on an empty drive, as the
///  Altirra Hardware Reference Manual (10.5, 10.9) describes. DOS 2.0S's master disk and the firmware come from
///  <c>%USERPROFILE%\Retrocore</c>; the tests are inconclusive without them.
/// </summary>
[TestClass]
public class Atari810Tests
{
    private static string Text(string[] screen) => string.Join('\n', screen.Select(line => line.TrimEnd()));

    private static string? LastLine(string[] screen) => screen.LastOrDefault(line => line.Trim().Length != 0)?.Trim();

    /// <summary>
    ///  DOS 2.0S's menu formats a blank disk through the 810: revision C's firmware writes each track's sector 18,
    ///  then its odd sectors, then its even ones, and DOS writes a VTOC of 707 free sectors and an empty directory.
    /// </summary>
    [TestMethod]
    public void DosFormatsABlankDisk()
    {
        AtariMachine machine = AtariDiskTests.Machine();
        AtariMachineTests.RunUntil(machine, line => line.Contains("SELECT ITEM", StringComparison.Ordinal), seconds: 30);
        Atari810 drive = (Atari810)machine.Drives[0];
        AtariDisk blank = AtariDisk.Create();
        drive.Insert(blank, "blank.atr");

        AtariMachineTests.Type(machine, "I\r");
        AtariMachineTests.RunUntil(machine, line => line.Contains("FORMAT?", StringComparison.Ordinal), seconds: 5);
        AtariMachineTests.Type(machine, "1\r");
        AtariMachineTests.RunUntil(machine, line => line.Contains("TO FORMAT", StringComparison.Ordinal), seconds: 5);
        AtariMachineTests.Type(machine, "Y\r");

        // About ten seconds to write the 40 tracks, 25 to read them back, and DOS's VTOC and directory.
        string[] screen = machine.ReadTextScreen();
        for (int second = 0; second < 90 && LastLine(screen) != "SELECT ITEM OR RETURN FOR MENU"; second++)
        {
            machine.Run(TimeSpan.FromSeconds(1));
            screen = machine.ReadTextScreen();
        }

        LastLine(screen).Should().Be("SELECT ITEM OR RETURN FOR MENU", Text(screen));
        screen.Should().NotContain(line => line.Contains("ERROR", StringComparison.Ordinal), Text(screen));
        blank.IsDirty.Should().BeTrue();

        // Revision C's format order (Altirra Hardware Reference Manual, table 53), on every track.
        FloppyDisk floppy = drive.Fdc.Disk(0) ?? throw new AssertFailedException("The drive has no disk.");
        byte[] order = [18, 1, 3, 5, 7, 9, 11, 13, 15, 17, 2, 4, 6, 8, 10, 12, 14, 16];
        for (int track = 0; track < Atari810Disk.Tracks; track++)
        {
            floppy.Track(track, 0).Select(sector => sector.Sector).Should().Equal(order, $"track {track}");
            floppy.Track(track, 0).Should().OnlyContain(sector => sector.Track == track);
        }

        // DOS 2.0S's VTOC: version 2, 707 sectors, all free.
        byte[] vtoc = new byte[128];
        blank.ReadSector(360, vtoc);
        vtoc[0].Should().Be(2);
        (vtoc[1] | (vtoc[2] << 8)).Should().Be(707);
        (vtoc[3] | (vtoc[4] << 8)).Should().Be(707);
        byte[] directory = new byte[128];
        blank.ReadSector(361, directory);
        directory.Should().OnlyContain(value => value == 0, "the directory is empty");
    }

    /// <summary>
    ///  An image's tracks are laid out in the order each firmware formats them: sector 18 first (its format loop
    ///  starts with it), then the 17 in its table at <c>$086F</c>, stored inverted.
    /// </summary>
    /// <param name="file">The firmware's file in MAME's <c>atari810</c> set.</param>
    /// <param name="revision">Its revision.</param>
    [TestMethod]
    [DataRow(Atari810Firmware.RevisionCFile, 'C')]
    [DataRow(Atari810Firmware.RevisionBFile, 'B')]
    public void LayoutFollowsTheFirmwaresOrder(string file, char revision)
    {
        string path = Path.Join(Path.GetDirectoryName(AtariMachineTests.RomDirectory), "atari810", file);
        if (!File.Exists(path)) { Assert.Inconclusive($"The 810's firmware isn't at {path}."); }
        byte[] rom = File.ReadAllBytes(path);
        Atari810Firmware.Revision(rom).Should().Be(revision);

        byte[] order = [18, .. rom.AsSpan(0x6F, 17).ToArray().Select(value => (byte)~value)];
        Atari810Disk disk = new(AtariDisk.Create(), revision);
        disk.Floppy.Track(5, 0).Select(sector => sector.Sector).Should().Equal(order);
    }

    /// <summary>
    ///  After a command the firmware turns the motor off and leaves the head on track 39 with its phases off, as its
    ///  start-up does.
    /// </summary>
    [TestMethod]
    public void DriveParksAfterBooting()
    {
        AtariMachine machine = AtariDiskTests.Machine();
        Atari810 drive = (Atari810)machine.Drives[0];
        drive.Revision.Should().Be('C');
        drive.Track.Should().Be(39, "the drive was switched on first");
        drive.Motor.Should().BeFalse();

        AtariMachineTests.RunUntil(machine, line => line.Contains("SELECT ITEM", StringComparison.Ordinal), seconds: 30);
        machine.Run(TimeSpan.FromSeconds(5));
        drive.Motor.Should().BeFalse();
        drive.Track.Should().Be(39);
        drive.Head.Motor.Should().BeFalse();
    }

    /// <summary>
    ///  With no disk the 810 can't tell: it turns its motor on, looks for the boot sector until its timer gives up,
    ///  and answers Error, so the OS prints <c>BOOT ERROR</c>.
    /// </summary>
    [TestMethod]
    public void EmptyDriveFailsToBoot()
    {
        AtariMachine machine = AtariDiskTests.Machine();
        Atari810 drive = (Atari810)machine.Drives[0];
        drive.Eject();
        string[] screen = AtariMachineTests.RunUntil(machine, line => line.Contains("BOOT ERROR", StringComparison.Ordinal), seconds: 20);
        screen.Should().Contain(line => line.Trim() == "BOOT ERROR", Text(screen));
    }
}
