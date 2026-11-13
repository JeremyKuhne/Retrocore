// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug;
using Retrocore.Machines.Apple2;
using Retrocore.Media;
using Retrocore.Pascal;

namespace Retrocore.Tests;

/// <summary>
///  Apple Pascal 1.1 on a 64K Apple II Plus, from Apple's disks: it boots from APPLE1 with the language card, its
///  Filer lists the disk, and a program is edited, compiled with a listing, and run.
/// </summary>
/// <remarks>
///  <para>
///   The disks (<c>UCSD Pascal 1.1_1.dsk</c>, APPLE1, and <c>1.1_2.dsk</c>, APPLE2 with the Compiler) are in <c>RETROCORE_APPLE2_PASCAL_DISKS</c>; the ROMs are the
///   SDK's. The Editor is typed a line at a time: keys queued faster than a typist can lose some while it scrolls.
///  </para>
/// </remarks>
[TestClass]
public class Apple2PascalTests
{
    private const string Apple1 = "UCSD Pascal 1.1_1.dsk";
    private const string Apple2 = "UCSD Pascal 1.1_2.dsk";
    private static readonly string s_inputs = Path.Join(AppContext.BaseDirectory, "Inputs");

    /// <summary>
    ///  Pascal boots to its command line, and the Filer lists APPLE1.
    /// </summary>
    [TestMethod]
    public void PascalBootsAndTheFilerListsItsDisk()
    {
        Apple2Machine machine = Boot();
        RunUntil(machine, "WELCOME APPLE1, TO APPLE II PASCAL 1.1", seconds: 30);
        Type(machine, "F");
        RunUntil(machine, "FILER: G, S, N, L", seconds: 20);
        Type(machine, "L");
        RunUntil(machine, "DIR LISTING OF", seconds: 10, orElse: "?");
        Type(machine, "*\r");
        RunUntil(machine, "8/8 FILES", seconds: 20);
        Screen(machine).Should().Contain("SYSTEM.APPLE");
    }

    /// <summary>
    ///  A program typed into the Editor, kept as the workfile, compiles with the listing it asks for and runs, and
    ///  its code file and listing read back from the disk.
    /// </summary>
    [TestMethod]
    public void PascalCompilesAndRunsAProgram()
    {
        Apple2Machine machine = Boot();
        RunUntil(machine, "WELCOME APPLE1, TO APPLE II PASCAL 1.1", seconds: 30);
        EditHello(machine);
        Type(machine, "R");
        RunUntil(machine, "RUNNING...", seconds: 60);
        RunUntil(machine, "\n21 ", seconds: 20);
        Screen(machine).Should().MatchRegex(@"\n7 +\n14 +\n21 ");

        WozDisk disk = machine.Drives[0].Eject() ?? throw new InvalidOperationException("The disk left the drive.");
        PascalVolume volume = PascalVolume.Read(SectorDiskReader.Read(disk, proDosOrder: false), proDosOrder: false);
        PascalSegment segment = PascalCodeFile.Read(volume.ReadFile("SYSTEM.WRK.CODE")).Segments.Should().ContainSingle().Subject;
        segment.Name.Should().Be("HELLO");
        segment.Version.Should().Be(2);
        PcodeDisassembler.Disassemble(segment, segment.Procedures.Single(procedure => procedure.Index == 2)).Select(instruction => instruction.ToString())
            .Should().StartWith(["LOD 2, 3", "SLDL1", "SLDC 7", "MPI"]);

        PascalTextFile.Read(volume.ReadFile("HELLO.LST.TEXT")).Should().MatchRegex(@" 1:2 +\d+ SHOW\(I\)");
    }

    /// <summary>
    ///  At the interpreter's fetch in a procedure of a running program, the p-machine's frames read as the procedure,
    ///  its caller in the program, and the system below them.
    /// </summary>
    [TestMethod]
    public void FramesReadFromTheMarkStack()
    {
        Apple2Machine machine = Boot();
        RunUntil(machine, "WELCOME APPLE1, TO APPLE II PASCAL 1.1", seconds: 30);
        EditHello(machine);
        Type(machine, "R");
        IPascalMemory memory = new Retrocore.Debug.Apple2PascalMemory(machine.Bus);
        ushort? fetch = null;
        PascalFrame? top = null;
        for (long step = 0; step < 50_000_000 && top is not { SegmentNumber: 1, Procedure: 2 }; step++)
        {
            machine.StepInstruction();
            ushort pc = machine.Processor.Registers.ProgramCounter;
            fetch ??= PascalInterpreter.IsFetch(machine.Bus.Peek, pc) ? pc : null;
            if (pc == fetch) { top = PascalMachine.Top(memory, new PascalInterpreter("II", pc, 0, Extended: false)); }
        }

        fetch.Should().NotBeNull();
        top.Should().NotBeNull();
        IReadOnlyList<PascalFrame> frames = PascalMachine.Frames(memory, new PascalInterpreter("II", fetch.GetValueOrDefault(), 0, Extended: false));
        frames.Select(frame => (frame.SegmentNumber, frame.Procedure)).Should().StartWith([(1, 2), (1, 1)]);
        frames[0].Offset.Should().Be(0);
        PascalMachine.Word(memory, frames[0].Local(1)).Should().Be(1, "N is 1 on the first call");
        frames[^1].SegmentNumber.Should().Be(0);
    }

    // Types HELLO into the Editor, asking for a listing, and keeps it as the workfile, ending at the command line.
    private static void EditHello(Apple2Machine machine)
    {
        Type(machine, "E");
        RunUntil(machine, "NO WORKFILE IS PRESENT", seconds: 20);
        Type(machine, "\r");
        RunUntil(machine, ">EDIT: A(DJST", seconds: 10);
        Type(machine, "I");
        RunUntil(machine, ">INSERT:", seconds: 10);
        string[] lines =
        [
            "(*$L APPLE1:HELLO.LST.TEXT*)", "PROGRAM HELLO;", "VAR I: INTEGER;", "PROCEDURE SHOW(N: INTEGER);", "BEGIN",
            "WRITELN(N*7)", "END;", "BEGIN", "FOR I := 1 TO 3 DO", "SHOW(I)", "END."
        ];

        foreach (string line in lines)
        {
            Type(machine, line + "\r");
            machine.Run(cycles: 512_000);
        }

        // CONTROL-C takes the place of any key still waiting, so it goes alone.
        Type(machine, "\u0003");
        RunUntil(machine, ">EDIT: A(DJST", seconds: 10);
        Type(machine, "Q");
        RunUntil(machine, "U(PDATE THE WORKFILE", seconds: 10);
        Type(machine, "U");
        RunUntil(machine, "COMMAND: E(DIT, R(UN", seconds: 20);
        machine.Run(cycles: 1_020_480);
    }

    private static Apple2Machine Boot()
    {
        string path = Path.Join(PascalMediaTests.Apple2Disks, Apple1);
        string tools = Path.Join(PascalMediaTests.Apple2Disks, Apple2);
        if (!File.Exists(path) || !File.Exists(tools))
        {
            Assert.Inconclusive($"Set RETROCORE_APPLE2_PASCAL_DISKS to a folder with {Apple1} and {Apple2}.");
        }

        Apple2Machine machine = new(Apple2Model.IIPlus, SdkModules.BuildRoms(Apple2Model.IIPlus, s_inputs, autostart: true));
        machine.Bus.InstallDiskII(slot: 6, SdkModules.BuildDiskII(16, s_inputs));
        machine.Bus.InstallLanguageCard();

        // A converted image is read-only; a writable copy takes the workfile, the code and the listing.
        WozDisk media = SectorDiskConverter.Convert(File.ReadAllBytes(path), proDosOrder: false);
        machine.Drives[0].Insert(WozDisk.Load(media.Export(), writable: true), Apple1, "DSK");
        machine.Drives[1].Insert(SectorDiskConverter.Convert(File.ReadAllBytes(tools), proDosOrder: false), Apple2, "DSK");
        machine.Bus.ResetSwitches();
        machine.Processor.Reset();
        return machine;
    }

    private static void Type(Apple2Machine machine, string keys)
    {
        foreach (char key in keys) { machine.Bus.QueueKey((byte)key); }
    }

    private static string Screen(Apple2Machine machine) => string.Join(
        "\n",
        Enumerable.Range(0, 24).Select(row => new string([.. Enumerable.Range(0, 40)
            .Select(column => (char)(machine.Bus.TextByte(row, column) & 0x7F))
            .Select(character => character < 32 ? (char)(character + 64) : character)])));

    private static void RunUntil(Apple2Machine machine, string text, int seconds, string? orElse = null)
    {
        for (int tenth = 0; tenth < seconds * 10; tenth++)
        {
            string screen = Screen(machine);
            if (screen.Contains(text, StringComparison.Ordinal) || (orElse is not null && screen.Contains(orElse, StringComparison.Ordinal)))
            {
                return;
            }

            machine.Run(cycles: 102_048);
        }

        Screen(machine).Should().Contain(text);
    }
}
