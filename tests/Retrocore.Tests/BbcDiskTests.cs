// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.IO.Compression;
using Retrocore.Machines.Acorn;
using Retrocore.Machines.Chips;
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

    /// <summary>
    ///  A seek to a track the bad-track registers skip ends on the first good track past it.
    /// </summary>
    [TestMethod]
    public void SeekToABadTrackEnds()
    {
        Intel8271 fdc = new();
        fdc.Insert(0, AcornDiskImage.Blank(40));
        Send(fdc, 0x35, 0x10, 1, 0xFF, 0);      // drive 0: bad track 1, current track 0
        Send(fdc, 0x69, 1);                     // seek drive 0 to track 1
        RunWhileBusy(fdc);
        fdc.IsBusy.Should().BeFalse();
        fdc.InterruptRequest.Should().BeTrue();
        fdc.Read(1).Should().Be(0, "the seek succeeds");
        Send(fdc, 0x7D, 0x12);                  // read the current track register
        fdc.Read(1).Should().Be(2);
    }

    /// <summary>
    ///  Bad track registers of &amp;FF, as the DFS sets them, skip nothing: a seek to track &amp;FF ends there.
    /// </summary>
    [TestMethod]
    public void SeekToTrackFFEnds()
    {
        Intel8271 fdc = new();
        fdc.Insert(0, AcornDiskImage.Blank(40));
        Send(fdc, 0x35, 0x0D, 1, 1, 0x02);      // fast steps
        Send(fdc, 0x35, 0x10, 0xFF, 0xFF, 0);   // drive 0: no bad tracks, current track 0
        Send(fdc, 0x69, 0xFF);                  // seek drive 0 to track &FF
        RunWhileBusy(fdc);
        fdc.IsBusy.Should().BeFalse();
        fdc.Read(1).Should().Be(0);
        Send(fdc, 0x7D, 0x12);
        fdc.Read(1).Should().Be(0xFF);
    }

    /// <summary>
    ///  With RECORD down, time spent on RS-423 goes on the tape as silence.
    /// </summary>
    [TestMethod]
    public void Rs423KeepsTheTapesTime()
    {
        Acia6850 acia = new();
        BbcCassette cassette = new();
        BbcSerialUla ula = new(acia, cassette);
        cassette.Insert(new AcornTape(), "blank");
        cassette.Record();
        ula.Write(0xC0);                        // motor on, RS-423
        for (int cycle = 0; cycle < BbcTiming.CpuHertz; cycle++) { ula.Tick(); }
        long units = (cassette.Tape ?? throw new AssertFailedException("A tape is in.")).HalfCycles.Sum(length => (long)length);
        units.Should().BeCloseTo(AcornTape.UnitsPerSecond, 8, "a second of silence");
    }

    /// <summary>
    ///  Recording, the tones come from the crystal whatever the transmit rate: a second at the fastest or slowest rate
    ///  is a second of tape.
    /// </summary>
    /// <param name="rate">The transmit and receive rate bits.</param>
    [TestMethod]
    [DataRow(0)]
    [DataRow(7)]
    public void RecordingKeepsTimeAtAnyRate(int rate)
    {
        Acia6850 acia = new();
        BbcCassette cassette = new();
        BbcSerialUla ula = new(acia, cassette);
        cassette.Insert(new AcornTape(), "blank");
        cassette.Record();
        acia.Write(0, 0x15);                    // divide by 16, 8 bits, 1 stop, RTS low: tones
        ula.Write((byte)(0x80 | rate | (rate << 3)));
        for (int cycle = 0; cycle < BbcTiming.CpuHertz; cycle++) { ula.Tick(); }
        long units = (cassette.Tape ?? throw new AssertFailedException("A tape is in.")).HalfCycles.Sum(length => (long)length);
        units.Should().BeCloseTo(AcornTape.UnitsPerSecond, 8, "a second of tone");
    }

    /// <summary>
    ///  The ACIA has one shift register in either mode: a character part way out when the serial ULA switches between
    ///  RS-423 and the cassette finishes on the other side, rather than waiting for the first mode to come back.
    /// </summary>
    /// <param name="startOnRs423">Whether the character starts on RS-423 and finishes on the cassette.</param>
    [TestMethod]
    [DataRow(data: true)]
    [DataRow(data: false)]
    public void ModeChangeFinishesTheCharacter(bool startOnRs423)
    {
        Acia6850 acia = new();
        BbcSerialUla ula = new(acia, new BbcCassette());
        List<byte> sent = [];
        acia.Transmitted = sent.Add;
        acia.Write(0, 0x03);                    // master reset
        acia.Write(0, 0x16);                    // divide by 64, 8 bits, 1 stop, RTS low
        byte rs423 = 0x40;
        byte cassette = 0x00;
        ula.Write(startOnRs423 ? rs423 : cassette);
        acia.Write(1, (byte)'A');
        for (int cycle = 0; cycle < 300; cycle++) { ula.Tick(); }
        sent.Should().BeEmpty("the character is still going out");
        ula.Write(startOnRs423 ? cassette : rs423);
        for (int cycle = 0; cycle < 2_000 && sent.Count == 0; cycle++) { ula.Tick(); }
        sent.Should().Equal((byte)'A');
    }

    /// <summary>
    ///  A reset, or the disk changed, part way through writing a sector keeps the bytes written, with a CRC error, on
    ///  the disk being written; a reset part way through formatting keeps the sectors formatted.
    /// </summary>
    [TestMethod]
    public void CutOffWritesKeepWhatWasWritten()
    {
        FloppySector Cut(Action<Intel8271> cut)
        {
            Intel8271 fdc = new();
            FloppyDisk disk = AcornDiskImage.Blank(40);
            fdc.Insert(0, disk);
            Send(fdc, 0x35, 0x10, 0xFF, 0xFF, 0);
            Send(fdc, 0x4B, 0, 2, 0x21);            // write drive 0, track 0, sector 2, one 256-byte sector
            int written = 0;
            for (int cycle = 0; cycle < 10_000_000 && fdc.IsBusy; cycle++)
            {
                if (fdc.DataRequest)
                {
                    if (written == 100)
                    {
                        cut(fdc);
                        break;
                    }

                    fdc.WriteData(0x5A);
                    written++;
                }

                fdc.Tick();
            }

            return disk.Track(0, 0).Single(found => found.Sector == 2);
        }

        foreach (Action<Intel8271> cut in (Action<Intel8271>[])[fdc => fdc.Reset(), fdc => fdc.Insert(0, AcornDiskImage.Blank(40))])
        {
            FloppySector sector = Cut(cut);
            sector.CrcError.Should().BeTrue();
            sector.Data[..100].ToArray().Should().OnlyContain(value => value == 0x5A, "the bytes written before the cut");
            sector.Data[100..].ToArray().Should().OnlyContain(value => value == 0xE5, "the rest is what was there");
        }

        Intel8271 formatter = new();
        FloppyDisk formatted = AcornDiskImage.Blank(40);
        formatter.Insert(0, formatted);
        Send(formatter, 0x35, 0x10, 0xFF, 0xFF, 0);
        Send(formatter, 0x63, 0, 21, 0x2A, 0, 16);  // format drive 0, track 0: ten 256-byte sectors
        int position = 0;
        for (int cycle = 0; cycle < 10_000_000 && formatter.IsBusy; cycle++)
        {
            if (formatter.DataRequest)
            {
                if (position == 12)
                {
                    formatter.Reset();              // at the fourth sector's ID, three sectors written
                    break;
                }

                formatter.WriteData(position % 4 == 2 ? (byte)(position / 4) : (byte)(position % 4 == 3 ? 1 : 0));
                position++;
            }

            formatter.Tick();
        }

        formatted.Track(0, 0).Select(sector => sector.Sector).Should().Equal(0, 1, 2);
    }

    /// <summary>
    ///  A data request reaches the INT pin, and so NMI, only in non-DMA mode.
    /// </summary>
    /// <param name="nonDma">Whether the mode register selects non-DMA mode.</param>
    [TestMethod]
    [DataRow(data: false)]
    [DataRow(data: true)]
    public void DataRequestsInterruptOnlyWithoutDma(bool nonDma)
    {
        Intel8271 fdc = new();
        fdc.Insert(0, AcornDiskImage.Blank(40));
        Send(fdc, 0x35, 0x10, 0xFF, 0xFF, 0);   // drive 0: no bad tracks, current track 0
        if (nonDma) { Send(fdc, 0x7A, 0x17, 0xC1); }
        Send(fdc, 0x53, 0, 0, 0x21);            // read drive 0, track 0, sector 0, one sector of 256 bytes
        for (int cycle = 0; cycle < 4_000_000 && !fdc.DataRequest; cycle++) { fdc.Tick(); }
        fdc.DataRequest.Should().BeTrue();
        fdc.InterruptOutput.Should().Be(nonDma);
        fdc.PeekData().Should().Be(fdc.ReadData(), "the debugger sees the byte the CPU would read");
    }

    /// <summary>
    ///  Read ID gives the whole ID field: the four ID bytes, then their CRC, high byte first.
    /// </summary>
    [TestMethod]
    public void ReadIdGivesTheCrc()
    {
        Intel8271 fdc = new();
        fdc.Insert(0, AcornDiskImage.Blank(40));
        Send(fdc, 0x35, 0x10, 0xFF, 0xFF, 0);
        Send(fdc, 0x7A, 0x17, 0xC1);            // non-DMA mode
        Send(fdc, 0x5B, 0, 0, 1);               // read one ID on drive 0, track 0
        List<byte> bytes = [];
        for (int cycle = 0; cycle < 4_000_000 && fdc.IsBusy; cycle++)
        {
            fdc.Tick();
            if (fdc.DataRequest) { bytes.Add(fdc.ReadData()); }
        }

        bytes.Should().HaveCount(6);
        bytes[0].Should().Be(0, "track 0");
        int crc = 0xFFFF;
        foreach (byte value in (byte[])[0xFE, .. bytes[..4]])
        {
            crc ^= value << 8;
            for (int bit = 0; bit < 8; bit++) { crc = (crc & 0x8000) != 0 ? (crc << 1) ^ 0x1021 : crc << 1; }
        }

        ((bytes[4] << 8) | bytes[5]).Should().Be(crc & 0xFFFF);
    }

    /// <summary>
    ///  A STEP pulse on the output port moves the head a cylinder, and the direction bit says which way.
    /// </summary>
    [TestMethod]
    public void OutputPortStepsTheHead()
    {
        Intel8271 fdc = new();
        Send(fdc, 0x7A, 0x23, 0x48);            // drive 0, head loaded
        Send(fdc, 0x7A, 0x23, 0x4A);            // STEP, inward
        Send(fdc, 0x7A, 0x23, 0x48);
        Send(fdc, 0x7A, 0x23, 0x4A);
        fdc.Cylinder(0).Should().Be(2);
        Send(fdc, 0x7A, 0x23, 0x4C);            // outward, STEP low
        Send(fdc, 0x7A, 0x23, 0x4E);            // STEP
        fdc.Cylinder(0).Should().Be(1);
    }

    /// <summary>
    ///  A sector count of 0 is 32: verifying 32 sectors from sector 0 of a ten-sector track runs out of sectors,
    ///  rather than verifying none and succeeding.
    /// </summary>
    [TestMethod]
    public void ZeroSectorCountIsThirtyTwo()
    {
        Intel8271 fdc = new();
        fdc.Insert(0, AcornDiskImage.Blank(40));
        Send(fdc, 0x35, 0x10, 0xFF, 0xFF, 0);   // drive 0: no bad tracks, current track 0
        Send(fdc, 0x5F, 0, 0, 0x20);            // verify drive 0, track 0, from sector 0, a count of 0, 256 bytes
        RunWhileBusy(fdc);
        fdc.Read(1).Should().NotBe(0, "sector 10 is not there");
    }

    /// <summary>
    ///  Taking the disk out of the drive a command is using ends the command, not ready.
    /// </summary>
    [TestMethod]
    public void EjectingEndsTheCommand()
    {
        Intel8271 fdc = new();
        fdc.Insert(0, AcornDiskImage.Blank(40));
        Send(fdc, 0x35, 0x10, 0xFF, 0xFF, 0);
        Send(fdc, 0x53, 0, 0, 0x21);            // read drive 0, track 0, sector 0, one sector
        for (int cycle = 0; cycle < 4_000_000 && !fdc.DataRequest; cycle++) { fdc.Tick(); }
        fdc.Insert(0, disk: null);
        fdc.IsBusy.Should().BeFalse();
        fdc.DataRequest.Should().BeFalse();
        fdc.InterruptRequest.Should().BeTrue();
        fdc.Read(1).Should().Be(0x10, "not ready");
    }

    /// <summary>
    ///  The drive status shows the index hole only while a disk turns: never with no disk, and with one once the
    ///  head is loaded.
    /// </summary>
    /// <param name="disk">Whether drive 0 has a disk.</param>
    [TestMethod]
    [DataRow(data: false)]
    [DataRow(data: true)]
    public void IndexNeedsATurningDisk(bool disk)
    {
        Intel8271 fdc = new();
        if (disk) { fdc.Insert(0, AcornDiskImage.Blank(40)); }
        Send(fdc, 0x7A, 0x23, 0x48);            // the output port: drive 0 selected, head loaded
        bool index = false;
        for (int cycle = 0; cycle < Intel8271.RevolutionCycles && !index; cycle += Intel8271.ByteCycles)
        {
            Send(fdc, 0x6C);                    // read drive 0's status
            index = (fdc.Read(1) & 0x10) != 0;
            for (int tick = 0; tick < Intel8271.ByteCycles; tick++) { fdc.Tick(); }
        }

        index.Should().Be(disk);
    }

    /// <summary>
    ///  An idle head unloads at its count of index pulses from when it went idle, not after that many revolutions:
    ///  a count of 0 or 1 at the next index, which is less than a revolution away, and 2 a revolution later.
    /// </summary>
    [TestMethod]
    public void HeadUnloadsAtIndexPulses()
    {
        int next = IdleCycles(count: 1);
        next.Should().BeInRange(1, Intel8271.RevolutionCycles - 1, "the verify does not end exactly at an index");
        IdleCycles(count: 0).Should().Be(next);
        IdleCycles(count: 2).Should().Be(next + Intel8271.RevolutionCycles);
    }

    // The cycles a head stays loaded after a verify, with an index count.
    private static int IdleCycles(int count)
    {
        Intel8271 fdc = new();
        fdc.Insert(0, AcornDiskImage.Blank(40));
        Send(fdc, 0x35, 0x0D, 1, 1, (byte)(count << 4));
        Send(fdc, 0x35, 0x10, 0xFF, 0xFF, 0);
        Send(fdc, 0x5F, 0, 0, 0x21);            // verify drive 0, track 0, sector 0, which loads the head
        RunWhileBusy(fdc);
        fdc.HeadLoaded.Should().BeTrue();

        int idle = 0;
        while (fdc.HeadLoaded && idle < 4 * Intel8271.RevolutionCycles)
        {
            fdc.Tick();
            idle++;
        }

        return idle;
    }

    /// <summary>
    ///  Formatting stops at the next index: of sixteen 256-byte sectors, only those a revolution holds are written.
    /// </summary>
    [TestMethod]
    public void FormatStopsAtTheIndex()
    {
        Intel8271 fdc = new();
        FloppyDisk disk = AcornDiskImage.Blank(40);
        fdc.Insert(0, disk);
        Send(fdc, 0x35, 0x10, 0xFF, 0xFF, 0);
        Send(fdc, 0x63, 0, 21, 0x30, 0, 16);    // format drive 0, track 0: gap 3 of 21, 16 sectors of 256 bytes
        byte[] id = [0, 0, 0, 1];
        int position = 0;
        for (int cycle = 0; cycle < 10_000_000 && fdc.IsBusy; cycle++)
        {
            if (fdc.DataRequest)
            {
                fdc.WriteData(position % 4 == 2 ? (byte)(position / 4) : id[position % 4]);
                position++;
            }

            fdc.Tick();
        }

        fdc.Read(1).Should().Be(0, "a full track is no error");
        int written = disk.Track(0, 0).Count;
        written.Should().BeInRange(1, 15, "a track holds about 3,125 bytes, not sixteen 256-byte sectors");
        (written * 256).Should().BeLessThan(Intel8271.RevolutionCycles / Intel8271.ByteCycles);

        // Ten 128-byte sectors with gap 3 of 230: the eighth's gap 3 reaches the index, so there is no ninth.
        fdc = new();
        disk = AcornDiskImage.Blank(40);
        fdc.Insert(0, disk);
        Send(fdc, 0x35, 0x10, 0xFF, 0xFF, 0);
        Send(fdc, 0x63, 0, 230, 0x0A, 0, 16);   // format drive 0, track 0: gap 3 of 230, ten 128-byte sectors
        position = 0;
        for (int cycle = 0; cycle < 10_000_000 && fdc.IsBusy; cycle++)
        {
            if (fdc.DataRequest)
            {
                fdc.WriteData(position % 4 == 2 ? (byte)(position / 4) : id[position % 4]);
                position++;
            }

            fdc.Tick();
        }

        fdc.Read(1).Should().Be(0);
        disk.Track(0, 0).Should().HaveCount(8);
    }

    /// <summary>
    ///  The 8271 formats the sizes it is asked for, up to 16384 bytes: one 2048-byte sector fits a track, reads back
    ///  and keeps its size through a DMK snapshot, and a 4096-byte one does not fit at all.
    /// </summary>
    /// <param name="sizeCode">The size code, 4 for 2048 bytes or 5 for 4096.</param>
    /// <param name="sectors">The sectors a revolution holds.</param>
    [TestMethod]
    [DataRow(4, 1)]
    [DataRow(5, 0)]
    public void FormatTakesLargeSectors(int sizeCode, int sectors)
    {
        Intel8271 fdc = new();
        FloppyDisk disk = AcornDiskImage.Blank(40);
        fdc.Insert(0, disk);
        Send(fdc, 0x35, 0x10, 0xFF, 0xFF, 0);
        Send(fdc, 0x63, 3, 16, (byte)((sizeCode << 5) | 2), 0, 16);    // track 3, two sectors asked for
        byte[] id = [3, 0, 0, (byte)sizeCode];
        int position = 0;
        for (int cycle = 0; cycle < 10_000_000 && fdc.IsBusy; cycle++)
        {
            if (fdc.DataRequest)
            {
                fdc.WriteData(position % 4 == 2 ? (byte)(position / 4) : id[position % 4]);
                position++;
            }

            fdc.Tick();
        }

        fdc.Read(1).Should().Be(0);
        IReadOnlyList<FloppySector> track = disk.Track(3, 0);
        track.Should().HaveCount(sectors);
        if (sectors == 0) { return; }

        track[0].Data.Length.Should().Be(2048);
        track[0].SizeCode.Should().Be(4);
        IReadOnlyList<FloppySector> again = DmkFormat.ReadSnapshot(DmkFormat.Write(disk)).Track(3, 0);
        again.Should().ContainSingle().Which.Data.Length.Should().Be(2048);

        // Read back: verify track 3, sector 0, one 2048-byte sector.
        Send(fdc, 0x5F, 3, 0, (byte)((sizeCode << 5) | 1));
        RunWhileBusy(fdc);
        fdc.Read(1).Should().Be(0);
    }

    /// <summary>
    ///  A format that fits still runs to the next index, writing gap 4, and a late DMA ends a format with the sectors
    ///  written before it kept.
    /// </summary>
    [TestMethod]
    public void FormatEndsAtTheIndexOrALateDma()
    {
        // One sector: from its ID's first request, the command ends close to a revolution later, at the index.
        Intel8271 fdc = new();
        FloppyDisk disk = AcornDiskImage.Blank(40);
        fdc.Insert(0, disk);
        Send(fdc, 0x35, 0x10, 0xFF, 0xFF, 0);
        Send(fdc, 0x63, 0, 21, 0x21, 0, 16);    // format drive 0, track 0: one sector of 256 bytes
        int position = 0;
        int sinceFirst = -1;
        for (int cycle = 0; cycle < 10_000_000 && fdc.IsBusy; cycle++)
        {
            if (fdc.DataRequest)
            {
                fdc.WriteData(position++ == 3 ? (byte)1 : (byte)0);
                if (sinceFirst < 0) { sinceFirst = 0; }
            }

            fdc.Tick();
            if (sinceFirst >= 0) { sinceFirst++; }
        }

        fdc.Read(1).Should().Be(0);
        disk.Track(0, 0).Should().ContainSingle();
        sinceFirst.Should().BeGreaterThan(Intel8271.RevolutionCycles - (64 * Intel8271.ByteCycles), "gap 4 runs to the index");

        // Two sectors' IDs given, then none: the third ID's request goes unanswered.
        fdc = new();
        disk = AcornDiskImage.Blank(40);
        fdc.Insert(0, disk);
        Send(fdc, 0x35, 0x10, 0xFF, 0xFF, 0);
        Send(fdc, 0x63, 0, 21, 0x2A, 0, 16);    // format drive 0, track 0: ten sectors of 256 bytes
        position = 0;
        for (int cycle = 0; cycle < 10_000_000 && fdc.IsBusy; cycle++)
        {
            if (fdc.DataRequest && position < 8)
            {
                fdc.WriteData(position % 4 == 2 ? (byte)(position / 4) : (byte)(position % 4 == 3 ? 1 : 0));
                position++;
            }

            fdc.Tick();
        }

        fdc.Read(1).Should().Be(0x0A, "late DMA");
        disk.Track(0, 0).Select(sector => sector.Sector).Should().Equal(0, 1);
    }


    /// <summary>
    ///  A write that a late DMA cuts short leaves the bytes written before it on the disk, and the field with a CRC
    ///  error, as the chip stops writing partway; it does not leave the old data looking whole.
    /// </summary>
    [TestMethod]
    public void LateDmaWriteKeepsWhatWasWritten()
    {
        Intel8271 fdc = new();
        FloppyDisk disk = AcornDiskImage.Blank(40);
        fdc.Insert(0, disk);
        Send(fdc, 0x35, 0x10, 0xFF, 0xFF, 0);
        Send(fdc, 0x4B, 0, 2, 0x21);                    // write drive 0, track 0, sector 2, one 256-byte sector
        int written = 0;
        for (int cycle = 0; cycle < 10_000_000 && fdc.IsBusy; cycle++)
        {
            if (fdc.DataRequest && written < 100)
            {
                fdc.WriteData(0x5A);
                written++;
            }

            fdc.Tick();
        }

        fdc.Read(1).Should().Be(0x0A, "late DMA");
        FloppySector sector = disk.Track(0, 0).Single(found => found.Sector == 2);
        sector.CrcError.Should().BeTrue();
        sector.Data[..100].ToArray().Should().OnlyContain(value => value == 0x5A, "the bytes written before the late one");
        sector.Data[100..].ToArray().Should().OnlyContain(value => value == 0xE5, "the rest is what was there");
    }

    /// <summary>
    ///  Bad tracks are left out of the track numbering: with track 5 bad, logical track 6 is physical track 7, the
    ///  head steps one physical track at a time, and the current track register holds the physical position. With
    ///  tracks 0 and 1 bad, logical track 1 is physical 3.
    /// </summary>
    [TestMethod]
    public void BadTracksAreLeftOutOfTheNumbering()
    {
        Intel8271 fdc = new();
        fdc.Insert(0, AcornDiskImage.Blank(40));
        Send(fdc, 0x35, 0x10, 5, 0xFF, 0);              // drive 0: bad track 5, current track 0
        Send(fdc, 0x69, 6);                             // seek drive 0 to track 6
        RunWhileBusy(fdc);
        fdc.Read(1).Should().Be(0);
        fdc.Cylinder(0).Should().Be(7, "the head is past the bad track, not on it");
        Send(fdc, 0x7D, 0x12);                          // read the current track register
        fdc.Read(1).Should().Be(7);

        fdc = new();
        fdc.Insert(0, AcornDiskImage.Blank(40));
        Send(fdc, 0x35, 0x10, 1, 0, 0);                 // drive 0: bad tracks 1 and 0, current track 0
        Send(fdc, 0x69, 1);                             // seek drive 0 to track 1
        RunWhileBusy(fdc);
        fdc.IsBusy.Should().BeFalse("the seek ends");
        fdc.Read(1).Should().Be(0);
        fdc.Cylinder(0).Should().Be(3);
    }

    /// <summary>
    ///  The chip finds a sector by its track and sector and takes the length from the command: reading 128 bytes of a
    ///  256-byte sector gives them and a data CRC error, and writing 128 leaves the rest as it was, with a CRC that no
    ///  longer matches the sector.
    /// </summary>
    [TestMethod]
    public void CommandLengthNotIdLength()
    {
        Intel8271 fdc = new();
        FloppyDisk disk = AcornDiskImage.Blank(40);
        fdc.Insert(0, disk);
        Send(fdc, 0x35, 0x10, 0xFF, 0xFF, 0);
        Send(fdc, 0x52, 0, 2);                          // read drive 0, track 0, sector 2: 128 bytes
        int read = 0;
        for (int cycle = 0; cycle < 10_000_000 && fdc.IsBusy; cycle++)
        {
            if (fdc.DataRequest)
            {
                fdc.ReadData().Should().Be(0xE5);
                read++;
            }

            fdc.Tick();
        }

        read.Should().Be(128);
        fdc.Read(1).Should().Be(0x0E, "the data CRC is not after 128 bytes");

        Send(fdc, 0x4A, 0, 3);                          // write drive 0, track 0, sector 3: 128 bytes
        for (int cycle = 0; cycle < 10_000_000 && fdc.IsBusy; cycle++)
        {
            if (fdc.DataRequest) { fdc.WriteData(0x11); }
            fdc.Tick();
        }

        fdc.Read(1).Should().Be(0);
        FloppySector sector = disk.Track(0, 0).Single(found => found.Sector == 3);
        sector.Data.Length.Should().Be(256);
        sector.Data[..128].ToArray().Should().OnlyContain(value => value == 0x11);
        sector.Data[128..].ToArray().Should().OnlyContain(value => value == 0xE5);
        sector.CrcError.Should().BeTrue();
    }

    /// <summary>
    ///  The drive status has TRK0 in bit 1 and WR PROT in bit 3 for a protected disk; reading it, or a special
    ///  register, fills the result register, as status bit 4 shows, without an interrupt.
    /// </summary>
    [TestMethod]
    public void DriveStatusAsTheDatasheetHasIt()
    {
        Intel8271 fdc = new();
        FloppyDisk disk = AcornDiskImage.Blank(40);
        fdc.Insert(0, disk);
        Send(fdc, 0x35, 0x10, 0xFF, 0xFF, 0);
        Send(fdc, 0x69, 0);                             // seek drive 0 to track 0
        RunWhileBusy(fdc);
        fdc.Read(1);
        Send(fdc, 0x6C);                                // read drive 0's status
        (fdc.Status & 0x10).Should().Be(0x10, "the result register is full");
        (fdc.Status & 0x08).Should().Be(0, "no interrupt");
        byte status = fdc.Read(1);
        (status & 0x02).Should().Be(0x02, "TRK0");
        (status & 0x08).Should().Be(0, "not write protected");
        (fdc.Status & 0x10).Should().Be(0, "reading the result empties it");

        Send(fdc, 0x69, 3);                             // seek drive 0 to track 3
        RunWhileBusy(fdc);
        fdc.Read(1);
        disk.IsWriteProtected = true;
        Send(fdc, 0x6C);
        status = fdc.Read(1);
        (status & 0x02).Should().Be(0, "off track 0");
        (status & 0x08).Should().Be(0x08, "WR PROT");

        Send(fdc, 0x7D, 0x12);                          // read the current track register
        (fdc.Status & 0x10).Should().Be(0x10);
        Send(fdc, 0x6C);                                // a result not read is lost to the next command
        fdc.Read(1).Should().Be(status);
    }

    private static void Send(Intel8271 fdc, byte command, params byte[] parameters)
    {
        fdc.Write(0, command);
        foreach (byte parameter in parameters) { fdc.Write(1, parameter); }
    }

    private static void RunWhileBusy(Intel8271 fdc)
    {
        for (int cycle = 0; cycle < 10_000_000 && fdc.IsBusy; cycle++) { fdc.Tick(); }
    }
}
