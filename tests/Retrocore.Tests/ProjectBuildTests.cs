// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug.Project;
using System.Text.Json.Nodes;

namespace Retrocore.Tests;

/// <summary>
///  <c>retrocore build</c> assembles a project's <c>bare</c> targets for their CPUs and machines, with their defines
///  and platform folders, and writes the binary, debug information, map and build record.
/// </summary>
[TestClass]
public sealed class ProjectBuildTests
{
    private string _folder = "";

    /// <summary>
    ///  Gets each test a folder of its own.
    /// </summary>
    [TestInitialize]
    public void Initialize()
    {
        _folder = Path.Join(Path.GetTempPath(), "retrocore-build-" + Guid.NewGuid().ToString("N"));
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
    ///  A bare Apple II target assembles at the machine's load address, its defines over the project's choose code,
    ///  and its output lands in artifacts/&lt;target&gt;/ and obj/&lt;target&gt;/.
    /// </summary>
    [TestMethod]
    public void BareTargetWritesItsOutput()
    {
        Write("retrocore.json", """
            { "sdk": "1", "name": "hello", "cpu": "6502", "sources": ["src/*.s"], "defines": { "COLUMNS": 40, "FAST": 1 },
              "entry": "START",
              "targets": { "apple2-bare": { "machine": "apple2-iiplus", "environment": "bare", "defines": { "COLUMNS": 80 } } } }
            """);

        Write("src/main.s", """
            DATA:
                .byte COLUMNS
            START:
            .if FAST
                lda #1
            .else
                lda #2
            .endif
                rts
            """);

        TargetBuild build = ProjectBuild.Build(RetrocoreProject.Load(_folder).Target("apple2-bare"));
        string output = Path.Join(_folder, "artifacts", "apple2-bare");
        build.Binary.Should().Be(Path.Join(output, "hello.bin"));
        File.ReadAllBytes(build.Binary).Should().Equal(80, 0xA9, 1, 0x60);
        build.Entry.Should().Be(0x6001);
        ProjectBuild.Image(build).Address.Should().Be(0x6000);

        File.ReadAllText(Path.Join(output, "hello.dbg")).Should().Contain("main.s");
        string map = File.ReadAllText(Path.Join(output, "hello.map"));
        map.Should().StartWith("; hello, target apple2-bare: apple2-iiplus, bare, 6502\nload $6000-$6003 (4 bytes)\nentry $6001\n");
        map.Should().Contain("\nsections\n  .text            $6000-$6003      4\n");
        map.Should().Contain("START").And.Contain("$6001 label");

        JsonNode record = JsonNode.Parse(File.ReadAllText(Path.Join(_folder, "obj", "apple2-bare", "build.json")))
            ?? throw new AssertFailedException("No build record.");

        ((string?)record["cpu"]).Should().Be("6502");
        ((string?)record["sources"]?[0]).Should().Be(Path.Join(_folder, "src", "main.s"));
        ((long?)record["defines"]?["COLUMNS"]).Should().Be(80);
    }

    /// <summary>
    ///  Each machine's bare program loads where its launch loads a source by default.
    /// </summary>
    /// <param name="machine">The catalog machine.</param>
    /// <param name="cpu">The project's CPU.</param>
    /// <param name="source">A source that emits one byte.</param>
    /// <param name="address">Where it loads.</param>
    [TestMethod]
    [DataRow("pet4032", "6502", "rts", 0x0800)]
    [DataRow("apple1", "6502", "rts", 0x0300)]
    [DataRow("bbcb", "6502", "rts", 0x2000)]
    [DataRow("kaypro2", "z80", "ret", 0x0100)]
    [DataRow("altair", "8080", "ret", 0x0100)]
    [DataRow("trs80-model3", "z80", "ret", 0x7000)]
    [DataRow("coco2", "6809", "rts", 0x3000)]
    public void BareProgramsLoadAtTheMachinesAddress(string machine, string cpu, string source, int address)
    {
        Write("retrocore.json", $$"""
            { "sdk": "1", "name": "one", "cpu": "{{cpu}}", "sources": ["main.s"],
              "targets": { "t": { "machine": "{{machine}}", "environment": "bare" } } }
            """);

        Write("main.s", source);
        TargetBuild build = ProjectBuild.Build(RetrocoreProject.Load(_folder).Target("t"));
        ProjectBuild.Image(build).Address.Should().Be(address);
        build.Entry.Should().Be(address);
        File.ReadAllBytes(build.Binary).Should().HaveCount(1);
    }

    /// <summary>
    ///  The build starts at the target's CPU: a 65C02 instruction fails a 6502 target and builds where the target
    ///  raises the CPU.
    /// </summary>
    [TestMethod]
    public void BuildStartsAtTheTargetsCpu()
    {
        Write("retrocore.json", """
            { "sdk": "1", "cpu": "6502", "sources": ["main.s"], "targets": {
                "iiplus": { "machine": "apple2-iiplus", "environment": "bare" },
                "iie": { "machine": "apple2-iie-enhanced", "environment": "bare" },
                "iie-cmos": { "machine": "apple2-iie-enhanced", "environment": "bare", "cpu": "65c02" } } }
            """);

        Write("main.s", "stz $00\nrts");
        RetrocoreProject project = RetrocoreProject.Load(_folder);
        Error(() => ProjectBuild.Build(project.Target("iiplus"))).Should().Contain("target iiplus:").And.Contain("main.s(1)");
        Error(() => ProjectBuild.Build(project.Target("iie"))).Should().Contain("target iie:");
        File.ReadAllBytes(ProjectBuild.Build(project.Target("iie-cmos")).Binary).Should().Equal(0x64, 0x00, 0x60);
    }

    /// <summary>
    ///  A source's <c>.cpu</c> may switch to another CPU its machine has, but one the machine lacks is an error
    ///  naming the target and the machine.
    /// </summary>
    [TestMethod]
    public void SourceCpuTheMachineLacksIsAnError()
    {
        Write("retrocore.json", """
            { "sdk": "1", "cpu": "6502", "sources": ["main.s"], "targets": {
                "iiplus": { "machine": "apple2-iiplus", "environment": "bare" },
                "iie": { "machine": "apple2-iie-enhanced", "environment": "bare" } } }
            """);

        Write("main.s", ".cpu Rockwell65C02\nstz $00\nrts");
        RetrocoreProject project = RetrocoreProject.Load(_folder);
        File.ReadAllBytes(ProjectBuild.Build(project.Target("iie")).Binary).Should().Equal(0x64, 0x00, 0x60);
        Error(() => ProjectBuild.Build(project.Target("iiplus"))).Should().Contain(
            "main.s(1): .cpu Rockwell65C02 names a CPU target iiplus lacks: its machine, apple2-iiplus, runs 6502 code.");

        Write("main.s", ".cpu Z80\nret");
        Error(() => ProjectBuild.Build(project.Target("iie"))).Should().Contain(
            ".cpu Z80 names a CPU target iie lacks: its machine, apple2-iie-enhanced, runs r65c02 code.");
    }

    /// <summary>
    ///  A <c>.cpu</c> in code a conditional turns off is not checked.
    /// </summary>
    [TestMethod]
    public void SourceCpuInCodeThatIsOffIsNotChecked()
    {
        Write("retrocore.json", """
            { "sdk": "1", "cpu": "6502", "sources": ["main.s"], "targets": { "t": { "machine": "apple2-iiplus", "environment": "bare" } } }
            """);

        Write("main.s", ".ifdef Z80_BUILD\n.cpu Z80\n.endif\nrts");
        File.ReadAllBytes(ProjectBuild.Build(RetrocoreProject.Load(_folder).Target("t")).Binary).Should().Equal(0x60);
    }

    /// <summary>
    ///  Sources assemble as one stream: the project's, the platform folders' and the target's, each in its dialect.
    /// </summary>
    [TestMethod]
    public void SourcesAssembleInOrder()
    {
        Write("retrocore.json", """
            { "sdk": "1", "cpu": "6502", "sources": ["src/main.s"], "targets": {
                "t": { "machine": "apple2-iie", "environment": "bare", "sources": [{ "path": "src/end.s", "dialect": "native" }] } } }
            """);

        Write("src/main.s", "jsr PUT");
        Write("src/platform/apple2/console.s", "PUT: lda #1");
        Write("src/platform/apple2-iie/console.s", "PUT: lda #2");
        Write("src/end.s", "rts");
        File.ReadAllBytes(ProjectBuild.Build(RetrocoreProject.Load(_folder).Target("t")).Binary)
            .Should().Equal(0x20, 0x03, 0x60, 0xA9, 0x02, 0x60);
    }

    /// <summary>
    ///  A bare binary is one block: code with a gap in it is an error, rather than a binary that fills the gap.
    /// </summary>
    [TestMethod]
    public void BareBinaryIsOneBlock()
    {
        Write("retrocore.json", """
            { "sdk": "1", "cpu": "6502", "sources": ["main.s"], "targets": { "t": { "machine": "apple2-iiplus", "environment": "bare" } } }
            """);

        Write("main.s", "rts\n.section Low, $5000, $10\nrts");
        Error(() => ProjectBuild.Build(RetrocoreProject.Load(_folder).Target("t"))).Should().EndWith(
            "target t: a bare binary is one block, but its code and data end at $5000 and the next part starts at $6000.");

        Write("main.s", "rts\n.section Below, $5FFF, 1\nrts");
        File.ReadAllBytes(ProjectBuild.Build(RetrocoreProject.Load(_folder).Target("t")).Binary).Should().Equal(0x60, 0x60);
    }

    /// <summary>
    ///  What does not build yet fails before assembling, and a missing entry label is an error.
    /// </summary>
    [TestMethod]
    public void UnsupportedTargetsAndMissingEntriesFail()
    {
        Write("retrocore.json", """
            { "sdk": "1", "cpu": "6502", "sources": ["main.s"], "entry": "GO", "targets": {
                "dos": { "machine": "apple2-iiplus", "environment": "dos33" },
                "bare": { "machine": "apple2-iiplus", "environment": "bare" } } }
            """);

        Write("main.s", "rts");
        RetrocoreProject project = RetrocoreProject.Load(_folder);
        Error(() => ProjectBuild.Build(project.Target("dos"))).Should().EndWith("the 'dos33' environment is not yet supported; only 'bare' builds.");
        Error(() => ProjectBuild.Build(project.Target("bare"))).Should().EndWith("target bare: the entry 'GO' is not an address the sources define.");
        Directory.Exists(Path.Join(_folder, "artifacts")).Should().BeFalse();
    }

    /// <summary>
    ///  The command builds the one target, a named one or every one, from the project it names or the nearest above
    ///  the current folder, and reports errors with exit codes.
    /// </summary>
    [TestMethod]
    public void CommandChoosesTargets()
    {
        Write("retrocore.json", """{ "projects": ["game", "tool"] }""");
        Write("game/retrocore.json", """
            { "sdk": "1", "cpu": "6502", "sources": ["main.s"], "targets": {
                "apple2": { "machine": "apple2-iiplus", "environment": "bare" },
                "pet": { "machine": "pet4032", "environment": "bare" } } }
            """);

        Write("game/main.s", "rts");
        Write("tool/retrocore.json", """
            { "sdk": "1", "cpu": "z80", "sources": ["main.s"], "targets": { "pet": { "machine": "kaypro2", "environment": "bare" } } }
            """);

        Write("tool/main.s", "ret");

        (int code, string output, string error) = Run("--project", Path.Join(_folder, "game"), "--target", "pet");
        code.Should().Be(0, error);
        output.Should().Be($"game/pet: {Path.Join(_folder, "game", "artifacts", "pet", "game.bin")} ($0800-$0800, 1 byte, entry $0800)\n");

        Run("--project", _folder, "--target", "pet").Error.Should().Contain("The projects game and tool each have a target 'pet'; name it as project/target, or give that project's own retrocore.json.");
        Run("--project", _folder).Error.Should().Contain("Give --target name or --all; the targets are game/apple2, game/pet, tool/pet.");
        Run("--project", _folder, "--target", "atari").Code.Should().Be(1);
        Run("--target", "x", "--all").Code.Should().Be(2);
        Run("--bogus").Code.Should().Be(2);

        (code, output, _) = Run("--project", _folder, "--all");
        code.Should().Be(0);
        output.Split('\n', StringSplitOptions.RemoveEmptyEntries).Select(line => line[..line.IndexOf(':')])
            .Should().Equal("game/apple2", "game/pet", "tool/pet");

        Run("--project", Path.Join(_folder, "tool")).Code.Should().Be(0);
        Run("--project", _folder, "--target", "tool/pet").Output.Should().StartWith("tool/pet: ");
        Run("--project", Path.Join(_folder, "missing")).Error.Should().Contain("does not exist");
        BuildCommand.Find(Path.Join(_folder, "game", "artifacts")).Should().Be(Path.Join(_folder, "game", "retrocore.json"));

        // With --all, the other targets still build after one fails.
        Write("game/main.s", "stz $00");
        (code, output, error) = Run("--project", _folder, "--all");
        code.Should().Be(1);
        error.Should().Contain("target apple2:").And.Contain("target pet:");
        output.Should().StartWith("tool/pet: ");
    }

    private static (int Code, string Output, string Error) Run(params string[] args)
    {
        using StringWriter output = new() { NewLine = "\n" };
        using StringWriter error = new() { NewLine = "\n" };
        int code = BuildCommand.Run(args, output, error);
        return (code, output.ToString(), error.ToString());
    }

    private void Write(string path, string text)
    {
        string file = Path.Join(_folder, path);
        Directory.CreateDirectory(Path.GetDirectoryName(file) ?? _folder);
        File.WriteAllText(file, text);
    }

    private static string Error(Func<object> action)
    {
        try
        {
            _ = action();
        }
        catch (ProjectException exception)
        {
            return exception.Message;
        }

        throw new AssertFailedException("Expected a ProjectException.");
    }
}