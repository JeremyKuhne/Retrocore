// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug.Project;
using Retrocore.Machines.Apple1;
using Retrocore.Media;
using System.Text.Json.Nodes;

namespace Retrocore.Tests;

/// <summary>
///  Each environment that builds writes its own file and image beside the binary, and they load on the machine as a
///  user would load them: the <c>wozmon</c> hex typed in at the Woz Monitor, and its ACI tape read with <c>C100R</c>.
/// </summary>
[TestClass]
public sealed class ProjectEnvironmentTests
{
    // A program that writes HI through the Woz Monitor's ECHO and goes back to its command line.
    private const string Hello = """
        .include <machine.inc>
        .include <environment.inc>

        Start:
            lda #'H' | KEY_BIT
            jsr CharacterOut
            lda #'I' | KEY_BIT
            jsr CharacterOut
            jmp MonitorCommandLine
        """;

    private string _folder = "";

    /// <summary>
    ///  Gets each test a folder of its own.
    /// </summary>
    [TestInitialize]
    public void Initialize()
    {
        _folder = Path.Join(Path.GetTempPath(), "retrocore-environment-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(_folder);
    }

    /// <summary>
    ///  Removes the test's folder.
    /// </summary>
    [TestCleanup]
    public void Cleanup()
    {
        if (Directory.Exists(_folder)) { Directory.Delete(_folder, recursive: true); }
    }

    /// <summary>
    ///  A <c>wozmon</c> target builds at the map's load address and writes its hex, which typed in at the Woz Monitor
    ///  stores the binary's bytes and runs it at its entry, and its ACI tape, which the cassette interface reads back
    ///  into the same bytes. The build record names both.
    /// </summary>
    [TestMethod]
    public void WozmonHexTypesInAndTapeReadsBack()
    {
        Write("retrocore.json", """
            { "sdk": "1", "name": "hello", "cpu": "6502", "sources": ["hello.s"],
              "targets": { "woz": { "machine": "apple1", "environment": "wozmon" } } }
            """);

        Write("hello.s", Hello);
        TargetBuild build = ProjectBuild.Build(RetrocoreProject.Load(_folder).Target("woz"));
        (int start, byte[] bytes) = ProjectBuild.Image(build);
        start.Should().Be(0x0300);
        build.Entry.Should().Be(0x0300);

        string output = Path.Join(_folder, "artifacts", "woz");
        build.Media.Should().Be(new TargetMedia(
            Path.Join(output, "hello.hex"),
            "Woz Monitor hex",
            Path.Join(output, "hello.wav"),
            "ACI tape",
            $"type it at the Woz Monitor's prompt, or play the tape after C100R and 0300.{0x300 + bytes.Length - 1:X4}R, then 0300R"));

        string hex = File.ReadAllText(Path.Join(output, "hello.hex"));
        hex.Should().Be(WozMonitorHex.ToText(bytes, 0x0300, entry: 0x0300));

        // Typed in, line by line, the hex stores the program and its last line runs it.
        Apple1Machine typed = Apple1MachineTests.Boot();
        foreach (string line in hex.Split(WozMonitorHex.NewLine, StringSplitOptions.RemoveEmptyEntries))
        {
            Apple1MachineTests.TypeLine(typed, line);
        }

        Bytes(typed, 0x0300, bytes.Length).Should().Equal(bytes);
        Enumerable.Range(0, Apple1Terminal.Rows).Select(row => typed.Terminal.Line(row).TrimEnd())
            .Should().Contain("0300: A9HI", "R examines the entry, then the program writes HI");

        // The tape reads back into the same bytes.
        Apple1Machine taped = Apple1MachineTests.Boot();
        Apple1CassetteDrive drive = taped.CassetteDrive ?? throw new AssertFailedException("No cassette interface.");
        drive.Play(Apple1Tape.FromWave(File.ReadAllBytes(Path.Join(output, "hello.wav"))), "hello.wav");
        Apple1MachineTests.TypeLine(taped, "C100R");
        Apple1MachineTests.TypeLine(taped, $"0300.{0x300 + bytes.Length - 1:X4}R", seconds: 20);
        Bytes(taped, 0x0300, bytes.Length).Should().Equal(bytes);

        JsonNode record = JsonNode.Parse(File.ReadAllText(Path.Join(_folder, "obj", "woz", "build.json")))
            ?? throw new AssertFailedException("No build record.");

        ((string?)record["environment"]).Should().Be("wozmon");
        ((string?)record["file"]).Should().Be(Path.Join(output, "hello.hex"));
        ((string?)record["image"]).Should().Be(Path.Join(output, "hello.wav"));
    }

    /// <summary>
    ///  With <c>"image": false</c>, a <c>wozmon</c> target writes its hex and no tape, and deletes the tape an earlier
    ///  build wrote; a <c>bare</c> target writes nothing beyond its binary, and deletes the hex and tape a <c>wozmon</c>
    ///  build of it wrote.
    /// </summary>
    [TestMethod]
    public void ImageFalseLeavesTheTapeOut()
    {
        void Project(string woz) => Write("retrocore.json", $$"""
            { "sdk": "1", "name": "hello", "cpu": "6502", "sources": ["hello.s"],
              "targets": { "woz": {{woz}} } }
            """);

        string output = Path.Join(_folder, "artifacts", "woz");
        Write("hello.s", Hello.Replace(".include <environment.inc>", "", StringComparison.Ordinal));
        Project("""{ "machine": "apple1", "environment": "wozmon" }""");
        ProjectBuild.Build(RetrocoreProject.Load(_folder).Target("woz"));
        File.Exists(Path.Join(output, "hello.wav")).Should().BeTrue();

        Project("""{ "machine": "apple1", "environment": "wozmon", "image": false }""");
        TargetBuild woz = ProjectBuild.Build(RetrocoreProject.Load(_folder).Target("woz"));
        woz.Media.File.Should().Be(Path.Join(output, "hello.hex"));
        (woz.Media.Image, woz.Media.ImageKind).Should().Be((null, null));
        woz.Media.Note.Should().Be("type it at the Woz Monitor's prompt");
        File.Exists(Path.Join(output, "hello.wav")).Should().BeFalse("the earlier build's tape goes");

        Project("""{ "machine": "apple1", "environment": "wozmon" }""");
        ProjectBuild.Build(RetrocoreProject.Load(_folder).Target("woz"));
        Project("""{ "machine": "apple1", "environment": "bare" }""");
        ProjectBuild.Build(RetrocoreProject.Load(_folder).Target("woz")).Media.Should().Be(TargetMedia.None);
        Directory.GetFiles(output).Select(Path.GetFileName).Should().BeEquivalentTo("hello.bin", "hello.dbg", "hello.map");
    }

    /// <summary>
    ///  A <c>dos33</c> target writes a DOS 3.3 disk: DOS on tracks 0 to 2, <c>HELLO</c> in AppleSoft, which BLOADs the
    ///  program and CALLs its entry, the program as a B file at its load address named for the project, and its
    ///  files, each a B file at its address. With the entry at the first byte, HELLO BRUNs it.
    /// </summary>
    [TestMethod]
    public void Dos33WritesItsDisk()
    {
        Write("retrocore.json", """
            { "sdk": "1", "name": "my-game", "cpu": "6502", "sources": ["main.s"], "entry": "START",
              "targets": { "dos": { "machine": "apple2-iiplus", "environment": "dos33",
                "files": ["data.bin", { "path": "${obj}/extra.bin", "name": "EXTRA DATA", "address": "$4000" }] } } }
            """);

        Write("main.s", "DATA:\n    .byte 1\nSTART:\n    rts\n");
        Write("data.bin", "AB");
        Write("obj/extra.bin", "XYZ");
        TargetBuild build = ProjectBuild.Build(RetrocoreProject.Load(_folder).Target("dos"));
        string disk = Path.Join(_folder, "artifacts", "dos", "my-game.dsk");
        build.Media.Should().Be(new TargetMedia(File: null, FileKind: null, disk, "DOS 3.3 disk", "boot the disk, and HELLO starts MYGAME"));

        List<DosFile> files = [.. DosDisk.ReadFiles(File.ReadAllBytes(disk))];
        files.Select(file => (file.Name, file.Type)).Should().Equal(
            ("HELLO", DosFileType.AppleSoft), ("MYGAME", DosFileType.Binary), ("DATA.BIN", DosFileType.Binary), ("EXTRA DATA", DosFileType.Binary));

        files[1].TryGetBinary(out int address, out ReadOnlyMemory<byte> data).Should().BeTrue();
        (address, data.ToArray()).Should().BeEquivalentTo((0x6000, new byte[] { 1, 0x60 }));
        files[2].TryGetBinary(out address, out data).Should().BeTrue();
        (address, data.ToArray()).Should().BeEquivalentTo((0, "AB"u8.ToArray()));
        files[3].TryGetBinary(out address, out data).Should().BeTrue();
        (address, data.ToArray()).Should().BeEquivalentTo((0x4000, "XYZ"u8.ToArray()));
        files[0].TryGetProgram(out ReadOnlyMemory<byte> hello).Should().BeTrue();
        Basic.BasicProgram.FromImage(Basic.BasicDialect.AppleSoft, hello.Span).ToText().Should().Contain("CHR$(4);\"BLOAD MYGAME\": CALL 24577");

        Write("retrocore.json", """
            { "sdk": "1", "name": "my-game", "cpu": "6502", "sources": ["main.s"],
              "targets": { "dos": { "machine": "apple2-iiplus", "environment": "dos33", "image": false } } }
            """);

        TargetBuild first = ProjectBuild.Build(RetrocoreProject.Load(_folder).Target("dos"));
        (first.Media.Image, first.Media.Note).Should().Be((null, "the binary is the B file MYGAME, which loads at its first address"));
        File.Exists(disk).Should().BeFalse("the earlier build's disk goes");
    }

    /// <summary>
    ///  A file whose name DOS 3.3 cannot take, or that another file on the disk has, fails the build naming it, as does a
    ///  project whose program would be named HELLO.
    /// </summary>
    [TestMethod]
    public void Dos33RefusesBadNames()
    {
        string Fails(string files)
        {
            Write("retrocore.json", $$"""
                { "sdk": "1", "name": "game", "cpu": "6502", "sources": ["main.s"],
                  "targets": { "dos": { "machine": "apple2-iiplus", "environment": "dos33", "files": {{files}} } } }
                """);

            Action build = () => ProjectBuild.Build(RetrocoreProject.Load(_folder).Target("dos"));
            return build.Should().Throw<ProjectException>().Which.Message;
        }

        Write("main.s", "rts\n");
        Write("a,b.bin", "1");
        Write("1st.bin", "1");
        Write("data.bin", "1");
        Fails("""["a,b.bin"]""").Should().EndWith("'A,B.BIN' is not a DOS 3.3 file name, 1 to 30 characters from a capital letter with no comma; give its file a 'name'.");
        Fails("""["1st.bin"]""").Should().Contain("'1ST.BIN' is not a DOS 3.3 file name");
        Fails("""[{ "path": "data.bin", "name": "GAME" }]""").Should().EndWith("two files on the disk are named GAME.");
        Fails("""[{ "path": "data.bin", "name": "HELLO" }]""").Should().EndWith("two files on the disk are named HELLO.");

        Write("retrocore.json", """
            { "sdk": "1", "name": "hello", "cpu": "6502", "sources": ["main.s"],
              "targets": { "dos": { "machine": "apple2-iiplus", "environment": "dos33" } } }
            """);

        Action hello = () => ProjectBuild.Build(RetrocoreProject.Load(_folder).Target("dos"));
        hello.Should().Throw<ProjectException>().WithMessage("*the program would be HELLO on the disk, the name of the program that starts it; give the project another 'name'.");
    }

    /// <summary>
    ///  <c>&lt;environment.inc&gt;</c> for <c>wozmon</c> refuses a target of another environment.
    /// </summary>
    [TestMethod]
    public void WozmonHeaderIsForWozmonTargets()
    {
        Write("retrocore.json", """
            { "sdk": "1", "name": "hello", "cpu": "6502", "sources": ["hello.s"],
              "targets": { "bare": { "machine": "apple1", "environment": "bare" } } }
            """);

        Write("hello.s", ".include <environments/wozmon/environment.inc>\nrts");
        Action build = () => ProjectBuild.Build(RetrocoreProject.Load(_folder).Target("bare"));
        build.Should().Throw<ProjectException>().WithMessage("*environment.inc for wozmon is for targets whose environment is wozmon.*");
    }

    private static byte[] Bytes(Apple1Machine machine, int address, int count) =>
        [.. Enumerable.Range(address, count).Select(at => machine.Bus.Peek((ushort)at))];

    private void Write(string path, string text)
    {
        string file = Path.Join(_folder, path);
        Directory.CreateDirectory(Path.GetDirectoryName(file) ?? _folder);
        File.WriteAllText(file, text);
    }
}
