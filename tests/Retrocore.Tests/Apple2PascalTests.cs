// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug;
using Retrocore.Machines.Apple2;
using Retrocore.Media;
using Retrocore.Pascal;

namespace Retrocore.Tests;

/// <summary>
///  Apple Pascal 1.0 (on the II Plus), 1.1 and 1.2 on a 64K Apple II Plus (with the language card) and an enhanced
///  IIe, and 1.3 on a 128K enhanced IIe, from Apple's disks:
///  each boots from APPLE1, its Filer lists the disk, and a program is edited, compiled with a listing, and run.
/// </summary>
/// <remarks>
///  <para>
///   The disks (<c>UCSD Pascal 1.0_1.DSK</c>, <c>1.1_1.dsk</c>, <c>1.2_1.DSK</c> and <c>1.3_1.DSK</c>, APPLE1, and the APPLE2 beside each,
///   with the Compiler) are in <c>RETROCORE_APPLE2_PASCAL_DISKS</c>; the ROMs are the SDK's.
///   The IIe shows lowercase, so the screen is compared in capitals. The Editor is typed a key at a time, at a typist's
///   pace: keys queued faster can be lost while it scrolls.
///  </para>
/// </remarks>
[TestClass]
public class Apple2PascalTests
{
    private static readonly string s_inputs = Path.Join(AppContext.BaseDirectory, "Inputs");

    /// <summary>
    ///  Pascal boots to its command line, and the Filer lists APPLE1.
    /// </summary>
    /// <param name="model">The model.</param>
    /// <param name="version">Apple Pascal's version, 1.0 to 1.3.</param>
    [TestMethod]
    [DataRow(Apple2Model.IIPlus, "1.0")]
    [DataRow(Apple2Model.IIPlus, "1.1")]
    [DataRow(Apple2Model.IIPlus, "1.2")]
    [DataRow(Apple2Model.IIeEnhanced, "1.1")]
    [DataRow(Apple2Model.IIeEnhanced, "1.2")]
    [DataRow(Apple2Model.IIeEnhanced, "1.3")]
    public void PascalBootsAndTheFilerListsItsDisk(Apple2Model model, string version)
    {
        Apple2Machine machine = Boot(model, version);
        RunUntil(machine, Welcome(version), seconds: 30);
        Type(machine, "F");
        RunUntil(machine, "FILER:", seconds: 20);
        Type(machine, "L");
        RunUntil(machine, "DIR LISTING OF", seconds: 10, orElse: "?");
        Type(machine, "*\r");
        RunUntil(machine, "FILES", seconds: 20);
        Screen(machine).Should().Contain("SYSTEM.APPLE");
    }

    /// <summary>
    ///  A program typed into the Editor, kept as the workfile, compiles with the listing it asks for and runs, and
    ///  its code file and listing read back from the disk.
    /// </summary>
    /// <param name="model">The model.</param>
    /// <param name="version">Apple Pascal's version, 1.0 to 1.3.</param>
    [TestMethod]
    [DataRow(Apple2Model.IIPlus, "1.0")]
    [DataRow(Apple2Model.IIPlus, "1.1")]
    [DataRow(Apple2Model.IIPlus, "1.2")]
    [DataRow(Apple2Model.IIeEnhanced, "1.1")]
    [DataRow(Apple2Model.IIeEnhanced, "1.2")]
    [DataRow(Apple2Model.IIeEnhanced, "1.3")]
    public void PascalCompilesAndRunsAProgram(Apple2Model model, string version)
    {
        Apple2Machine machine = Boot(model, version);
        RunUntil(machine, Welcome(version), seconds: 30);
        EditHello(machine, version);
        Run(machine, version);
        RunUntil(machine, version == "1.0" ? "SYSTEM.WRK" : "RUNNING...", seconds: 60);
        RunUntil(machine, "\n21 ", seconds: 20);
        Screen(machine).Should().MatchRegex(@"\n7 +\n14 +\n21 ");
        if (version != "1.0")
        {
            Screen(machine).Should().Contain(model == Apple2Model.IIPlus ? "RUNNING" : "Running", "the IIe shows lowercase");
        }

        WozDisk disk = machine.Drives[0].Eject() ?? throw new InvalidOperationException("The disk left the drive.");
        PascalVolume volume = PascalVolume.Read(SectorDiskReader.Read(disk, proDosOrder: false), proDosOrder: false);
        PascalSegment segment = PascalCodeFile.Read(volume.ReadFile("SYSTEM.WRK.CODE")).Segments.Should().ContainSingle().Subject;
        segment.Name.Should().Be("HELLO");
        segment.Version.Should().Be(version switch { "1.0" => 1, "1.1" => 2, "1.2" => 5, _ => 6 });
        PcodeDisassembler.Disassemble(segment, segment.Procedures.Single(procedure => procedure.Index == 2)).Select(instruction => instruction.ToString())
            .Should().StartWith(["LOD 2, 3", "SLDL1", "SLDC 7", "MPI"]);

        if (version != "1.0")
        {
            PascalTextFile.Read(volume.ReadFile("HELLO.LST.TEXT")).Should().MatchRegex(@" 1:2 +\d+ SHOW\(I\)");
        }
    }

    /// <summary>
    ///  At the interpreter's fetch in a procedure of a running program, the p-machine's frames read as the procedure,
    ///  its caller in the program, and the system below them.
    /// </summary>
    /// <param name="model">The model.</param>
    /// <param name="version">Apple Pascal's version, 1.0 to 1.3.</param>
    [TestMethod]
    [DataRow(Apple2Model.IIPlus, "1.0")]
    [DataRow(Apple2Model.IIPlus, "1.1")]
    [DataRow(Apple2Model.IIPlus, "1.2")]
    [DataRow(Apple2Model.IIeEnhanced, "1.1")]
    [DataRow(Apple2Model.IIeEnhanced, "1.2")]
    [DataRow(Apple2Model.IIeEnhanced, "1.3")]
    public void FramesReadFromTheMarkStack(Apple2Model model, string version)
    {
        Apple2Machine machine = Boot(model, version);
        RunUntil(machine, Welcome(version), seconds: 30);
        EditHello(machine, version);
        Run(machine, version);
        IPascalMemory memory = new Retrocore.Debug.Apple2PascalMemory(machine.Bus);
        ushort? fetch = null;
        PascalFrame? top = null;
        for (long step = 0; step < 50_000_000 && top is not { SegmentNumber: 1, Procedure: 2 }; step++)
        {
            machine.StepInstruction();
            ushort pc = machine.Processor.Registers.ProgramCounter;
            fetch ??= PascalInterpreter.IsFetch(machine.Bus.Peek, pc) ? pc : null;
            if (pc == fetch) { top = PascalMachine.Top(memory, Interpreter(machine, pc)); }
        }

        fetch.Should().NotBeNull();
        top.Should().NotBeNull();
        IReadOnlyList<PascalFrame> frames = PascalMachine.Frames(memory, Interpreter(machine, fetch.GetValueOrDefault()));
        frames.Select(frame => (frame.SegmentNumber, frame.Procedure)).Should().StartWith([(1, 2), (1, 1)]);
        frames[0].Offset.Should().Be(0);
        PascalMachine.Word(memory, frames[0].Local(1)).Should().Be(1, "N is 1 on the first call");
        frames[^1].SegmentNumber.Should().Be(0);
    }

    // The interpreter at its fetch: 1.3 on a 128K IIe reads its code from the auxiliary 64K there.
    private static PascalInterpreter Interpreter(Apple2Machine machine, ushort fetch) =>
        new("II", fetch, 0, Extended: false, CodeBank: (machine.Bus.Switches & Apple2Switches.RamRead) != 0 ? (byte)1 : (byte)0);

    // Types HELLO into the Editor, asking for a listing, and keeps it as the workfile, ending at the command line.
    private static void EditHello(Apple2Machine machine, string version)
    {
        // Apple Pascal 1.0's APPLE1 comes with a workfile, which the Filer's N(ew) throws away.
        if (Screen(machine).Contains("PASCAL  SYSTEM  II.1", StringComparison.OrdinalIgnoreCase))
        {
            Type(machine, "F");
            RunUntil(machine, "FILER:", seconds: 20);
            Type(machine, "N");
            RunUntil(machine, "THROW AWAY", seconds: 10);
            Type(machine, "Y");
            RunUntil(machine, "WORKFILE CLEARED", seconds: 10);
            Type(machine, "Q");
            RunUntil(machine, "COMMAND: E(DIT", seconds: 20);
            machine.Run(cycles: 1_020_480);
        }

        Type(machine, "E");
        // 1.3's Editor asks for a file where the others say there is no workfile; RETURN starts a new one either way.
        RunUntil(machine, "NO WORKFILE IS PRESENT", seconds: 20, orElse: "EDIT WHAT FILE?");
        machine.Run(cycles: 204_096);
        Type(machine, "\r");
        RunUntil(machine, ">EDIT:", seconds: 10);
        Type(machine, "I");
        RunUntil(machine, ">INSERT:", seconds: 10);
        string[] lines =
        [
            "(*$L APPLE1:HELLO.LST.TEXT*)", "PROGRAM HELLO;", "VAR I: INTEGER;", "PROCEDURE SHOW(N: INTEGER);", "BEGIN",
            "WRITELN(N*7)", "END;", "BEGIN", "FOR I := 1 TO 3 DO", "SHOW(I)", "END."
        ];

        // Apple Pascal 1.0's compiler leaves the code file open, all the disk's free space and undated, when it also
        // writes a listing, so 1.0 gets none.
        foreach (string line in version == "1.0" ? lines[1..] : lines)
        {
            // A key at a time, at the pace the debugger pastes: 1.3's Editor loses keys queued faster.
            foreach (char key in line + "\r")
            {
                Type(machine, key.ToString());
                machine.Run(cycles: 30_000);
            }

            RunUntil(machine, line, seconds: 10);
            machine.Run(cycles: 204_096);
        }

        // CONTROL-C takes the place of any key still waiting, so it goes alone.
        Type(machine, "\u0003");
        RunUntil(machine, ">EDIT:", seconds: 10);
        Type(machine, "Q");
        RunUntil(machine, "U(PDATE ", seconds: 10);
        Type(machine, "U");

        // 1.3's Editor writes the workfile and stays in its Quit menu, which E(xit) leaves.
        if (version == "1.3")
        {
            RunUntil(machine, "BYTES LONG", seconds: 20);
            Type(machine, "E");
        }

        // 1.3's command line starts with F(ile, the others' with E(dit.
        RunUntil(machine, "COMMAND: ", seconds: 20);
        machine.Run(cycles: 1_020_480);
    }

    // Runs the workfile: 1.1 to 1.3 compile it first, and 1.0 is told to.
    private static void Run(Apple2Machine machine, string version)
    {
        if (version == "1.0")
        {
            Type(machine, "C");
            RunUntil(machine, "SMALLEST AVAILABLE SPACE", seconds: 60);
            RunUntil(machine, "COMMAND: E(DIT", seconds: 30);
            machine.Run(cycles: 1_020_480);

            // 1.0's R(un) does not find the code the C(ompile) before it wrote, so X(ecute) names it.
            Type(machine, "X");
            RunUntil(machine, "EXECUTE WHAT FILE", seconds: 30);
            Type(machine, "SYSTEM.WRK\r");
            return;
        }

        Type(machine, "R");

        // 1.3's Compiler asks for a listing even with $L in the program.
        if (version == "1.3")
        {
            RunUntil(machine, "LISTING FILE", seconds: 30);
            machine.Run(cycles: 204_096);
            Type(machine, "APPLE1:HELLO.LST.TEXT\r");
        }
    }

    // What the system says once it has booted: 1.0 names only UCSD Pascal.
    private static string Welcome(string version) =>
        version == "1.0" ? "U.C.S.D.  PASCAL  SYSTEM  II.1" : $"WELCOME APPLE1, TO APPLE II PASCAL {version}";

    private static Apple2Machine Boot(Apple2Model model, string version)
    {
        // Apple Pascal 1.0's and 1.2's images are named in capitals.
        string extension = version == "1.1" ? "dsk" : "DSK";
        string apple1 = $"UCSD Pascal {version}_1.{extension}";
        string apple2 = $"UCSD Pascal {version}_2.{extension}";
        string path = Path.Join(PascalMediaTests.Apple2Disks, apple1);
        string tools = Path.Join(PascalMediaTests.Apple2Disks, apple2);
        if (!File.Exists(path) || !File.Exists(tools))
        {
            Assert.Inconclusive($"Set RETROCORE_APPLE2_PASCAL_DISKS to a folder with {apple1} and {apple2}.");
        }

        Apple2Machine machine = new(model, SdkModules.BuildRoms(model, s_inputs, autostart: true));
        machine.Bus.InstallDiskII(slot: 6, SdkModules.BuildDiskII(16, s_inputs));
        if (!model.IsIIe()) { machine.Bus.InstallLanguageCard(); }

        // A converted image is read-only; a writable copy takes the workfile, the code and the listing.
        WozDisk media = SectorDiskConverter.Convert(File.ReadAllBytes(path), proDosOrder: false);
        machine.Drives[0].Insert(WozDisk.Load(media.Export(), writable: true), apple1, "DSK");
        machine.Drives[1].Insert(SectorDiskConverter.Convert(File.ReadAllBytes(tools), proDosOrder: false), apple2, "DSK");
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
            if (screen.Contains(text, StringComparison.OrdinalIgnoreCase) || (orElse is not null && screen.Contains(orElse, StringComparison.OrdinalIgnoreCase)))
            {
                return;
            }

            machine.Run(cycles: 102_048);
        }

        Screen(machine).Should().ContainEquivalentOf(text);
    }
}
