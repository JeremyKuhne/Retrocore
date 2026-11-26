// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug.Project;
using Retrocore.Machines.Apple1;
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
    ///  With <c>"image": false</c>, a <c>wozmon</c> target writes its hex and no tape; a <c>bare</c> target writes
    ///  nothing beyond its binary.
    /// </summary>
    [TestMethod]
    public void ImageFalseLeavesTheTapeOut()
    {
        Write("retrocore.json", """
            { "sdk": "1", "name": "hello", "cpu": "6502", "sources": ["hello.s"],
              "targets": {
                "woz": { "machine": "apple1", "environment": "wozmon", "image": false },
                "bare": { "machine": "apple1", "environment": "bare" } } }
            """);

        Write("hello.s", Hello.Replace(".include <environment.inc>", "", StringComparison.Ordinal));
        RetrocoreProject project = RetrocoreProject.Load(_folder);
        TargetBuild woz = ProjectBuild.Build(project.Target("woz"));
        woz.Media.File.Should().Be(Path.Join(_folder, "artifacts", "woz", "hello.hex"));
        (woz.Media.Image, woz.Media.ImageKind).Should().Be((null, null));
        woz.Media.Note.Should().Be("type it at the Woz Monitor's prompt");
        File.Exists(Path.Join(_folder, "artifacts", "woz", "hello.wav")).Should().BeFalse();

        ProjectBuild.Build(project.Target("bare")).Media.Should().Be(TargetMedia.None);
        Directory.GetFiles(Path.Join(_folder, "artifacts", "bare")).Select(Path.GetFileName)
            .Should().BeEquivalentTo("hello.bin", "hello.dbg", "hello.map");
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
