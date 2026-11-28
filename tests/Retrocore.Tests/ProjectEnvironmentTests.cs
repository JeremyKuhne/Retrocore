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
    ///  A <c>basic</c> program's name on its tape and disk keeps the project name's letters, digits, <c>-</c> and
    ///  <c>.</c>, which CBM DOS takes and the PET types, so a project named with <c>_</c> builds.
    /// </summary>
    [TestMethod]
    public void BasicNamesTheProgramWhatThePetTypes()
    {
        Write("retrocore.json", """
            { "sdk": "1", "name": "my_game-2.0", "cpu": "6502", "sources": ["main.s"],
              "targets": { "pet": { "machine": "pet4032", "environment": "basic" } } }
            """);

        Write("main.s", "rts\n");
        ProjectBuild.Build(RetrocoreProject.Load(_folder).Target("pet"));
        CbmDosDisk.FromD64(File.ReadAllBytes(Path.Join(_folder, "artifacts", "pet", "my_game-2.0.d64"))).Files.Single().Name
            .Should().Be("MYGAME-2.0");
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
    ///  A <c>sos</c> target writes its SOS.INTERP, loading at <c>$2000</c>, and a SOS boot disk named for the project
    ///  with SOS.KERNEL, SOS.DRIVER, the interpreter and its files, each a BIN file whose aux type is its address. A
    ///  program whose entry is past its first byte starts with a <c>JMP</c>, or fails the build.
    /// </summary>
    [TestMethod]
    public void SosWritesItsInterpreterAndDisk()
    {
        void Project(string source) => Write("main.s", source);
        Write("retrocore.json", """
            { "sdk": "1", "name": "my-game", "cpu": "6502", "sources": ["main.s"], "entry": "START",
              "targets": { "sos": { "machine": "apple3", "environment": "sos",
                "files": [{ "path": "data.bin", "name": "GAME.DAT", "address": "$4000" }] } } }
            """);

        Write("data.bin", "XYZ");
        Project("    jmp START\nDATA:\n    .byte 1\nSTART:\n    rts\n");
        TargetBuild build = ProjectBuild.Build(RetrocoreProject.Load(_folder).Target("sos"));
        string output = Path.Join(_folder, "artifacts", "sos");
        build.Media.Should().Be(new TargetMedia(
            Path.Join(output, "my-game.interp"), "SOS.INTERP", Path.Join(output, "my-game.dsk"), "SOS boot disk",
            "boot the disk in .D1, and SOS starts the program"));

        byte[] program = [0x4C, 0x04, 0x20, 1, 0x60];
        SosInterpreterFile interpreter = SosInterpreterFile.Read(File.ReadAllBytes(Path.Join(output, "my-game.interp")));
        (interpreter.LoadAddress, interpreter.Code.ToArray()).Should().BeEquivalentTo((0x2000, program));

        SosVolume volume = SosVolume.Read(File.ReadAllBytes(Path.Join(output, "my-game.dsk")), proDosOrder: false);
        volume.Name.Should().Be("MYGAME");
        volume.Files.Select(file => file.Name).Should().Contain(["SOS.KERNEL", "SOS.DRIVER", "SOS.INTERP", "GAME.DAT"]);
        SosInterpreterFile.Read(volume.ReadFile("SOS.INTERP")).Code.ToArray().Should().Equal(program);
        SosFileEntry data = volume.Files.Single(file => file.Name == "GAME.DAT");
        (data.FileType, data.AuxType).Should().Be((SosEnvironment.BinaryType, 0x4000));
        volume.ReadFile("GAME.DAT").Should().Equal("XYZ"u8.ToArray());

        Project("DATA:\n    .byte 1\nSTART:\n    rts\n");
        Action late = () => ProjectBuild.Build(RetrocoreProject.Load(_folder).Target("sos"));
        late.Should().Throw<ProjectException>().WithMessage(
            "*SOS starts an interpreter at its first byte, $2000, but the entry is $2001; start the program at its entry, or with jmp on to it.");
    }

    /// <summary>
    ///  A <c>sos</c> target's files need SOS names, each once on the disk, beside SOS's own files.
    /// </summary>
    [TestMethod]
    public void SosRefusesBadNames()
    {
        string Fails(string files)
        {
            Write("retrocore.json", $$"""
                { "sdk": "1", "name": "game", "cpu": "6502", "sources": ["main.s"],
                  "targets": { "sos": { "machine": "apple3", "environment": "sos", "files": {{files}} } } }
                """);

            Action build = () => ProjectBuild.Build(RetrocoreProject.Load(_folder).Target("sos"));
            return build.Should().Throw<ProjectException>().Which.Message;
        }

        Write("main.s", "rts\n");
        Write("data.bin", "1");
        Fails("""[{ "path": "data.bin", "name": "GAME_DATA" }]""").Should().EndWith(
            "'GAME_DATA' is not a SOS file name, 1 to 15 letters, digits and periods from a letter; give its file a 'name'.");

        Fails("""[{ "path": "data.bin", "name": "sos.kernel" }]""").Should().EndWith("two files on the disk are named SOS.KERNEL.");
    }

    /// <summary>
    ///  A <c>prodos</c> target's disk is ProDOS's own disk's boot blocks and <c>PRODOS</c>, then the program as a SYS
    ///  file loading at <c>$2000</c>, named for the project and cut to eight before <c>.SYSTEM</c>, then its files, each
    ///  a BIN file whose aux type is its address, in ProDOS's block order.
    /// </summary>
    [TestMethod]
    public void ProdosDiskHoldsProDosThenTheProgram()
    {
        Write("retrocore.json", """
            { "sdk": "1", "name": "my-adventure", "cpu": "6502", "sources": ["main.s"], "entry": "START",
              "targets": { "prodos": { "machine": "apple2-iiplus", "environment": "prodos", "image": false,
                "files": [{ "path": "data.bin", "name": "GAME.DAT", "address": "$4000" }, "notes.txt"] } } }
            """);

        Write("data.bin", "XYZ");
        Write("notes.txt", "N");
        Write("main.s", "    jmp START\nDATA:\n    .byte 1\nSTART:\n    rts\n");
        TargetBuild build = ProjectBuild.Build(RetrocoreProject.Load(_folder).Target("prodos"));
        build.Media.Should().Be(new TargetMedia(File: null, FileKind: null, Image: null, ImageKind: null, "the binary is the system file MYADVENT.SYSTEM, which ProDOS loads at $2000"));

        SosVolume volume = SosVolume.Read(ProdosEnvironment.Disk(build, ProDosDisk()), proDosOrder: true);
        volume.Name.Should().Be("MYADVENTURE");
        volume.Block(0).Should().OnlyContain(value => value == 0xB0, "block 0 is ProDOS's boot loader");
        volume.Block(1).Should().OnlyContain(value => value == 0xB1);
        volume.Files.Select(file => (file.Name, file.FileType, file.AuxType)).Should().Equal(
            ("PRODOS", 0xFF, 0), ("MYADVENT.SYSTEM", 0xFF, 0x2000), ("GAME.DAT", 0x06, 0x4000), ("NOTES.TXT", 0x06, 0));

        volume.ReadFile("PRODOS").Should().Equal("SYSTEM"u8.ToArray());
        volume.ReadFile("MYADVENT.SYSTEM").Should().Equal(0x4C, 0x04, 0x20, 1, 0x60);
        volume.ReadFile("GAME.DAT").Should().Equal("XYZ"u8.ToArray());
    }

    /// <summary>
    ///  A <c>prodos</c> target starts at <c>$2000</c>, at its entry or with a <c>JMP</c>, and its files need ProDOS
    ///  names, each once on the disk, beside <c>PRODOS</c> and the program.
    /// </summary>
    [TestMethod]
    public void ProdosRefusesWhatProDosCannotStartOrHold()
    {
        string Fails(string target, string source)
        {
            Write("retrocore.json", $$"""
                { "sdk": "1", "name": "game", "cpu": "6502", "sources": ["main.s"], "entry": "START",
                  "targets": { "prodos": { "machine": "apple2-iie", "environment": "prodos", "image": false{{target}} } } }
                """);

            Write("main.s", source);
            Action build = () => ProdosEnvironment.Disk(ProjectBuild.Build(RetrocoreProject.Load(_folder).Target("prodos")), ProDosDisk());
            return build.Should().Throw<ProjectException>().Which.Message;
        }

        const string Starts = "START:\n    rts\n";
        Write("data.bin", "1");
        Fails("", "DATA:\n    .byte 1\nSTART:\n    rts\n").Should().EndWith(
            "ProDOS starts a system file at its first byte, $2000, but the entry is $2001; start the program at its entry, or with jmp on to it.");

        Fails(""", "memoryMap": { "load": "$4000" }""", Starts).Should().EndWith(
            "ProDOS loads a system file at $2000, but the program starts at $4000; place it at $2000.");

        Fails(""", "files": [{ "path": "data.bin", "name": "GAME_DATA" }]""", Starts).Should().EndWith(
            "'GAME_DATA' is not a ProDOS file name, 1 to 15 letters, digits and periods from a letter; give its file a 'name'.");

        Fails(""", "files": [{ "path": "data.bin", "name": "prodos" }]""", Starts).Should().EndWith("two files on the disk are named PRODOS.");
        Fails(""", "files": [{ "path": "data.bin", "name": "Game.System" }]""", Starts).Should().EndWith("two files on the disk are named GAME.SYSTEM.");
    }

    /// <summary>
    ///  A <c>prodos</c> target builds its disk when ProDOS 2.4.3's is found by its hash, and otherwise writes the binary
    ///  alone, its note naming the disk it needs and where it was looked for.
    /// </summary>
    [TestMethod]
    public void ProdosBuildsItsDiskOnlyWithProDos()
    {
        Write("retrocore.json", """
            { "sdk": "1", "name": "game", "cpu": "6502", "sources": ["main.s"],
              "targets": { "prodos": { "machine": "apple2-iie-enhanced", "environment": "prodos" } } }
            """);

        Write("main.s", "rts\n");
        TargetBuild build = ProjectBuild.Build(RetrocoreProject.Load(_folder).Target("prodos"));
        if (build.Media.Image is { } image)
        {
            // ProDOS 2.4.3's disk was found.
            build.Media.ImageKind.Should().Be("ProDOS disk");
            Path.GetFileName(image).Should().Be("game.po");
            SosVolume.Read(File.ReadAllBytes(image), proDosOrder: true).Files.Select(file => file.Name).Should().Equal("PRODOS", "GAME.SYSTEM");
        }
        else
        {
            string note = build.Media.Note ?? "";
            note.Should().StartWith("no disk: ProDOS 2.4.3's disk, for an Apple II prodos target's disk, which takes its boot blocks and its PRODOS file, was not found by its hash in ");
            note.Should().EndWith("The binary is the system file GAME.SYSTEM");
            File.Exists(Path.Join(_folder, "artifacts", "prodos", "game.po")).Should().BeFalse();
        }
    }

    /// <summary>
    ///  A <c>level2</c> target links at its map's load address, <c>$4300</c> on the Model I and <c>$4400</c> on the
    ///  Model III, above their ROMs' RAM, and writes its SYSTEM tape under the project's name cut to six, with its entry.
    /// </summary>
    /// <param name="machine">The catalog machine.</param>
    /// <param name="load">Where its map loads a program.</param>
    [TestMethod]
    [DataRow("trs80-model1-level2", 0x4300)]
    [DataRow("trs80-model3", 0x4400)]
    public void Level2WritesItsSystemTape(string machine, int load)
    {
        Write("retrocore.json", $$"""
            { "sdk": "1", "name": "2-space-game", "cpu": "z80", "sources": ["main.s"], "entry": "START",
              "targets": { "tape": { "machine": "{{machine}}", "environment": "level2" } } }
            """);

        Write("main.s", "DATA:\n    .byte 1\nSTART:\n    JP START\n");
        TargetBuild build = ProjectBuild.Build(RetrocoreProject.Load(_folder).Target("tape"));
        string tape = Path.Join(_folder, "artifacts", "tape", "2-space-game.cas");
        build.Media.Should().Be(new TargetMedia(
            File: null, FileKind: null, tape, "SYSTEM tape (CAS)", "SYSTEM, then SPACEG at the *? prompt, then / once it has loaded"));

        (string name, IReadOnlyList<(int Address, byte[] Bytes)> blocks, int entry) = Retrocore.Media.Trs80.SystemTape.Read(File.ReadAllBytes(tape));
        (name, entry).Should().Be(("SPACEG", load + 1));
        byte[] program = [1, 0xC3, (byte)(load + 1), (byte)((load + 1) >> 8)];
        blocks.Should().ContainSingle();
        (blocks[0].Address, blocks[0].Bytes).Should().BeEquivalentTo((load, program));
        File.ReadAllText(Path.Join(_folder, "obj", "tape", "memory.cfg")).Should().NotContain("ZP:", "the Z80 has no zero page");
    }

    /// <summary>
    ///  A <c>level2</c> map has no zero page, as the Z80 has none, so a program's sections are checked from
    ///  <c>$0000</c>: one placed over the ROM's RAM fails naming it, and a program too big for 16K says how far over it
    ///  is. A program with no bytes has no tape, and a target cannot give files, as the tape holds the program alone.
    /// </summary>
    [TestMethod]
    public void Level2MapsAndRefusals()
    {
        string Fails(string target, string source)
        {
            Write("retrocore.json", $$"""
                { "sdk": "1", "name": "game", "cpu": "z80", "sources": ["main.s"],
                  "targets": { "tape": { "machine": "trs80-model1-level2", "environment": "level2"{{target}} } } }
                """);

            Write("main.s", source);
            Action build = () => ProjectBuild.Build(RetrocoreProject.Load(_folder).Target("tape"));
            return build.Should().Throw<ProjectException>().Which.Message;
        }

        Fails(""", "memoryMap": { "load": "$4000", "free": [{ "start": "$4000", "end": "$40FF" }] }""", "    RET\n    .res $200\n").Should().Contain(
            "section CODE ($4000-$4200) overlaps Level II's RAM:");

        Fails(""", "options": { "ramKilobytes": 16, "expansionInterface": false }""", ".res $4000\n").Should().Contain(
            "overlaps addresses with no RAM, as the machine has 16K from $4000 ($8000-$FFFF)").And.Contain("so it is 768 bytes over.");

        Fails(""", "memoryMap": { "zeroPage": ["$80"] }""", "RET\n").Should().EndWith(
            "target tape: its CPU has no zero page, so its 'memoryMap' cannot give 'zeroPage'.");

        Fails("", "").Should().EndWith("target tape: the sources emit no bytes.");
        Write("data.bin", "1");
        Fails(""", "files": ["data.bin"]""", "RET\n").Should().EndWith(
            "the 'level2' environment puts only its program on its tape, so it takes no 'files'.");
    }

    /// <summary>
    ///  A <c>colorbasic</c> target links at <c>$1F00</c>, above Extended BASIC's graphics pages and BASIC's empty
    ///  program, and writes its cassette: one machine-language file under the project's name cut to eight, which EXEC
    ///  starts at the entry. Its map has no zero page, as the 6809's direct page is not one, so a section is checked from
    ///  <c>$0000</c>, and a program too big for 16K says how far over it is.
    /// </summary>
    /// <param name="machine">The catalog machine.</param>
    [TestMethod]
    [DataRow("coco1")]
    [DataRow("coco3")]
    public void ColorbasicWritesItsTape(string machine)
    {
        Write("retrocore.json", $$"""
            { "sdk": "1", "name": "space-adventure", "cpu": "6809", "sources": ["main.s"], "entry": "START",
              "targets": { "tape": { "machine": "{{machine}}", "environment": "colorbasic" },
                           "big": { "machine": "coco1", "environment": "colorbasic", "options": { "ramKilobytes": 16 } } } }
            """);

        Write("main.s", "DATA:\n    .byte 1\nSTART:\n    rts\n");
        TargetBuild build = ProjectBuild.Build(RetrocoreProject.Load(_folder).Target("tape"));
        string tape = Path.Join(_folder, "artifacts", "tape", "space-adventure.cas");
        build.Media.Should().Be(new TargetMedia(
            File: null, FileKind: null, tape, "Color Computer tape (CAS)", "CLOADM\"SPACEADV\", then EXEC once it has loaded"));

        (string name, int address, byte[] bytes, int entry) = Retrocore.Media.Trs80.CocoTape.Read(File.ReadAllBytes(tape));
        (name, address, entry).Should().Be(("SPACEADV", 0x1F00, 0x1F01));
        bytes.Should().Equal(1, 0x39);
        File.ReadAllText(Path.Join(_folder, "obj", "tape", "memory.cfg")).Should().NotContain("ZP:", "the 6809 has no zero page");

        Write("main.s", "START:\n    rts\n    .res $2000\n");
        Action big = () => ProjectBuild.Build(RetrocoreProject.Load(_folder).Target("big"));
        big.Should().Throw<ProjectException>().Which.Message.Should().Contain(
            "overlaps BASIC's 200 bytes of string space at the top of RAM").And.Contain("so it is 257 bytes over.");
    }

    /// <summary>
    ///  A <c>diskbasic</c> target links at <c>$2700</c>, above Disk BASIC's workspace, the graphics pages it moves up and
    ///  BASIC's empty program, and writes its RS-DOS disk: the program as <c>&lt;NAME&gt;.BIN</c> in LOADM's format, and
    ///  its files as binary data files; a file needs a name the SDK puts on a disk, once, some bytes and no address.
    /// </summary>
    [TestMethod]
    public void DiskbasicWritesItsDisk()
    {
        Write("retrocore.json", """
            { "sdk": "1", "name": "space-adventure", "cpu": "6809", "sources": ["main.s"], "entry": "START",
              "targets": { "disk": { "machine": "coco2", "environment": "diskbasic",
                                     "files": [{ "path": "data.bin", "name": "GAME.DAT" }, "notes"] },
                           "bad": { "machine": "coco2", "environment": "diskbasic", "files": [{ "path": "data.bin", "name": "GAME.DATA" }] },
                           "clash": { "machine": "coco2", "environment": "diskbasic", "files": [{ "path": "data.bin", "name": "SPACEADV.BIN" }] },
                           "address": { "machine": "coco2", "environment": "diskbasic", "files": [{ "path": "data.bin", "address": "$4000" }] },
                           "empty": { "machine": "coco2", "environment": "diskbasic", "files": ["empty.dat"] } } }
            """);

        Write("data.bin", "XYZ");
        Write("notes", "N");
        Write("main.s", "DATA:\n    .byte 1\nSTART:\n    rts\n");
        TargetBuild build = ProjectBuild.Build(RetrocoreProject.Load(_folder).Target("disk"));
        string disk = Path.Join(_folder, "artifacts", "disk", "space-adventure.dsk");
        build.Media.Should().Be(new TargetMedia(
            File: null, FileKind: null, disk, "RS-DOS disk (JVC)", "LOADM\"SPACEADV\" from drive 0, then EXEC"));

        IReadOnlyList<(string Name, string Extension, byte Type, bool Ascii, byte[] Bytes)> files = Retrocore.Media.Trs80.RsDosDisk.Read(File.ReadAllBytes(disk));
        files.Select(file => (file.Name, file.Extension, file.Type)).Should().Equal(("SPACEADV", "BIN", (byte)2), ("GAME", "DAT", (byte)1), ("NOTES", "", (byte)1));
        files[0].Bytes.Should().Equal(0, 0, 2, 0x27, 0x00, 1, 0x39, 0xFF, 0, 0, 0x27, 0x01);
        files[1].Bytes.Should().Equal("XYZ"u8.ToArray());

        string Fails(string name)
        {
            Action build = () => ProjectBuild.Build(RetrocoreProject.Load(_folder).Target(name));
            return build.Should().Throw<ProjectException>().Which.Message;
        }

        Write("empty.dat", "");
        Fails("clash").Should().EndWith("target clash: two files on the disk are named SPACEADV.BIN.");
        Fails("address").Should().EndWith("target address: DATA.BIN goes on the disk as a data file, which keeps no load address, so it cannot give 'address'.");
        Fails("empty").Should().EndWith("target empty: EMPTY.DAT is empty, and a file on the disk holds at least a byte.");
        Action bad = () => ProjectBuild.Build(RetrocoreProject.Load(_folder).Target("bad"));
        bad.Should().Throw<ProjectException>().Which.Message.Should().EndWith(
            "'GAME.DATA' is not a name the SDK puts on an RS-DOS disk, 1 to 8 capital letters and digits from a letter, then an extension of up to 3, also from a letter; give its file a 'name'.");
    }

    // A small ProDOS disk in ProDOS's order, as the build reads ProDOS 2.4.3's: its boot blocks, each filled with a
    // byte of its own, and PRODOS, whose contents stand in for ProDOS itself.
    private static byte[] ProDosDisk()
    {
        SosVolumeBuilder builder = new("PRODOS.2.4.3");
        byte[] boot = [.. Enumerable.Repeat((byte)0xB0, 512), .. Enumerable.Repeat((byte)0xB1, 512)];
        builder.BootFrom(boot);
        builder.Add("README", 0x04, 0, "R"u8);
        builder.Add("PRODOS", 0xFF, 0, "SYSTEM"u8);
        return builder.Build(proDosOrder: true);
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
