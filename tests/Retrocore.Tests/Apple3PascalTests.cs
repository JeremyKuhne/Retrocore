// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Apple3;
using Retrocore.Media;
using Retrocore.Pascal;

namespace Retrocore.Tests;

/// <summary>
///  Apple III Pascal 1.1 on the Apple III, from Apple's disks: it boots, its Filer lists the boot disk, and a program
///  is edited, compiled with a listing, and run.
/// </summary>
/// <remarks>
///  <para>
///   The disks (<c>Apple3Pascal1.1Disk1.dsk</c> and <c>Disk2.dsk</c>) are with the other Apple III disks
///   (<c>RETROCORE_APPLE3_DISKS</c>), and the ROMs are MAME's <c>apple3</c> set, as for <see cref="Apple3SosTests"/>.
///  </para>
/// </remarks>
[TestClass]
public class Apple3PascalTests
{
    private const string System = "Apple3Pascal1.1Disk1.dsk";
    private const string Tools = "Apple3Pascal1.1Disk2.dsk";

    /// <summary>
    ///  Pascal boots to its command line, and the Filer lists /PASCAL1.
    /// </summary>
    [TestMethod]
    public void PascalBootsAndTheFilerListsItsDisk()
    {
        Apple3Machine machine = Boot(System);
        RunUntil(machine, "Based on  U.C.S.D. Pascal II.1", seconds: 60);
        Type(machine, "\r");
        RunUntil(machine, "Command: E(dit, R(un, F(ile", seconds: 30);
        Type(machine, "F");
        RunUntil(machine, "Filer: L(dir", seconds: 30);
        Type(machine, "L");
        RunUntil(machine, "List what directory", seconds: 10);
        Type(machine, "*\r");
        RunUntil(machine, "7 files listed", seconds: 30);
        Screen(machine).Should().Contain("SYSTEM.PASCAL");
    }

    /// <summary>
    ///  A program typed into the Editor (ending its insertion with CONTROL-C), saved to /PASCAL2, compiled with a
    ///  listing and run prints what it should, and its code file and listing read back from the disk.
    /// </summary>
    [TestMethod]
    public void PascalCompilesAndRunsAProgram()
    {
        Apple3Machine machine = Boot(System, Tools);
        RunUntil(machine, "Based on  U.C.S.D. Pascal II.1", seconds: 60);
        Type(machine, "\r");
        RunUntil(machine, "Command: E(dit, R(un, F(ile", seconds: 30);

        Type(machine, "E");
        RunUntil(machine, "No workfile is present", seconds: 60);
        Type(machine, "\r");
        RunUntil(machine, ">Edit: A(djst", seconds: 30);
        Type(machine, "I");
        RunUntil(machine, ">Insert:", seconds: 10);
        Type(machine, "PROGRAM HELLO;\rVAR I: INTEGER;\rPROCEDURE SHOW(N: INTEGER);\rBEGIN\rWRITELN(N*7)\rEND;\r");
        Type(machine, "BEGIN\rFOR I := 1 TO 3 DO\rSHOW(I)\rEND.\r\u0003");
        RunUntil(machine, ">Edit: A(djst", seconds: 30);
        Type(machine, "Q");
        RunUntil(machine, "W(rite to a new file name", seconds: 10);
        Type(machine, "W");
        RunUntil(machine, "Name of output file", seconds: 10);
        Type(machine, "/PASCAL2/HELLO\r");
        RunUntil(machine, "bytes long", seconds: 60);
        Type(machine, "E");
        RunUntil(machine, "Command: E(dit, R(un, F(ile", seconds: 30);

        Type(machine, "C");
        RunUntil(machine, "Compile what text?", seconds: 60);
        Type(machine, "/PASCAL2/HELLO\r");
        RunUntil(machine, "To what codefile?", seconds: 10);
        Type(machine, "/PASCAL2/HELLO\r");
        RunUntil(machine, "Listing file", seconds: 10);
        Type(machine, "/PASCAL2/HELLO.LST.TEXT\r");
        RunUntil(machine, "Smallest available space", seconds: 120);
        RunUntil(machine, "Command: E(dit, R(un, F(ile", seconds: 30);
        machine.Run(TimeSpan.FromSeconds(1));

        Type(machine, "X");
        RunUntil(machine, "Execute what file?", seconds: 30);
        Type(machine, "/PASCAL2/HELLO\r");
        RunUntil(machine, "\n21 ", seconds: 60);
        Screen(machine).Should().MatchRegex(@"\n7 +\n14 +\n21 ");

        WozDisk disk = machine.Drives[1].Eject() ?? throw new InvalidOperationException("The disk left the drive.");
        SosVolume volume = SosVolume.Read(SectorDiskReader.Read(disk, proDosOrder: false), proDosOrder: false);
        PascalSegment segment = PascalCodeFile.Read(volume.ReadFile("HELLO.CODE")).Segments.Should().ContainSingle().Subject;
        segment.Name.Should().Be("HELLO");
        segment.Version.Should().Be(4);
        string[] show = [.. PcodeDisassembler.Disassemble(segment, segment.Procedure(2)!).Select(instruction => instruction.ToString())];
        show.Should().StartWith(["LOD 2, 3", "SLDL1", "SLDC 7", "MPI"]);

        string listing = PascalTextFile.Read(volume.ReadFile("HELLO.LST.TEXT"));
        listing.Should().Contain("    9   1    1:2    13 SHOW(I)");
    }

    private static Apple3Machine Boot(params string[] disks)
    {
        Apple3Machine machine = Apple3MachineTests.Machine();
        for (int drive = 0; drive < disks.Length; drive++)
        {
            string path = Path.Join(SosVolumeTests.Disks, disks[drive]);
            if (!File.Exists(path))
            {
                Assert.Inconclusive($"Set RETROCORE_APPLE3_DISKS to a folder with {disks[drive]}.");
            }

            // A converted image is read-only; a writable copy takes the Editor's and Compiler's writes.
            WozDisk media = SectorDiskConverter.Convert(File.ReadAllBytes(path), proDosOrder: false);
            machine.Drives[drive].Insert(WozDisk.Load(media.Export(), writable: true), disks[drive], "DSK");
        }

        return machine;
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
