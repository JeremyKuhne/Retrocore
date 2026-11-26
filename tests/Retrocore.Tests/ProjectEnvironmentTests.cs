// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug.Project;
using Retrocore.Machines.Apple1;
using Retrocore.Media;
using Retrocore.Media.Acorn;
using Retrocore.Media.Commodore;
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

        // With no entry, the first byte is the entry, and HELLO BRUNs the program.
        Write("retrocore.json", """
            { "sdk": "1", "name": "my-game", "cpu": "6502", "sources": ["main.s"],
              "targets": { "dos": { "machine": "apple2-iiplus", "environment": "dos33" } } }
            """);

        ProjectBuild.Build(RetrocoreProject.Load(_folder).Target("dos"));
        DosDisk.ReadFiles(File.ReadAllBytes(disk))[0].TryGetProgram(out hello).Should().BeTrue();
        Basic.BasicProgram.FromImage(Basic.BasicDialect.AppleSoft, hello.Span).ToText().Should().Contain("CHR$(4);\"BRUN MYGAME\"").And.NotContain("CALL");
    }

    /// <summary>
    ///  On the Apple II, HELLO is Integer BASIC's, its Ctrl-D in its string, and it CALLs an entry from <c>$8000</c>
    ///  as the negative number Integer BASIC takes for it.
    /// </summary>
    [TestMethod]
    public void Dos33HelloOnTheIIIsIntegerBasic()
    {
        Write("retrocore.json", """
            { "sdk": "1", "name": "game", "cpu": "6502", "sources": ["main.s"], "entry": "START",
              "targets": { "dos": { "machine": "apple2-ii", "environment": "dos33", "memoryMap": { "load": "$8000" } } } }
            """);

        Write("main.s", "DATA:\n    .byte 1\nSTART:\n    rts\n");
        ProjectBuild.Build(RetrocoreProject.Load(_folder).Target("dos"));
        DosFile hello = DosDisk.ReadFiles(File.ReadAllBytes(Path.Join(_folder, "artifacts", "dos", "game.dsk")))[0];
        hello.Type.Should().Be(DosFileType.IntegerBasic);
        hello.TryGetProgram(out ReadOnlyMemory<byte> program).Should().BeTrue();
        string text = Basic.BasicProgram.FromImage(Basic.BasicDialect.Integer, program.Span).ToText();
        text.Should().Contain("BLOAD GAME").And.Contain("CALL -32767");
        program.ToArray().Should().Contain(0x84, "Ctrl-D, with its high bit, starts the string");
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
    ///  A <c>dfs</c> target writes a DFS disk: its title the project's name, the program as <c>$.&lt;NAME&gt;</c> at its
    ///  load address running at its entry, its files at their addresses in their directories, and a <c>!BOOT</c> that
    ///  <c>*RUN</c>s the program, with the boot option to <c>*EXEC</c> it; and a UEF tape of the same files, each named
    ///  <c>D.NAME</c>, or <c>NAME</c> in <c>$</c>.
    /// </summary>
    [TestMethod]
    public void DfsWritesItsDiskAndTape()
    {
        Write("retrocore.json", """
            { "sdk": "1", "name": "adventure", "cpu": "6502", "sources": ["main.s"], "entry": "START",
              "targets": { "dfs": { "machine": "bbcb", "environment": "dfs",
                "files": ["data.bin", { "path": "${obj}/extra.bin", "name": "G.LEVEL1", "address": "$3000" }] } } }
            """);

        Write("main.s", "DATA:\n    .byte 1\nSTART:\n    rts\n");
        Write("data.bin", "AB");
        Write("obj/extra.bin", "XYZ");
        TargetBuild build = ProjectBuild.Build(RetrocoreProject.Load(_folder).Target("dfs"));
        string output = Path.Join(_folder, "artifacts", "dfs");
        build.Media.Should().Be(new TargetMedia(
            Path.Join(output, "adventure.uef"), "UEF tape, for *TAPE and *RUN", Path.Join(output, "adventure.ssd"), "DFS disk",
            "SHIFT-BREAK boots the disk, and !BOOT runs ADVENTU"));

        AcornDfsDisk disk = AcornDfsDisk.Read(File.ReadAllBytes(Path.Join(output, "adventure.ssd")));
        disk.Title.TrimEnd().Should().Be("ADVENTURE");
        disk.BootOption.Should().Be(AcornBootOption.Exec);
        AcornDfsFile program = disk.Find('$', "ADVENTU")?.File ?? throw new AssertFailedException("No program.");
        (program.LoadAddress, program.ExecutionAddress, program.Data).Should().BeEquivalentTo((0x1900u, 0x1901u, new byte[]
        {
            1, 0x60
        }));

        AcornDfsFile data = disk.Find('$', "DATA")?.File ?? throw new AssertFailedException("No DATA.");
        (data.LoadAddress, data.Data).Should().BeEquivalentTo((0u, "AB"u8.ToArray()));
        AcornDfsFile level = disk.Find('G', "LEVEL1")?.File ?? throw new AssertFailedException("No G.LEVEL1.");
        (level.LoadAddress, level.Data).Should().BeEquivalentTo((0x3000u, "XYZ"u8.ToArray()));
        System.Text.Encoding.ASCII.GetString(disk.Find('$', AcornDfsDisk.BootFileName)?.File.Data ?? []).Should().Be("*RUN ADVENTU\r");

        // The tape is the one the tape builder makes of the same files, each named with its directory but for $'s.
        AcornTape tape = UefFormat.Read(File.ReadAllBytes(Path.Join(output, "adventure.uef")));
        AcornTape expected = AcornTapeBuilder.Build(
        [
            new("ADVENTU", 0x1900, 0x1901, [1, 0x60]),
            new("DATA", 0, 0, "AB"u8.ToArray()),
            new("G.LEVEL1", 0x3000, 0, "XYZ"u8.ToArray())
        ]);

        tape.HalfCycles.Should().Equal(expected.HalfCycles);
    }

    /// <summary>
    ///  A file whose name the DFS cannot take, or that another file on the disk has in any case, fails the build naming
    ///  it, as does a file too long for the disk.
    /// </summary>
    [TestMethod]
    public void DfsRefusesBadNames()
    {
        string Fails(string files)
        {
            Write("retrocore.json", $$"""
                { "sdk": "1", "name": "game", "cpu": "6502", "sources": ["main.s"],
                  "targets": { "dfs": { "machine": "bbcb", "environment": "dfs", "files": {{files}} } } }
                """);

            Action build = () => ProjectBuild.Build(RetrocoreProject.Load(_folder).Target("dfs"));
            return build.Should().Throw<ProjectException>().Which.Message;
        }

        Write("main.s", "rts\n");
        Write("data.bin", "1");
        Fails("""[{ "path": "data.bin", "name": "TOOLONGNAME" }]""").Should().EndWith("'TOOLONGNAME' is not a DFS file name, D.NAME or NAME with 1 to 7 printable characters, none a space or . : \" # *; give its file a 'name'.");
        Fails("""[{ "path": "data.bin", "name": "GAME" }]""").Should().EndWith("two files on the disk are named $.GAME.");
        Fails("""[{ "path": "data.bin", "name": "!BOOT" }]""").Should().EndWith("two files on the disk are named $.!BOOT.");
        Fails("""[{ "path": "data.bin", "name": "g.LEVEL" }, { "path": "main.s", "name": "G.level" }]""").Should().EndWith("two files on the disk are named G.LEVEL.");

        Write("retrocore.json", """
            { "sdk": "1", "name": "game", "cpu": "6502", "sources": ["main.s"],
              "targets": { "dfs": { "machine": "bbcb", "environment": "dfs", "files": [{ "path": "data.bin", "address": "$FFFF" }] } } }
            """);

        File.WriteAllBytes(Path.Join(_folder, "data.bin"), new byte[0x40000]);
        Action big = () => ProjectBuild.Build(RetrocoreProject.Load(_folder).Target("dfs"));
        big.Should().Throw<ProjectException>().WithMessage("*its files do not fit on a DFS disk: *");
    }

    /// <summary>
    ///  A <c>basic</c> target writes its PRG: the load address <c>$0401</c>, BASIC's line that SYSes its entry, zeros to
    ///  its load address, <c>$0410</c>, then the program; the TAP tape of it; and a 4040 disk holding it under the
    ///  project's name. The tape is what a launch boots, unless the target's image boots the disk.
    /// </summary>
    [TestMethod]
    public void BasicWritesItsProgramTapeAndDisk()
    {
        void Project(string image) => Write("retrocore.json", $$"""
            { "sdk": "1", "name": "adventure", "cpu": "6502", "sources": ["main.s"], "entry": "START",
              "targets": { "pet": { "machine": "pet4032", "environment": "basic"{{image}} } } }
            """);

        Write("main.s", "DATA:\n    .byte 1\nSTART:\n    rts\n");
        Project("");
        TargetBuild build = ProjectBuild.Build(RetrocoreProject.Load(_folder).Target("pet"));
        string output = Path.Join(_folder, "artifacts", "pet");
        build.Media.Should().Be(new TargetMedia(
            Path.Join(output, "adventure.prg"), "PRG", Path.Join(output, "adventure.tap"), "PET tape (TAP)",
            "LOAD and RUN from the tape; the 4040 disk is adventure.d64"));

        byte[] prg = File.ReadAllBytes(Path.Join(output, "adventure.prg"));
        byte[] stub = PetSysProgram.Stub(0x0411);
        prg.AsSpan(0, stub.Length).ToArray().Should().Equal(stub);
        prg.AsSpan(stub.Length, 2 + 0x0410 - 0x0401 - stub.Length).ToArray().Should().OnlyContain(value => value == 0);
        prg[(2 + 0x0410 - 0x0401)..].Should().Equal(1, 0x60);

        File.ReadAllBytes(Path.Join(output, "adventure.tap")).Should().Equal(PetSysProgram.ToTap("ADVENTURE", prg));
        CbmDosDisk disk = CbmDosDisk.FromD64(File.ReadAllBytes(Path.Join(output, "adventure.d64")));
        (disk.Name, disk.Id).Should().Be(("ADVENTURE", "RC"));
        disk.Files.Select(file => (file.Name, file.Type)).Should().Equal(("ADVENTURE", CbmDosFileType.Program));
        disk.ReadFile("ADVENTURE").Should().Equal(prg);

        Project(""", "image": { "boot": "disk" }""");
        ProjectBuild.Build(RetrocoreProject.Load(_folder).Target("pet")).Media.Should().Be(new TargetMedia(
            Path.Join(output, "adventure.prg"), "PRG", Path.Join(output, "adventure.d64"), "4040 disk (D64)",
            "LOAD\"ADVENTURE\",8 and RUN, in a 4040 with its ROMs; the tape is adventure.tap"));

        Project(""", "image": false""");
        ProjectBuild.Build(RetrocoreProject.Load(_folder).Target("pet")).Media.Image.Should().BeNull();
        Directory.GetFiles(output).Select(Path.GetFileName).Should().BeEquivalentTo("adventure.bin", "adventure.dbg", "adventure.map", "adventure.prg");
    }

    /// <summary>
    ///  A <c>basic</c> target takes no <c>files</c>, boots only its tape or its disk, and an environment that boots one
    ///  image takes no <c>boot</c>.
    /// </summary>
    [TestMethod]
    public void ImageBootsAreTheEnvironmentsOwn()
    {
        Write("retrocore.json", """
            { "sdk": "1", "name": "game", "cpu": "6502", "sources": ["main.s"],
              "targets": {
                "files": { "machine": "pet4032", "environment": "basic", "files": ["main.s"] },
                "floppy": { "machine": "pet4032", "environment": "basic", "image": { "boot": "floppy" } },
                "dos": { "machine": "apple2-iiplus", "environment": "dos33", "image": { "boot": "disk" } } } }
            """);

        Write("main.s", "rts\n");
        RetrocoreProject project = RetrocoreProject.Load(_folder);
        Action files = project.Target("files").RequireSupported;
        files.Should().Throw<ProjectException>().WithMessage("*the 'basic' environment puts only its program on its tape and disk, so it takes no 'files'.");
        Action floppy = project.Target("floppy").RequireSupported;
        floppy.Should().Throw<ProjectException>().WithMessage("*the 'basic' environment boots 'tape' or 'disk', not 'floppy'.");
        Action dos = project.Target("dos").RequireSupported;
        dos.Should().Throw<ProjectException>().WithMessage("*the 'dos33' environment boots one image, so its image takes no 'boot'.");
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
