// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.IO.Compression;
using Retrocore.Machines.Acorn;
using Retrocore.Media;
using Retrocore.Media.Acorn;
using Retrocore.Media.Floppy;

namespace Retrocore.Tests;

/// <summary>
///  The BBC Micro's disks: DNFS 1.20's DFS on the 8271, with SSD and DSD images.
/// </summary>
[TestClass]
public class BbcDiskTests
{
    /// <summary>
    ///  Gets the Welcome disk from MAME's software list, or marks the test inconclusive.
    /// </summary>
    /// <returns>The <c>.ssd</c> image.</returns>
    internal static byte[] Welcome()
    {
        string zip = Path.Join(ExternalTestData.Root, "bbc-media", "extract", "bbcb_flop", "bbcb_flop", "welcome.zip");
        if (!File.Exists(zip)) { Assert.Inconclusive("The bbcb_flop software list is missing from bbc-media."); }
        using ZipArchive archive = ZipFile.OpenRead(zip);
        ZipArchiveEntry entry = archive.GetEntry("welcome.ssd") ?? throw new InvalidDataException("No welcome.ssd.");
        using Stream stream = entry.Open();
        using MemoryStream bytes = new();
        stream.CopyTo(bytes);
        return bytes.ToArray();
    }

    /// <summary>
    ///  Makes a Model B with DNFS 1.20, the Welcome disk in drive 0 and a blank 80-track disk in drive 1, at the prompt.
    /// </summary>
    /// <returns>The machine.</returns>
    internal static BbcMachine MachineWithDisks()
    {
        BbcMachine machine = BbcMachineTests.Machine(filingSystem: "dnfs120.rom");
        machine.Drives[0].Insert(AcornDiskImage.Read(Welcome(), doubleSided: false), "welcome.ssd", "SSD");
        machine.Drives[1].Insert(AcornDiskImage.Blank(80), "blank.ssd", "SSD");
        BbcMachineTests.RunToPrompt(machine);
        return machine;
    }

    /// <summary>
    ///  Types a command and gives it time to finish.
    /// </summary>
    /// <param name="machine">The machine.</param>
    /// <param name="text">The text, with carriage returns for RETURN.</param>
    /// <param name="seconds">The emulated seconds the command takes.</param>
    /// <returns>The screen's lines that hold something.</returns>
    internal static string[] Command(BbcMachine machine, string text, double seconds = 3)
    {
        BbcMachineTests.Type(machine, text);
        machine.Run(TimeSpan.FromSeconds(seconds));
        return Screen(machine);
    }

    /// <summary>
    ///  Runs until the last line holding something is the prompt, for up to some emulated time.
    /// </summary>
    /// <param name="machine">The machine.</param>
    /// <param name="seconds">The most emulated seconds to wait.</param>
    /// <returns>The screen's lines that hold something.</returns>
    internal static string[] UntilPrompt(BbcMachine machine, double seconds)
    {
        for (double waited = 0; waited < seconds; waited += 0.5)
        {
            machine.Run(TimeSpan.FromSeconds(0.5));
            if (Screen(machine) is [.., ">"]) { break; }
        }

        return Screen(machine);
    }

    private static string[] Screen(BbcMachine machine) =>
        [.. machine.ReadTextScreen().Where(line => line.Trim().Length != 0).Select(line => line.TrimEnd())];

    /// <summary>
    ///  With the disk interface, DNFS names the DFS at power-on, as MAME's does.
    /// </summary>
    [TestMethod]
    public void PowerOnNamesTheDfs()
    {
        BbcMachine machine = BbcMachineTests.Machine(filingSystem: "dnfs120.rom");
        string[] screen = BbcMachineTests.RunToPrompt(machine);
        screen.Should().Contain(line => line.TrimEnd() == "Acorn DFS", string.Join('\n', screen));
    }

    /// <summary>
    ///  *CAT lists the Welcome disk's title, boot option and files.
    /// </summary>
    [TestMethod]
    public void CatalogueListsTheWelcomeDisk()
    {
        string[] screen = Command(MachineWithDisks(), "*CAT\r");
        string text = string.Join('\n', screen);
        screen.Should().Contain("WELCOME-DISK (04)", text);
        screen.Should().Contain("Drive 0             Option 3 (EXEC)", text);
        screen.Should().Contain("  W.SKETCH            W.WELCOME", text);
    }

    /// <summary>
    ///  SAVE writes a program to drive 1's blank disk, which LOAD reads back and *CAT lists; the disk is changed and
    ///  saves as an SSD image the DFS reads again.
    /// </summary>
    [TestMethod]
    public void SaveAndLoadOnDrive1()
    {
        BbcMachine machine = MachineWithDisks();
        Command(machine, "*DRIVE 1\r10 PRINT \"SAVED OK\"\rSAVE \"PROG\"\r");
        string[] screen = Command(machine, "NEW\rLOAD \"PROG\"\rRUN\r*CAT\r");
        string text = string.Join('\n', screen);
        screen.Should().Contain("SAVED OK", text);
        screen.Should().Contain("    PROG", text);

        FloppyDisk disk = machine.Drives[1].Disk ?? throw new AssertFailedException("Drive 1 is empty.");
        disk.IsDirty.Should().BeTrue();
        EncodedImage image = new AcornDiskCodec("SSD").Encode(disk.Snapshot());
        image.IsLossless.Should().BeTrue(string.Join('\n', image.Losses));

        // The catalogue's first file is PROG.
        image.Bytes.AsSpan(8, 7).ToArray().Should().Equal("PROG   "u8.ToArray());
    }

    /// <summary>
    ///  *BACKUP copies drive 0 to drive 1 and *COMPACT runs on the copy.
    /// </summary>
    [TestMethod]
    public void BackupAndCompact()
    {
        BbcMachine machine = MachineWithDisks();
        Command(machine, "*ENABLE\r*BACKUP 0 1\r", seconds: 0);
        UntilPrompt(machine, 120);
        string[] screen = Command(machine, "*CAT 1\r");
        screen.Should().Contain("WELCOME-DISK (04)", string.Join('\n', screen));

        Command(machine, "*COMPACT 1\r", seconds: 0);
        screen = UntilPrompt(machine, 120);
        string text = string.Join('\n', screen);
        screen.Should().Contain(line => line.StartsWith("W.WELCOME", StringComparison.Ordinal), text);
        screen.Should().Contain(line => line.EndsWith("free sectors", StringComparison.Ordinal), text);
    }

    /// <summary>
    ///  The Welcome disk's formatter formats all 80 tracks of drive 1 and its verifier reads them back.
    /// </summary>
    [TestMethod]
    public void FormatAndVerify()
    {
        BbcMachine machine = MachineWithDisks();
        Command(machine, "*FORM80\r", seconds: 1);
        Command(machine, "1", seconds: 1);
        Command(machine, "Y", seconds: 40);
        Command(machine, "N", seconds: 1);
        // The verifier takes no key until it is ready, some seconds after its prompt.
        Command(machine, "*VERIFY 1\r", seconds: 20);
        string[] screen = Command(machine, "Y", seconds: 30);
        string text = string.Join('\n', screen);
        screen.Should().Contain("46  47  48  49  4A  4B  4C  4D  4E  4F", text);
        screen.Should().Contain(line => line.StartsWith("Disk verified", StringComparison.Ordinal), text);
        machine.Drives[1].Disk?.Track(79, 0).Should().HaveCount(10);
    }

    /// <summary>
    ///  SHIFT-BREAK runs the Welcome disk's !BOOT, which *EXECs its introduction.
    /// </summary>
    [TestMethod]
    public void ShiftBreakBoots()
    {
        BbcMachine machine = MachineWithDisks();
        machine.Keyboard.Press(BbcKey.Shift);
        machine.PressBreak();
        machine.Run(TimeSpan.FromSeconds(1));
        machine.Keyboard.Release(BbcKey.Shift);
        machine.Run(TimeSpan.FromSeconds(10));
        string[] screen = machine.ReadTextScreen();
        screen.Should().Contain(line => line.Trim() == "Press  SPACE  to see them", string.Join('\n', screen));
    }

    /// <summary>
    ///  A write-protected disk refuses SAVE with the DFS's error, Disk read only.
    /// </summary>
    [TestMethod]
    public void WriteProtectedDiskRefusesSave()
    {
        BbcMachine machine = MachineWithDisks();
        machine.Drives[1].SetWriteProtected(writeProtected: true);
        string[] screen = Command(machine, "*DRIVE 1\r10 REM\rSAVE \"PROG\"\r");
        screen.Should().Contain("Disk read only", string.Join('\n', screen));
        machine.Drives[1].Disk?.IsDirty.Should().BeFalse();
    }

    /// <summary>
    ///  A DSD image's second side is DFS drive 2.
    /// </summary>
    [TestMethod]
    public void SecondSideIsDrive2()
    {
        BbcMachine machine = BbcMachineTests.Machine(filingSystem: "dnfs120.rom");
        byte[] welcome = Welcome();
        byte[] dsd = new byte[2 * 80 * AcornDiskImage.TrackSize];
        FloppyDisk blank = AcornDiskImage.Blank(80);
        byte[] side0 = AcornDiskImage.Encode(blank, doubleSided: false).Bytes;
        for (int track = 0; track < 80; track++)
        {
            int start = track * AcornDiskImage.TrackSize;
            Span<byte> even = dsd.AsSpan(track * 2 * AcornDiskImage.TrackSize, AcornDiskImage.TrackSize);
            side0.AsSpan(start, AcornDiskImage.TrackSize).CopyTo(even);
            if (start >= welcome.Length) { continue; }
            int length = Math.Min(AcornDiskImage.TrackSize, welcome.Length - start);
            welcome.AsSpan(start, length).CopyTo(dsd.AsSpan(((track * 2) + 1) * AcornDiskImage.TrackSize));
        }

        machine.Drives[0].Insert(AcornDiskImage.Read(dsd, doubleSided: true), "both.dsd", "DSD");
        BbcMachineTests.RunToPrompt(machine);
        string[] screen = Command(machine, "*CAT 2\r");
        string text = string.Join('\n', screen);
        screen.Should().Contain("WELCOME-DISK (04)", text);
        screen.Should().Contain(line => line.StartsWith("Drive 2", StringComparison.Ordinal), text);
    }
}
