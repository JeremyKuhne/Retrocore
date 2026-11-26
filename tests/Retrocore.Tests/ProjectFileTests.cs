// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Debug.Project;

namespace Retrocore.Tests;

/// <summary>
///  <c>retrocore.json</c> loads as the SDK plan describes it: its fields, root files that list projects, targets and
///  their CPUs, platform folders, and the errors for what is wrong or not supported yet.
/// </summary>
[TestClass]
public sealed class ProjectFileTests
{
    private string _folder = "";

    /// <summary>
    ///  Gets each test a folder of its own.
    /// </summary>
    [TestInitialize]
    public void Initialize()
    {
        _folder = Path.Join(Path.GetTempPath(), "retrocore-project-" + Guid.NewGuid().ToString("N"));
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
    ///  Every field of a project and its targets loads, with comments and trailing commas allowed.
    /// </summary>
    [TestMethod]
    public void ProjectLoadsEveryField()
    {
        Write("retrocore.json", """
            // The adventure's project.
            {
              "$schema": "https://retrocore.dev/schemas/project-1.json",
              "sdk": "1",
              "name": "adventure",
              "cpu": "6502",
              "sources": ["src/core/*.s", { "path": "src/merlin.s", "dialect": "merlin", "kind": "asm" }],
              "defines": { "DEBUG": true, "COLUMNS": 40, "SCREEN": "$0400", "MASK": "0x7F" },
              "entry": "start",
              "output": "out",
              "targets": {
                "apple2-bare": {
                  "machine": "apple2-iie-enhanced",
                  "environment": "bare",
                  "cpu": "r65c02",
                  "options": { "ramKilobytes": 64, "sound": "mockingboard" },
                  "cards": { "4": "mockingboard" },
                  "defines": { "COLUMNS": 80 },
                  "sources": ["src/iie.s"],
                  "linkerConfiguration": "link.cfg",
                },
              },
            }
            """);

        RetrocoreProject project = RetrocoreProject.Load(_folder);
        project.Sdk.Should().Be("1");
        project.Name.Should().Be("adventure");
        project.Cpu.Should().BeSameAs(ProjectCpu.Mos6502);
        project.Sources.Should().Equal(new ProjectSource("src/core/*.s", Dialect: null), new ProjectSource("src/merlin.s", AssemblyDialect.Merlin));
        project.Defines.Should().BeEquivalentTo(new Dictionary<string, long>
        {
            ["DEBUG"] = 1, ["COLUMNS"] = 40, ["SCREEN"] = 0x400, ["MASK"] = 0x7F
        });

        project.Entry.Should().Be("start");
        project.Output.Should().Be(Path.Join(_folder, "out"));
        project.Intermediate.Should().Be(Path.Join(_folder, "obj"));
        project.Unsupported.Should().BeEmpty();

        ProjectTarget target = project.Target("apple2-bare");
        target.Machine.Should().Be(CatalogMachine.Find("apple2-iie-enhanced"));
        target.Environment.Should().Be("bare");
        target.Cpu.Should().BeSameAs(ProjectCpu.Rockwell65C02);
        target.Options.ToJsonString().Should().Be("""{"ramKilobytes":64,"sound":"mockingboard"}""");
        target.Cards?.ToJsonString().Should().Be("""{"4":"mockingboard"}""");
        target.Sources.Should().Equal(new ProjectSource("src/iie.s", Dialect: null));
        target.LinkerConfiguration.Should().Be(Path.Join(_folder, "link.cfg"));
        target.Symbols().Should().BeEquivalentTo(new Dictionary<string, long>
        {
            ["DEBUG"] = 1, ["COLUMNS"] = 80, ["SCREEN"] = 0x400, ["MASK"] = 0x7F
        });

        target.RequireSupported();
    }

    /// <summary>
    ///  A project's name defaults to its folder's, its output to artifacts, and its targets keep the file's order.
    /// </summary>
    [TestMethod]
    public void DefaultsComeFromTheFolder()
    {
        string folder = Path.Join(_folder, "game");
        Write("game/retrocore.json", """
            { "sdk": "1", "cpu": "6502", "targets": {
                "b": { "machine": "apple1", "environment": "bare" },
                "a": { "machine": "pet4032", "environment": "bare" } } }
            """);

        RetrocoreProject project = RetrocoreProject.Load(Path.Join(folder, "retrocore.json"));
        project.Name.Should().Be("game");
        project.Output.Should().Be(Path.Join(folder, "artifacts"));
        project.Targets.Select(target => target.Name).Should().Equal("b", "a");
        project.Target("a").Cpu.Should().BeSameAs(ProjectCpu.Mos6502);
        project.Target("a").Cards.Should().BeNull();
    }

    /// <summary>
    ///  A root file lists its projects' folders, each loaded from its own file in the root's order.
    /// </summary>
    [TestMethod]
    public void RootFileListsProjects()
    {
        Write("retrocore.json", """{ "projects": ["interpreter", "tools/editor"] }""");
        Write("interpreter/retrocore.json", """{ "sdk": "1", "cpu": "6502", "targets": { "t": { "machine": "bbcb", "environment": "bare" } } }""");
        Write("tools/editor/retrocore.json", """{ "sdk": "1", "cpu": "z80", "targets": { "t": { "machine": "kaypro2", "environment": "bare" } } }""");

        List<RetrocoreProject> projects = RetrocoreProject.LoadAll(_folder);
        projects.Select(project => project.Name).Should().Equal("interpreter", "editor");
        projects[1].Directory.Should().Be(Path.Join(_folder, "tools", "editor"));

        Error(() => RetrocoreProject.Load(_folder)).Should().Contain("lists projects");
        RetrocoreProject.LoadAll(Path.Join(_folder, "interpreter")).Should().ContainSingle();
    }

    /// <summary>
    ///  A root file's mistakes are errors: a nested list, a missing project, other fields, an empty list.
    /// </summary>
    [TestMethod]
    public void RootFileErrors()
    {
        Write("retrocore.json", """{ "projects": ["a"] }""");
        Error(() => RetrocoreProject.LoadAll(_folder)).Should().Contain("the project 'a' has no retrocore.json");

        Write("a/retrocore.json", """{ "projects": ["b"] }""");
        Error(() => RetrocoreProject.LoadAll(_folder)).Should().Contain("only the repository's root file lists projects");

        Write("retrocore.json", """{ "projects": ["a"], "sdk": "1" }""");
        Error(() => RetrocoreProject.LoadAll(_folder)).Should().Contain("has no field 'sdk'");

        Write("retrocore.json", """{ "projects": [] }""");
        Error(() => RetrocoreProject.LoadAll(_folder)).Should().Contain("'projects' must list");
    }

    /// <summary>
    ///  Each malformed project names its file and what is wrong.
    /// </summary>
    /// <param name="json">The project file.</param>
    /// <param name="message">Part of the error.</param>
    [TestMethod]
    [DataRow("""{ "cpu": "6502", "targets": { "t": { "machine": "apple1", "environment": "bare" } } }""", "must give 'sdk'")]
    [DataRow("""{ "sdk": "2", "cpu": "6502", "targets": { "t": { "machine": "apple1", "environment": "bare" } } }""", "written for SDK 2; this tool builds SDK 1")]
    [DataRow("""{ "sdk": "1", "targets": { "t": { "machine": "apple1", "environment": "bare" } } }""", "must give 'cpu'")]
    [DataRow("""{ "sdk": "1", "cpu": "68000", "targets": { "t": { "machine": "apple1", "environment": "bare" } } }""", "there is no CPU '68000'")]
    [DataRow("""{ "sdk": "1", "cpu": "6502" }""", "must give 'targets'")]
    [DataRow("""{ "sdk": "1", "cpu": "6502", "targets": {} }""", "must give 'targets'")]
    [DataRow("""{ "sdk": "1", "cpu": "6502", "target": {} }""", "has no field 'target'")]
    [DataRow("""{ "sdk": "1", "cpu": "6502", "name": "a/b", "targets": { "t": { "machine": "apple1", "environment": "bare" } } }""", "the name 'a/b' must be letters")]
    [DataRow("""{ "sdk": "1", "cpu": "6502", "name": "..", "targets": { "t": { "machine": "apple1", "environment": "bare" } } }""", "the name '..' must be letters")]
    [DataRow("""{ "sdk": "1", "cpu": "6502", "name": "a:b", "targets": { "t": { "machine": "apple1", "environment": "bare" } } }""", "the name 'a:b' must be letters")]
    [DataRow("""{ "sdk": "1", "cpu": "6502", "targets": { "t": { "machine": "pet4032", "environment": "wozmon" } } }""", "pet4032 does not run the 'wozmon' environment")]
    [DataRow("""{ "sdk": "1", "cpu": "6502", "defines": { "@A": 1 }, "targets": { "t": { "machine": "apple1", "environment": "bare" } } }""", "define @A = 1 must name a symbol")]
    [DataRow("""{ "sdk": "1", "cpu": "6502", "targets": { "t": { "environment": "bare" } } }""", "target t must give 'machine'")]
    [DataRow("""{ "sdk": "1", "cpu": "6502", "targets": { "t": { "machine": "apple2" , "environment": "bare" } } }""", "there is no machine 'apple2'")]
    [DataRow("""{ "sdk": "1", "cpu": "6502", "targets": { "t": { "machine": "apple1" } } }""", "target t must give 'environment'")]
    [DataRow("""{ "sdk": "1", "cpu": "6502", "targets": { "t": { "machine": "apple1", "environment": "os9" } } }""", "there is no environment 'os9'")]
    [DataRow("""{ "sdk": "1", "cpu": "6502", "targets": { "t": { "machine": "apple1", "environment": "bare", "disk": 1 } } }""", "target t has no field 'disk'")]
    [DataRow("""{ "sdk": "1", "cpu": "6502", "targets": { "a b": { "machine": "apple1", "environment": "bare" } } }""", "the target name 'a b'")]
    [DataRow("""{ "sdk": "1", "cpu": "65c02", "targets": { "t": { "machine": "apple2-iie-enhanced", "environment": "bare", "cpu": "6502" } } }""", "its CPU, 6502, does not run the project's 65c02 code")]
    [DataRow("""{ "sdk": "1", "cpu": "Z80", "targets": { "t": { "machine": "kaypro2", "environment": "bare" } } }""", "there is no CPU 'Z80'")]
    [DataRow("""{ "sdk": "1", "cpu": "Mos6502", "targets": { "t": { "machine": "apple1", "environment": "bare" } } }""", "there is no CPU 'Mos6502'")]
    [DataRow("""{ "sdk": "1", "sdk": "1", "cpu": "6502", "targets": { "t": { "machine": "apple1", "environment": "bare" } } }""", "a field is given twice")]
    [DataRow("""{ "sdk": "1", "cpu": "6502", "entry": null, "targets": { "t": { "machine": "apple1", "environment": "bare" } } }""", "the project's 'entry' is null")]
    [DataRow("""{ "sdk": "1", "cpu": "6502", "targets": { "t": { "machine": "apple1", "environment": "bare", "options": { "entryAddress": 1 } } } }""", "cannot give 'entryAddress'")]
    [DataRow("""{ "sdk": "1", "cpu": "6502", "targets": { "..": { "machine": "apple1", "environment": "bare" } } }""", "the target name '..'")]
    [DataRow("""{ "sdk": "1", "cpu": "65c02", "targets": { "t": { "machine": "apple2-iiplus", "environment": "bare" } } }""", "apple2-iiplus's 6502 does not run 65c02 code")]
    [DataRow("""{ "sdk": "1", "cpu": "6502", "targets": { "t": { "machine": "apple2-iie-enhanced", "environment": "bare", "cpu": "w65c02" } } }""", "apple2-iie-enhanced's r65c02 does not run w65c02 code")]
    [DataRow("""{ "sdk": "1", "cpu": "z80", "targets": { "t": { "machine": "altair", "environment": "bare" } } }""", "altair's 8080 does not run z80 code")]
    [DataRow("""{ "sdk": "1", "cpu": "6502", "targets": { "t": { "machine": "apple1", "environment": "bare", "options": { "model": "x" } } } }""", "cannot give 'model'")]
    [DataRow("""{ "sdk": "1", "cpu": "6502", "targets": { "t": { "machine": "apple1", "environment": "bare", "options": 1 } } }""", "'options' must be an object")]
    [DataRow("""{ "sdk": "1", "cpu": "6502", "targets": { "t": { "machine": "apple2-iie", "environment": "bare", "cards": { "4": 1 } } } }""", "card in slot 4 must be a card's name")]
    [DataRow("""{ "sdk": "1", "cpu": "6502", "defines": { "RC_SDK": 2 }, "targets": { "t": { "machine": "apple1", "environment": "bare" } } }""", "names starting with RC_ are the SDK's")]
    [DataRow("""{ "sdk": "1", "cpu": "6502", "defines": { "A": 1.5 }, "targets": { "t": { "machine": "apple1", "environment": "bare" } } }""", "define A = 1.5 must")]
    [DataRow("""{ "sdk": "1", "cpu": "6502", "defines": { "A": null }, "targets": { "t": { "machine": "apple1", "environment": "bare" } } }""", "A must be a number")]
    [DataRow("""{ "sdk": "1", "cpu": "6502", "defines": { "1A": 1 }, "targets": { "t": { "machine": "apple1", "environment": "bare" } } }""", "define 1A = 1 must name a symbol")]
    [DataRow("""{ "sdk": "1", "cpu": "6502", "sources": "a.s", "targets": { "t": { "machine": "apple1", "environment": "bare" } } }""", "'sources' must be a list")]
    [DataRow("""{ "sdk": "1", "cpu": "6502", "sources": [{ "dialect": "ca65" }], "targets": { "t": { "machine": "apple1", "environment": "bare" } } }""", "must give 'path'")]
    [DataRow("""{ "sdk": "1", "cpu": "6502", "sources": [{ "path": "a.s", "kind": "assembly" }], "targets": { "t": { "machine": "apple1", "environment": "bare" } } }""", "there is no source kind 'assembly'")]
    [DataRow("""{ "sdk": "1", "cpu": "6502", "sources": [{ "path": "a.s", "dialect": "CA65" }], "targets": { "t": { "machine": "apple1", "environment": "bare" } } }""", "there is no dialect 'CA65'")]
    [DataRow("""{ "sdk": "1", "cpu": "6502", "sources": [{ "path": "a.s", "dialect": "tasm" }], "targets": { "t": { "machine": "apple1", "environment": "bare" } } }""", "there is no dialect 'tasm'")]
    [DataRow("""{ "sdk": "1", "cpu": "6502", "targets": { "t": { "machine": "apple1", "environment": "bare" } }, }x""", "retrocore.json: ")]
    [DataRow("""[1]""", "must hold a JSON object")]
    public void MalformedProjectsAreErrors(string json, string message)
    {
        Write("retrocore.json", json);
        string error = Error(() => RetrocoreProject.Load(_folder));
        error.Should().Contain(message);
        error.Should().StartWith(Path.Join(_folder, "retrocore.json"));
    }

    /// <summary>
    ///  A missing project file is an error that names it.
    /// </summary>
    [TestMethod]
    public void MissingFileIsAnError() =>
        Error(() => RetrocoreProject.Load(_folder)).Should().Be($"{Path.Join(_folder, "retrocore.json")} does not exist.");

    /// <summary>
    ///  CPUs follow supersets: a target can raise the project's CPU to one its machine runs, and an 8080 project
    ///  builds for a Z80 machine.
    /// </summary>
    [TestMethod]
    public void CpusFollowSupersets()
    {
        Write("retrocore.json", """
            { "sdk": "1", "cpu": "8080", "targets": {
                "altair": { "machine": "altair", "environment": "bare" },
                "kaypro": { "machine": "kaypro2", "environment": "bare" },
                "kaypro-z80": { "machine": "kaypro2", "environment": "bare", "cpu": "z80" } } }
            """);

        RetrocoreProject project = RetrocoreProject.Load(_folder);
        project.Target("altair").Cpu.Should().BeSameAs(ProjectCpu.I8080);
        project.Target("kaypro").Cpu.Should().BeSameAs(ProjectCpu.I8080);
        project.Target("kaypro-z80").Cpu.Should().BeSameAs(ProjectCpu.Z80);

        ProjectCpu.Wdc65C02.Runs(ProjectCpu.Rockwell65C02).Should().BeTrue();
        ProjectCpu.Rockwell65C02.Runs(ProjectCpu.Cmos65C02).Should().BeTrue();
        ProjectCpu.Cmos65C02.Runs(ProjectCpu.Mos6502).Should().BeTrue();
        ProjectCpu.Mos6502.Runs(ProjectCpu.Cmos65C02).Should().BeFalse();
        ProjectCpu.Z80.Runs(ProjectCpu.I8085).Should().BeFalse();
        ProjectCpu.M6809.Runs(ProjectCpu.Mos6502).Should().BeFalse();
    }

    /// <summary>
    ///  Every CPU's instruction set is one the assembler's <c>.cpu</c> selects.
    /// </summary>
    [TestMethod]
    public void CpusAreTheAssemblers()
    {
        foreach (ProjectCpu cpu in ProjectCpu.All)
        {
            CpuCatalog.InstructionSets.Should().ContainKey(cpu.AssemblerName);
            ProjectCpu.Find(cpu.AssemblerName).Should().BeSameAs(cpu);
            ProjectCpu.Find(cpu.Name.ToUpperInvariant()).Should().BeSameAs(cpu);
        }
    }

    /// <summary>
    ///  Fields the plan has but the host does not build yet load, and building with them fails naming each.
    /// </summary>
    [TestMethod]
    public void UnsupportedFieldsFailTheBuild()
    {
        Write("retrocore.json", """
            { "sdk": "1", "cpu": "6502", "steps": [], "targets": {
                "plain": { "machine": "apple2-iiplus", "environment": "bare" },
                "disk": { "machine": "apple2-iiplus", "environment": "dos33", "files": [], "image": false, "memoryMap": {}, "bootImage": "x" } } }
            """);

        RetrocoreProject project = RetrocoreProject.Load(_folder);
        Error(project.Target("plain").RequireSupported).Should().EndWith(
            "target plain: the project's 'steps' is not yet supported.");

        Error(project.Target("disk").RequireSupported).Should().EndWith(
            "target disk: the project's 'steps' is not yet supported; 'memoryMap' is not yet supported; "
                + "'files' is not yet supported; 'image' is not yet supported; 'bootImage' is not yet supported; "
                + "the 'dos33' environment is not yet supported; only 'bare' builds.");
    }

    /// <summary>
    ///  A source of a kind that does not build yet loads, and fails only the builds that assemble it.
    /// </summary>
    [TestMethod]
    public void BasicSourcesFailOnlyTheirTargets()
    {
        Write("retrocore.json", """
            { "sdk": "1", "cpu": "6502", "targets": {
                "plain": { "machine": "apple2-iiplus", "environment": "bare" },
                "menu": { "machine": "apple2-iiplus", "environment": "bare", "sources": [{ "path": "menu.bas", "kind": "basic" }] } } }
            """);

        RetrocoreProject project = RetrocoreProject.Load(_folder);
        project.Target("plain").RequireSupported();
        Error(project.Target("menu").RequireSupported).Should().EndWith(
            "target menu: the source 'menu.bas' is basic, which is not yet supported.");
    }

    /// <summary>
    ///  Each environment pairs with the machines the SDK plan gives it, and every machine runs bare.
    /// </summary>
    [TestMethod]
    public void EnvironmentsPairWithTheirMachines()
    {
        foreach (CatalogMachine machine in CatalogMachine.All)
        {
            ProjectTarget.Runs(machine, "bare").Should().BeTrue(machine.Id);
        }

        foreach (string environment in ProjectTarget.Environments)
        {
            CatalogMachine.All.Should().Contain(machine => ProjectTarget.Runs(machine, environment), environment);
        }

        ProjectTarget.Runs(Machine("apple2-iiplus"), "dos33").Should().BeTrue();
        ProjectTarget.Runs(Machine("apple2-ii"), "prodos").Should().BeFalse();
        ProjectTarget.Runs(Machine("bbcb"), "dos33").Should().BeFalse();
    }

    /// <summary>
    ///  A model's platform files sort in ordinal order on every system, so every build assembles them alike.
    /// </summary>
    [TestMethod]
    public void PlatformFilesSortTheSameEverywhere()
    {
        Write("retrocore.json", """{ "sdk": "1", "cpu": "6502", "targets": { "t": { "machine": "apple2-iie", "environment": "bare" } } }""");
        Write("src/platform/apple2/alpha.s", "");
        Write("src/platform/apple2/Zed.s", "");
        Write("src/platform/apple2-iie/beta.s", "");
        Write("src/platform/apple2-iie/Able.s", "");
        Relative(RetrocoreProject.Load(_folder).Target("t")).Should().Equal(
            "src/platform/apple2/Zed.s", "src/platform/apple2/alpha.s", "src/platform/apple2-iie/Able.s", "src/platform/apple2-iie/beta.s");
    }

    /// <summary>
    ///  An unknown target's error lists the targets there are.
    /// </summary>
    [TestMethod]
    public void UnknownTargetListsTheTargets()
    {
        Write("retrocore.json", """
            { "sdk": "1", "cpu": "6502", "targets": {
                "one": { "machine": "apple1", "environment": "bare" }, "two": { "machine": "apple1", "environment": "bare" } } }
            """);

        Error(() => RetrocoreProject.Load(_folder).Target("three")).Should().EndWith(
            "there is no target 'three'; the targets are one, two.");
    }

    /// <summary>
    ///  A target assembles the project's sources, then its family's platform folder, then its model's, a model's
    ///  file taking the place of its family's file of the same name, then its own sources; a file named twice comes
    ///  once, where it first does.
    /// </summary>
    [TestMethod]
    public void PlatformFoldersReplaceByName()
    {
        Write("retrocore.json", """
            { "sdk": "1", "cpu": "6502", "sources": ["src/core/**/*.s", "src/core/main.s"], "targets": {
                "iie": { "machine": "apple2-iie", "environment": "bare", "sources": ["src/extra.asm", { "path": "src/ca65.s", "dialect": "ca65" }] },
                "iiplus": { "machine": "apple2-iiplus", "environment": "bare" },
                "pet": { "machine": "pet4032", "environment": "bare" } } }
            """);

        Write("src/core/main.s", "");
        Write("src/core/parse/words.s", "");
        Write("src/core/notes.txt", "");
        Write("src/platform/apple2/console.s", "");
        Write("src/platform/apple2/disk.asm", "");
        Write("src/platform/apple2/apple2.inc", "");
        Write("src/platform/apple2-iie/console.s", "");
        Write("src/platform/apple2-iie/columns.s", "");
        Write("src/extra.asm", "");
        Write("src/ca65.s", "");

        RetrocoreProject project = RetrocoreProject.Load(_folder);
        Relative(project.Target("iie")).Should().Equal(
            "src/core/main.s",
            "src/core/parse/words.s",
            "src/platform/apple2-iie/console.s",
            "src/platform/apple2/disk.asm",
            "src/platform/apple2-iie/columns.s",
            "src/extra.asm",
            "src/ca65.s");

        project.Target("iie").SourceFiles()[^1].Dialect.Should().Be(AssemblyDialect.Ca65);
        Relative(project.Target("iiplus")).Should().Equal(
            "src/core/main.s", "src/core/parse/words.s", "src/platform/apple2/console.s", "src/platform/apple2/disk.asm");

        Relative(project.Target("pet")).Should().Equal("src/core/main.s", "src/core/parse/words.s");
    }

    /// <summary>
    ///  A missing source, a pattern that matches nothing and a target with no sources are errors naming the target.
    /// </summary>
    [TestMethod]
    public void MissingSourcesAreErrors()
    {
        Write("retrocore.json", """
            { "sdk": "1", "cpu": "6502", "targets": {
                "none": { "machine": "apple1", "environment": "bare" },
                "missing": { "machine": "apple1", "environment": "bare", "sources": ["nope.s"] },
                "empty": { "machine": "apple1", "environment": "bare", "sources": ["src/*.s"] } } }
            """);

        RetrocoreProject project = RetrocoreProject.Load(_folder);
        Error(() => project.Target("none").SourceFiles()).Should().EndWith("target none has no sources.");
        Error(() => project.Target("missing").SourceFiles()).Should().EndWith("target missing: the source 'nope.s' does not exist.");
        Error(() => project.Target("empty").SourceFiles()).Should().EndWith("target empty: the sources 'src/*.s' match no files.");
    }

    /// <summary>
    ///  Patterns match <c>*</c> and <c>?</c> within a name, ignoring case, and <c>**</c> across folders.
    /// </summary>
    /// <param name="pattern">The pattern part.</param>
    /// <param name="name">The name.</param>
    /// <param name="matches">Whether it matches.</param>
    [TestMethod]
    [DataRow("*.s", "main.s", true)]
    [DataRow("*.s", "main.asm", false)]
    [DataRow("m?in.*", "main.s", true)]
    [DataRow("m?in.*", "mn.s", false)]
    [DataRow("*", "", true)]
    [DataRow("a*b*c", "aXbYc", true)]
    [DataRow("a*b*c", "aXbY", false)]
    public void PatternsMatchNames(string pattern, string name, bool matches) =>
        ProjectGlob.Matches(pattern, name).Should().Be(matches);

    /// <summary>
    ///  Patterns ignore case where file names do, on Windows and macOS, and not on Linux.
    /// </summary>
    [TestMethod]
    public void PatternsFollowTheFileSystemsCase() =>
        ProjectGlob.Matches("*.s", "main.S").Should().Be(OperatingSystem.IsWindows() || OperatingSystem.IsMacOS());

    private static CatalogMachine Machine(string id) =>
        CatalogMachine.Find(id) ?? throw new AssertFailedException($"There is no machine {id}.");

    private List<string> Relative(ProjectTarget target) =>
        [.. target.SourceFiles().Select(file => Path.GetRelativePath(_folder, file.Path).Replace('\\', '/'))];

    private void Write(string path, string text)
    {
        string file = Path.Join(_folder, path);
        Directory.CreateDirectory(Path.GetDirectoryName(file) ?? _folder);
        File.WriteAllText(file, text);
    }

    private static string Error(Action action)
    {
        try
        {
            action();
        }
        catch (ProjectException exception)
        {
            return exception.Message;
        }

        throw new AssertFailedException("Expected a ProjectException.");
    }

    private static string Error(Func<object> action) => Error(() => { _ = action(); });
}