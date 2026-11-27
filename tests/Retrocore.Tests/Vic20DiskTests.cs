// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.IO.Compression;
using Retrocore.Machines.Chips;
using Retrocore.Machines.Commodore.Serial;
using Retrocore.Machines.Commodore.Vic20;
using Retrocore.Media.Commodore;

namespace Retrocore.Tests;

/// <summary>
///  The VIC-20 with a 1541 or 1540 on its serial bus, through the kernal's and the drive's own DOS.
/// </summary>
/// <remarks>
///  <para>
///   The drives' ROMs are MAME's <c>c1541</c> and <c>c1540</c> sets, unzipped beside the VIC-20's; the disks are its
///   <c>vic1001_flop</c> list, under <c>%USERPROFILE%\Retrocore\vic20-media\extract</c>. The tests that need them are
///   inconclusive without them.
///  </para>
/// </remarks>
[TestClass]
public class Vic20DiskTests
{
    /// <summary>
    ///  Makes a machine with a drive as device 8, at power-on, or marks the test inconclusive without the dumps.
    /// </summary>
    /// <param name="model">The drive, <c>1541</c> or <c>1540</c>.</param>
    /// <param name="standard">The video standard.</param>
    /// <returns>The machine, and its drive.</returns>
    internal static (Vic20Machine Machine, Cbm1541 Drive) Machine(string model = "1541", VicVideoStandard standard = VicVideoStandard.Ntsc)
    {
        Vic20Machine machine = Vic20MachineTests.Machine(standard);
        string directory = Path.Join(Vic20MachineTests.RomRoot, "c" + model);
        string[] chips = model == "1540" ? ["325302-01.uab4", "325303-01.uab5"] : ["325302-01.uab4", "901229-06 aa.uab5"];
        if (!chips.All(chip => File.Exists(Path.Join(directory, chip))))
        {
            Assert.Inconclusive($"MAME's c{model} set is missing.");
        }

        Cbm1541Roms roms = model == "1540"
            ? Cbm1541Roms.Load1540FromDirectory(directory)
            : Cbm1541Roms.Load1541FromDirectory(directory);

        return (machine, machine.AddDisk(roms));
    }

    /// <summary>
    ///  <c>LOAD "$",8</c> reads a disk's directory as a program, which LIST shows, down to its blocks free.
    /// </summary>
    /// <param name="model">The drive.</param>
    [TestMethod]
    [DataRow("1541")]
    [DataRow("1540")]
    public void DirectoryLists(string model)
    {
        (Vic20Machine machine, Cbm1541 drive) = Machine(model);
        drive.Drive.Insert(D64Format.Read(Image("data20dm")), "data20.d64", "D64");
        Vic20MachineTests.RunToReady(machine);
        Vic20MachineTests.Type(machine, "LOAD\"$\",8\r");
        Vic20TapeTests.WaitForReady(machine);
        Vic20MachineTests.Type(machine, "LIST\r");
        Shows(machine, drive, "BLOCKS FREE.");
    }

    /// <summary>
    ///  Two drives, as devices 8 and 9, each list their own disk; a disk swapped in drive 8 is read again, as the
    ///  write protect sensor tells the DOS it changed; and a protected disk refuses a write.
    /// </summary>
    [TestMethod]
    public void DrivesListTheirOwnDisksAndSeeAChange()
    {
        (Vic20Machine machine, Cbm1541 first) = Machine();
        Cbm1541 second = machine.AddDisk(Cbm1541Roms.Load1541FromDirectory(Path.Join(Vic20MachineTests.RomRoot, "c1541")), 9);
        machine.Disks.Select(unit => unit.Address).Should().Equal(8, 9);
        machine.Devices.Should().Equal(machine.Cassette, first.Drive, second.Drive);

        byte[] data20 = Image("data20dm");
        byte[] speakez = Image("speakez");
        first.Drive.Insert(D64Format.Read(data20), "data20.d64", "D64");
        second.Drive.Insert(D64Format.Read(speakez), "speakeasy.d64", "D64");
        Vic20MachineTests.RunToReady(machine);

        ListsDisk(machine, first, 8, data20);
        ListsDisk(machine, second, 9, speakez);

        first.Drive.Eject();
        machine.Run(TimeSpan.FromSeconds(0.5));
        first.Drive.Insert(D64Format.Read(speakez), "speakeasy.d64", "D64");
        machine.Run(TimeSpan.FromSeconds(0.5));
        ListsDisk(machine, first, 8, speakez);

        first.Drive.SetWriteProtected(writeProtected: true);
        Command(machine, "S0:TONGUES").Should().Contain("RESULT 26 WRITE PROTECT ON");
    }

    // LOAD "$" from a device and LIST, which must show the disk's blocks free, as its BAM counts them.
    private static void ListsDisk(Vic20Machine machine, Cbm1541 drive, int device, byte[] image)
    {
        // The BAM is track 18 sector 0; each track's free count is at 4 × track, and track 18's is not counted.
        int bam = 17 * 21 * 256;
        int free = Enumerable.Range(1, 35).Where(track => track != 18).Sum(track => image[bam + (4 * track)]);
        string name = $"{free} BLOCKS FREE.";
        Vic20MachineTests.Type(machine, $"NEW\rLOAD\"$\",{device}\r");
        Vic20TapeTests.WaitForReady(machine);
        Vic20MachineTests.Type(machine, "LIST\r");
        Shows(machine, drive, name);
    }

    /// <summary>
    ///  The gate array reads a track as its image holds it: after each sync, every byte, counted from the bit after
    ///  the sync's last one, with BYTE READY falling for each.
    /// </summary>
    [TestMethod]
    public void GateArrayReadsEveryByteAfterSync()
    {
        (Vic20Machine _, Cbm1541 unit) = Machine();
        CommodoreDisk disk = D64Format.Read(Image("data20dm"));
        const int position = 34;
        unit.Drive.Insert(disk, "data20.d64", "D64");
        unit.Drive.Motor = true;
        for (int phase = 1; unit.Drive.Position < position; phase++) { unit.Drive.Step(phase & 3); }

        Cbm1541GateArray gate = unit.GateArray;
        gate.ReadSelect = true;
        gate.ByteReadyEnabled = true;
        gate.Zone = disk.Zone(position);
        List<List<byte>> runs = [];
        bool wasSync = true;

        // A turn is 200,000 microseconds.
        for (int microsecond = 0; microsecond < 200_000; microsecond++)
        {
            gate.Advance(16);
            if (!gate.Sync && wasSync) { runs.Add([]); }
            wasSync = gate.Sync;
            bool fell = gate.ByteReadyChanges > 0 && (!gate.ByteReady || gate.ByteReadyChanges > 1);
            if (fell && runs.Count > 0) { runs[^1].Add(gate.ByteData); }
        }

        // Where each sync ends in the image: the first 0 after ten or more 1s.
        List<int> starts = [];
        int ones = 0;
        for (int bit = 0; bit < disk.BitCount(position); bit++)
        {
            bool one = disk.Read(position, bit);
            if (!one && ones >= 10) { starts.Add(bit); }
            ones = one ? ones + 1 : 0;
        }

        runs.Count.Should().BeGreaterThanOrEqualTo(starts.Count - 1, "each sync on the track was seen");
        for (int run = 0; run + 1 < starts.Count; run++)
        {
            // The bytes before the next sync's ones begin.
            int count = ((starts[run + 1] - starts[run]) / 8) - 6;
            byte[] expected = new byte[count];
            for (int i = 0; i < count * 8; i++)
            {
                if (disk.Read(position, starts[run] + i)) { expected[i / 8] |= (byte)(0x80 >> (i % 8)); }
            }

            runs[run].Take(count).Should().Equal(expected, $"the bytes after sync {run} are the image's");
        }
    }

    /// <summary>
    ///  A blank disk formatted with <c>N</c> takes a program with SAVE, which LOAD brings back and VERIFY finds the same;
    ///  then <c>R</c> renames it, <c>S</c> scratches it, <c>V</c> validates the disk and <c>I</c> initializes it,
    ///  each answering on the command channel. The disk saves as a D64 that holds what was written, and once it is
    ///  protected it cannot be formatted again.
    /// </summary>
    /// <param name="model">The drive.</param>
    [TestMethod]
    [DataRow("1541")]
    [DataRow("1540")]
    public void FormatSaveLoadAndCommands(string model)
    {
        (Vic20Machine machine, Cbm1541 drive) = Machine(model);
        CommodoreDisk disk = CommodoreDisk.Blank();
        drive.Drive.Insert(disk, "blank", "G64", changed: true);
        Vic20MachineTests.RunToReady(machine);

        Command(machine, "N0:RETROCORE,RC").Should().Contain("RESULT 0 OK");
        Vic20MachineTests.Type(machine, "NEW\r10 PRINT \"DISK\";6*7\r");
        Vic20MachineTests.Type(machine, "SAVE\"PROG\",8\r");
        Vic20TapeTests.WaitForReady(machine);
        Vic20MachineTests.Type(machine, "NEW\rLOAD\"PROG\",8\r");
        Vic20TapeTests.WaitForReady(machine);
        Vic20MachineTests.Type(machine, "RUN\r");
        Shows(machine, drive, "DISK 42");
        Vic20MachineTests.Type(machine, "VERIFY\"PROG\",8\r");
        Vic20TapeTests.WaitForReady(machine);
        machine.ReadTextScreen().Should().Contain(line => line.TrimEnd() == "OK", Screen(machine));

        (byte[] image, IReadOnlyList<string> unreadable) = D64Format.Write(disk);
        unreadable.Should().BeEmpty();
        // The first directory sector, track 18 sector 1, after tracks 1-17's 21 sectors each.
        image.AsSpan(((17 * 21) + 1) * 256, 256).IndexOf("PROG"u8).Should().BePositive("the directory names the file");

        Command(machine, "R0:RENAMED=PROG").Should().Contain("RESULT 0 OK");
        Command(machine, "S0:RENAMED").Should().Contain("RESULT 1 FILES SCRATCHED");
        Command(machine, "V0").Should().Contain("RESULT 0 OK");
        Command(machine, "I0").Should().Contain("RESULT 0 OK");

        // A protected disk: the format job ends in WRITE PROTECT ON after its retries, but DOS 2.6 answers N with READ
        // ERROR, as MAME's 1541 does. A scratch answers WRITE PROTECT ON (DrivesListTheirOwnDisksAndSeeAChange).
        drive.Drive.SetWriteProtected(writeProtected: true);
        Command(machine, "N0:REFUSED,RF").Should().Contain("RESULT 21 READ ERROR");
    }

    /// <summary>
    ///  The disks of MAME's list load: Speakeasy's, a D64, and VIC File, VIC Writer and Simplicalc, G64s. (The Data 20
    ///  demo, whose directory <see cref="DirectoryLists"/> reads, needs the Video Pak cartridge to run.)
    /// </summary>
    /// <param name="software">The list's name for the disk.</param>
    [TestMethod]
    [DataRow("vicfile")]
    [DataRow("vicwrite")]
    [DataRow("simpcalc")]
    [DataRow("speakez")]
    public void MameDiskLoads(string software)
    {
        (Vic20Machine machine, Cbm1541 drive) = Machine();
        (CommodoreDisk disk, CommodoreDiskCodec codec) = CommodoreDiskCodec.Load(Image(software));
        drive.Drive.Insert(disk, software, codec.Format);
        Vic20MachineTests.RunToReady(machine);
        Vic20MachineTests.Type(machine, "LOAD\"*\",8\r");
        Vic20TapeTests.WaitForReady(machine);

        Shows(machine, drive, "LOADING");
        if (Screen(machine).Contains("ERROR", StringComparison.Ordinal)) { Assert.Fail(DriveState(machine, drive)); }
        (machine.Bus.Peek(0x2D) | (machine.Bus.Peek(0x2E) << 8)).Should().BeGreaterThan(0x1010, "a program loaded");
    }

    // Fails with the screen and the drive's state, which reading the command channel adds, unless the screen shows the
    // text.
    private static void Shows(Vic20Machine machine, Cbm1541 drive, string text)
    {
        if (!Screen(machine).Contains(text, StringComparison.Ordinal))
        {
            Assert.Fail($"No {text}:\n{DriveState(machine, drive)}");
        }
    }

    // Sends a command to the drive's command channel and prints its answer: RESULT, the number and the message.
    private static string Command(Vic20Machine machine, string command)
    {
        Vic20MachineTests.Type(machine, $"NEW\r10 OPEN15,8,15,\"{command}\":INPUT#15,A,B$:PRINT\"RESULT\";A;B$:CLOSE15\rRUN\r");
        Vic20TapeTests.WaitForReady(machine);
        return string.Concat(machine.ReadTextScreen());
    }

    private static string DriveState(Vic20Machine machine, Cbm1541 drive)
    {
        Vic20MachineTests.Type(machine, "NEW\r10 OPEN15,8,15:INPUT#15,A,B$,C,D:PRINTA;B$;C;D\rRUN\r");
        Vic20TapeTests.WaitForReady(machine);
        string jobs = string.Join(' ', Enumerable.Range(0, 8).Select(i => drive.Ram[i].ToString("X2")));
        string state = $"pos {drive.Drive.Position} motor {drive.Drive.Motor} jobs {jobs}";
        return $"{Screen(machine)}\n{state} pc {drive.Processor.Registers.ProgramCounter:X4} sync {drive.GateArray.Sync}";
    }

    /// <summary>
    ///  Reads a disk image from MAME's <c>vic1001_flop</c> list.
    /// </summary>
    /// <param name="software">The list's name for the disk.</param>
    /// <returns>The image.</returns>
    internal static byte[] Image(string software)
    {
        string zip = Path.Join(ExternalTestData.Root, "vic20-media", "extract", "vic1001_flop", "vic1001_flop", software + ".zip");
        if (!File.Exists(zip))
        {
            Assert.Inconclusive("MAME's vic1001_flop list is missing; see vic20-media's README.");
        }

        using ZipArchive archive = ZipFile.OpenRead(zip);
        using MemoryStream stream = new();
        using (Stream entry = archive.Entries[0].Open()) { entry.CopyTo(stream); }
        return stream.ToArray();
    }

    private static string Screen(Vic20Machine machine) => string.Join('\n', machine.ReadTextScreen());
}
