// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug;
using Retrocore.Debug.Project;
using System.Text.Json.Nodes;

namespace Retrocore.Tests;

/// <summary>
///  A launch with <c>project</c> and <c>target</c> builds the target as <c>retrocore build</c> does and debugs it on
///  the target's machine, with its options and cards.
/// </summary>
[TestClass]
public sealed class ProjectLaunchTests
{
    private string _folder = "";

    /// <summary>
    ///  Gets each test a folder of its own.
    /// </summary>
    [TestInitialize]
    public void Initialize()
    {
        _folder = Path.Join(Path.GetTempPath(), "retrocore-launch-" + Guid.NewGuid().ToString("N"));
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
    ///  The launch builds the target into its artifacts, loads it on the target's machine, stops at its entry, and
    ///  binds breakpoints in its sources.
    /// </summary>
    [TestMethod]
    public void ProjectLaunchDebugsTheTarget()
    {
        Write("retrocore.json", """
            { "sdk": "1", "name": "hello", "cpu": "6502", "sources": ["src/*.s"], "entry": "START",
              "targets": { "apple2": { "machine": "apple2-iiplus", "environment": "bare" } } }
            """);

        string main = Write("src/main.s", "DATA:\n    .byte 1\nSTART:\n    lda DATA\n    rts\n");

        using DapTestClient client = new();
        client.Request("initialize", []);
        client.Request("launch", Launch("apple2"));
        File.Exists(Path.Join(_folder, "artifacts", "apple2", "hello.bin")).Should().BeTrue();
        client.Request("evaluate", new JsonObject
        {
            ["expression"] = "PC"
        }).String("result").Should().StartWith("$6001");

        client.Request("evaluate", new JsonObject
        {
            ["expression"] = "START"
        }).String("result").Should().StartWith("$6001");

        JsonObject set = client.Request("setBreakpoints", new JsonObject
        {
            ["source"] = new JsonObject { ["path"] = main },
            ["breakpoints"] = new JsonArray(new JsonObject { ["line"] = 5 })
        });

        (set["breakpoints"]?[0]?["verified"]?.GetValue<bool>()).Should().BeTrue();
        client.Request("configurationDone", []);
        client.Event("stopped").String("reason").Should().Be("entry");
        JsonObject trace = client.Request("stackTrace", new JsonObject { ["threadId"] = 1 });
        ((string?)trace["stackFrames"]?[0]?["source"]?["path"]).Should().Be(main);
    }

    /// <summary>
    ///  Each catalog machine launches a bare target where the build loaded it, so the build's load addresses are the
    ///  launch's, and the target's machine, model and ROM are the launch's.
    /// </summary>
    /// <param name="machine">The catalog machine.</param>
    /// <param name="cpu">The project's CPU.</param>
    /// <param name="instruction">An instruction for it.</param>
    [TestMethod]
    [DataRow("apple2-iie-enhanced", "6502", "rts")]
    [DataRow("apple2-ii", "6502", "rts")]
    [DataRow("apple1", "6502", "rts")]
    [DataRow("apple3", "6502", "rts")]
    [DataRow("pet4032", "6502", "rts")]
    [DataRow("bbcb", "6502", "rts")]
    [DataRow("atari800", "6502", "rts")]
    [DataRow("coco2", "6809", "rts")]
    [DataRow("trs80-model1-level2", "z80", "ret")]
    [DataRow("trs80-model4", "z80", "ret")]
    [DataRow("altair", "8080", "ret")]
    public void EachMachineLoadsWhereTheBuildPlacedIt(string machine, string cpu, string instruction)
    {
        Write("retrocore.json", $$"""
            { "sdk": "1", "name": "one", "cpu": "{{cpu}}", "sources": ["main.s"],
              "targets": { "t": { "machine": "{{machine}}", "environment": "bare" } } }
            """);

        Write("main.s", instruction);
        CatalogMachine catalog = CatalogMachine.Find(machine) ?? throw new AssertFailedException(machine);
        using DapTestClient client = new();
        client.Request("initialize", []);
        client.Request("launch", Launch("t"));
        client.Request("evaluate", new JsonObject { ["expression"] = "PC" }).String("result")
            .Should().StartWith($"${catalog.LoadAddress:X}");
    }

    /// <summary>
    ///  A target's cards go in its machine's slots.
    /// </summary>
    [TestMethod]
    public void TargetCardsGoInTheSlots()
    {
        Write("retrocore.json", """
            { "sdk": "1", "cpu": "6502", "sources": ["main.s"], "targets": {
                "iie": { "machine": "apple2-iie", "environment": "bare", "cards": { "4": "mockingboard" } } } }
            """);

        Write("main.s", "rts");
        using DapTestClient client = new();
        client.Request("initialize", []);
        client.Request("launch", Launch("iie"));
        JsonObject devices = client.Request("retro/devices", []);
        ((string?)devices["configuration"]?["cards"]?["4"]).Should().Be("mockingboard");
    }

    /// <summary>
    ///  A target's options reach the launch, and the launch's own attributes of the same name override them.
    /// </summary>
    [TestMethod]
    public void LaunchAttributesOverrideTargetOptions()
    {
        Write("retrocore.json", """
            { "sdk": "1", "cpu": "6502", "sources": ["main.s"], "targets": {
                "iiplus": { "machine": "apple2-iiplus", "environment": "bare", "options": { "slot0": "empty" } } } }
            """);

        Write("main.s", "rts");
        using DapTestClient client = new();
        client.Request("initialize", []);
        client.Request("launch", Launch("iiplus"));
        ((string?)client.Request("retro/devices", [])["configuration"]?["cards"]?["0"]).Should().Be("empty");

        JsonObject overridden = Launch("iiplus");
        overridden["slot0"] = "languageCard";
        client.Request("launch", overridden);
        ((string?)client.Request("retro/devices", [])["configuration"]?["cards"]?["0"]).Should().Be("languageCard");
    }

    /// <summary>
    ///  A project launch that gives what the project decides, no target, an unknown target, cards for a machine
    ///  without slots, or a target that fails to build, fails naming what is wrong.
    /// </summary>
    [TestMethod]
    public void ProjectLaunchErrors()
    {
        Write("retrocore.json", """
            { "sdk": "1", "cpu": "6502", "sources": ["main.s"], "targets": {
                "apple1": { "machine": "apple1", "environment": "bare", "cards": { "1": "mockingboard" } },
                "iiplus": { "machine": "apple2-iiplus", "environment": "bare" },
                "dos": { "machine": "apple2-iiplus", "environment": "dos33" } } }
            """);

        Write("main.s", "rts");
        using DapTestClient client = new();
        client.Request("initialize", []);

        JsonObject withSource = Launch("iiplus");
        withSource["source"] = Path.Join(_folder, "main.s");
        client.Fails("launch", withSource).Should().Contain("cannot give 'source'");

        JsonObject noTarget = Launch("iiplus");
        noTarget.Remove("target");
        client.Fails("launch", noTarget).Should().Contain("give target");

        client.Fails("launch", Launch("pet")).Should().Contain("There is no target 'pet'; the targets are");
        client.Fails("launch", Launch("apple1")).Should().EndWith("target apple1: apple1 has no slots for its cards.");
        client.Fails("launch", Launch("dos")).Should().EndWith("the 'dos33' environment is not yet supported; only 'bare' builds.");

        Write("main.s", "stz $00");
        client.Fails("launch", Launch("iiplus")).Should().Contain("target iiplus:").And.Contain("main.s(1)");

        // The machine the launch names gives way to the target's.
        Write("main.s", "rts");
        JsonObject named = Launch("iiplus");
        named["machine"] = "pet";
        client.Request("launch", named);
        client.Request("evaluate", new JsonObject
        {
            ["expression"] = "PC"
        }).String("result").Should().StartWith("$6000");
    }

    private JsonObject Launch(string target) => new()
    {
        ["project"] = _folder,
        ["target"] = target,
        ["controllers"] = false,
        ["sound"] = "off",
        ["speed"] = "max"
    };

    private string Write(string path, string text)
    {
        string file = Path.GetFullPath(Path.Join(_folder, path));
        Directory.CreateDirectory(Path.GetDirectoryName(file) ?? _folder);
        File.WriteAllText(file, text);
        return file;
    }
}