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
    ///  A bare target launches on a machine of each family at the address the build loaded it, and the launch says
    ///  which machine it started.
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
        JsonObject launched = client.Request("launch", Launch("t"));
        client.Request("evaluate", new JsonObject { ["expression"] = "PC" }).String("result")
            .Should().StartWith($"${catalog.LoadAddress:X}");

        ((string?)launched["project"]?["catalogMachine"]).Should().Be(machine);
        ((string?)launched["project"]?["machine"]).Should().Be(catalog.Machine);
        ((string?)launched["project"]?["model"]).Should().Be(catalog.Model);
        ((string?)launched["project"]?["rom"]).Should().Be(catalog.Rom);
        ((int?)launched["project"]?["entry"]).Should().Be(catalog.LoadAddress);
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
                "disk": { "machine": "apple2-iiplus", "environment": "bare", "cards": { "6": "diskII" } },
                "disk16": { "machine": "apple2-iiplus", "environment": "bare", "cards": { "6": "diskII16" } },
                "held": { "machine": "apple2-iie", "environment": "bare", "options": { "diskImage": "BOOT" }, "cards": { "7": "mouse" } },
                "held6": { "machine": "apple2-iiplus", "environment": "bare", "options": { "diskController": "diskII" }, "cards": { "6": "mockingboard" } },
                "dos": { "machine": "apple2-iiplus", "environment": "prodos" } } }
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
        client.Fails("launch", Launch("disk")).Should().EndWith(
            "target disk: slot 6's diskII comes with its media from the target's options, such as diskImage, not from its cards.");

        JsonObject sixteenSector = Launch("disk16");
        client.Fails("launch", sixteenSector).Should().Contain("slot 6's diskII16 comes with its media");

        File.WriteAllBytes(Path.Join(_folder, "boot.po"), new byte[143360]);
        Write("retrocore.json", File.ReadAllText(Path.Join(_folder, "retrocore.json")).Replace("BOOT", Path.Join(_folder, "boot.po").Replace('\\', '/'), StringComparison.Ordinal));
        client.Fails("launch", Launch("held")).Should().EndWith("target held: slot 7 holds the blockStorage its options give, so it cannot take mouse.");
        client.Fails("launch", Launch("held6")).Should().MatchRegex("target held6: slot 6 holds the diskII(16)? its options give, so it cannot take mockingboard\\.$");

        JsonObject longBoot = Launch("iiplus");
        longBoot["bootSeconds"] = 61;
        client.Fails("launch", longBoot).Should().Be("bootSeconds must be from 0 to 60.");

        JsonObject withExecutable = Launch("iiplus");
        withExecutable["executable"] = Path.Join(_folder, "game.xex");
        client.Fails("launch", withExecutable).Should().Contain("cannot give 'executable'");
        client.Fails("launch", Launch("dos")).Should().EndWith("the 'prodos' environment is not yet supported; only 'bare', 'wozmon', 'dos33', 'dfs' and 'basic' build.");

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

    /// <summary>
    ///  A <c>dos33</c> target's launch boots its disk in slot 6, from the SDK's Disk II firmware and DOS, on the II
    ///  (with the Autostart ROM) with Integer BASIC's HELLO, and on the II Plus and both IIe models with AppleSoft's, and stops at its entry
    ///  once HELLO has loaded the program: by BLOAD and CALL when the entry is past its first byte, by BRUN when it
    ///  is there. The program's data file is on the disk.
    /// </summary>
    /// <param name="machine">The catalog machine.</param>
    /// <param name="entry">The project's entry label.</param>
    [TestMethod]
    [DataRow("apple2-ii", "START")]
    [DataRow("apple2-iiplus", "START")]
    [DataRow("apple2-iiplus", "DATA")]
    [DataRow("apple2-iie", "START")]
    [DataRow("apple2-iie-enhanced", "START")]
    public void Dos33LaunchBootsItsDisk(string machine, string entry)
    {
        Write("retrocore.json", $$"""
            { "sdk": "1", "name": "game", "cpu": "6502", "sources": ["src/*.s"], "entry": "{{entry}}",
              "targets": { "dos": { "machine": "{{machine}}", "environment": "dos33", "files": [{ "path": "data.bin", "name": "DATA.BIN", "address": "$4000" }] } } }
            """);

        Write("src/main.s", "DATA:\n    nop\nSTART:\n    lda #1\nLoop:\n    jmp Loop\n");
        File.WriteAllBytes(Path.Join(_folder, "data.bin"), [1, 2, 3]);

        using DapTestClient client = new();
        client.Request("initialize", []);
        JsonObject launched = client.Request("launch", Launch("dos"));
        int address = entry == "DATA" ? 0x6000 : 0x6001;
        launched["project"]?["entry"]?.GetValue<int>().Should().Be(address);
        client.Request("evaluate", new JsonObject
        {
            ["expression"] = "PC"
        }).String("result").Should().StartWith($"${address:X4}");

        IReadOnlyList<Retrocore.Media.DosFile> files = Retrocore.Media.DosDisk.ReadFiles(
            File.ReadAllBytes(Path.Join(_folder, "artifacts", "dos", "game.dsk")));

        files.Select(file => file.Name).Should().Equal("HELLO", "GAME", "DATA.BIN");
        client.Request("configurationDone", []);
        client.Event("stopped").String("reason").Should().Be("entry");
    }

    /// <summary>
    ///  A <c>dfs</c> target's launch fits the disk interface, boots its disk holding SHIFT, and stops at its entry once
    ///  !BOOT has run the program, on the model B and on a model A, whose disk interface the launch fits.
    /// </summary>
    /// <param name="machine">The catalog machine.</param>
    [TestMethod]
    [DataRow("bbcb")]
    [DataRow("bbca")]
    public void DfsLaunchBootsItsDisk(string machine)
    {
        Write("retrocore.json", $$"""
            { "sdk": "1", "name": "game", "cpu": "6502", "sources": ["src/*.s"], "entry": "START",
              "targets": { "dfs": { "machine": "{{machine}}", "environment": "dfs" } } }
            """);

        Write("src/main.s", "DATA:\n    nop\nSTART:\n    lda #1\nLoop:\n    jmp Loop\n");
        using DapTestClient client = new();
        client.Request("initialize", []);
        client.Request("launch", Launch("dfs"))["project"]?["entry"]?.GetValue<int>().Should().Be(0x1901);
        client.Request("evaluate", new JsonObject
        {
            ["expression"] = "PC"
        }).String("result").Should().StartWith("$1901");

        client.Request("configurationDone", []);
        client.Event("stopped").String("reason").Should().Be("entry");
    }

    /// <summary>
    ///  A <c>dfs</c> target, or its launch, cannot give the disks, the boot or the disk interface its launch decides,
    ///  nor <c>bootSeconds</c>, as the machine boots its disk from power-on.
    /// </summary>
    /// <param name="option">The option.</param>
    /// <param name="value">Its value, as JSON.</param>
    /// <param name="inTarget">Whether the target's options give it, rather than the launch.</param>
    [TestMethod]
    [DataRow("disks", "[\"x.ssd\"]", true)]
    [DataRow("boot", "false", false)]
    [DataRow("diskInterface", "true", true)]
    [DataRow("bootSeconds", "1", false)]
    [DataRow("bootSeconds", "1", true)]
    public void DfsLaunchRefusesWhatItsDiskDecides(string option, string value, bool inTarget)
    {
        string options = inTarget ? $$""", "options": { "{{option}}": {{value}} }""" : "";
        Write("retrocore.json", $$"""
            { "sdk": "1", "name": "game", "cpu": "6502", "sources": ["src/*.s"],
              "targets": { "dfs": { "machine": "bbcb", "environment": "dfs"{{options}} } } }
            """);

        Write("src/main.s", "rts\n");
        using DapTestClient client = new();
        client.Request("initialize", []);
        JsonObject launch = Launch("dfs");
        if (!inTarget) { launch[option] = JsonNode.Parse(value); }
        client.Fails("launch", launch).Should().EndWith(option == "bootSeconds"
            ? "the 'dfs' environment boots its image from power-on, so its options and its launch cannot give 'bootSeconds'."
            : $"a dfs target boots its own disk in drive 0, so its options and its launch cannot give '{option}'.");
    }

    /// <summary>
    ///  A <c>basic</c> target's launch puts its tape in cassette 1 with PLAY down, types LOAD at BASIC's prompt and RUN
    ///  once the program is in, and stops at its entry, on BASIC 4, BASIC 2 and BASIC 1.
    /// </summary>
    /// <param name="machine">The catalog machine.</param>
    [TestMethod]
    [DataRow("pet4032")]
    [DataRow("pet2001-basic2")]
    [DataRow("pet2001")]
    public void BasicLaunchLoadsItsTape(string machine)
    {
        Write("retrocore.json", $$"""
            { "sdk": "1", "name": "game", "cpu": "6502", "sources": ["src/*.s"], "entry": "START",
              "targets": { "pet": { "machine": "{{machine}}", "environment": "basic" } } }
            """);

        Write("src/main.s", "DATA:\n    nop\nSTART:\n    lda #1\nLoop:\n    jmp Loop\n");
        using DapTestClient client = new();
        client.Request("initialize", []);
        client.Request("launch", Launch("pet"))["project"]?["entry"]?.GetValue<int>().Should().Be(0x0411);
        client.Request("evaluate", new JsonObject
        {
            ["expression"] = "PC"
        }).String("result").Should().StartWith("$411 ");

        client.Request("configurationDone", []);
        client.Event("stopped").String("reason").Should().Be("entry");
    }

    /// <summary>
    ///  A <c>basic</c> target, or its launch, cannot give the tape, disks or units its launch decides.
    /// </summary>
    /// <param name="option">The option.</param>
    /// <param name="value">Its value, as JSON.</param>
    /// <param name="inTarget">Whether the target's options give it, rather than the launch.</param>
    [TestMethod]
    [DataRow("cassette1", "\"x.tap\"", true)]
    [DataRow("cassette1", "\"x.tap\"", false)]
    [DataRow("disks", "[\"x.d64\"]", false)]
    [DataRow("diskUnits", "[8]", true)]
    [DataRow("diskModel", "\"2040\"", false)]
    public void BasicLaunchRefusesWhatItsMediaDecides(string option, string value, bool inTarget)
    {
        string options = inTarget ? $$""", "options": { "{{option}}": {{value}} }""" : "";
        Write("retrocore.json", $$"""
            { "sdk": "1", "name": "game", "cpu": "6502", "sources": ["src/*.s"], "entry": "START",
              "targets": { "tape": { "machine": "pet4032", "environment": "basic"{{options}} } } }
            """);

        Write("src/main.s", "DATA:\n    nop\nSTART:\n    lda #1\nLoop:\n    jmp Loop\n");
        using DapTestClient client = new();
        client.Request("initialize", []);
        JsonObject launch = Launch("tape");
        if (!inTarget) { launch[option] = JsonNode.Parse(value); }
        client.Fails("launch", launch).Should().EndWith(
            $"a basic target boots its own tape or disk, so its options and its launch cannot give '{option}'.");
    }

    /// <summary>
    ///  A <c>basic</c> target cannot boot its disk on BASIC 1's PET, whose IEEE-488 routines stop disk drives, nor name
    ///  as its <c>bootImage</c> what is not a folder.
    /// </summary>
    [TestMethod]
    public void BasicDiskLaunchRefusesBasic1AndAMissingFolder()
    {
        Write("retrocore.json", """
            { "sdk": "1", "name": "game", "cpu": "6502", "sources": ["src/*.s"],
              "targets": {
                "basic1": { "machine": "pet2001", "environment": "basic", "image": { "boot": "disk" } },
                "missing": { "machine": "pet4032", "environment": "basic", "image": { "boot": "disk" }, "bootImage": "no-such-folder" } } }
            """);

        Write("src/main.s", "rts\n");
        using DapTestClient client = new();
        client.Request("initialize", []);
        client.Fails("launch", Launch("basic1")).Should().EndWith(
            "BASIC 1's IEEE-488 routines have the bug that stops disk drives working, so it cannot boot its 4040 disk; boot the tape, or target a PET with BASIC 2 or 4.");

        client.Fails("launch", Launch("missing")).Should().EndWith(
            $"its 'bootImage', {Path.Join(_folder, "no-such-folder")}, is not a folder of the 4040's ROMs.");

        Action build = () => ProjectBuild.Build(RetrocoreProject.Load(_folder).Target("basic1"));
        build.Should().Throw<ProjectException>("the build refuses it too").WithMessage("*cannot boot its 4040 disk*");
    }

    /// <summary>
    ///  A <c>basic</c> target whose image boots its disk finds the 4040's ROMs by hash: without them its launch fails
    ///  naming them (and the test is inconclusive); with MAME's c4040 set in <c>RETROCORE_PET_ROMS</c> it boots the disk
    ///  in unit 8 to its entry.
    /// </summary>
    [TestMethod]
    public void BasicDiskLaunchBootsWithTheDrivesRoms()
    {
        string drive = Path.Join(PetMachineTests.RomRoot, "c4040");
        string bootImage = Directory.Exists(drive) ? $", \"bootImage\": \"{drive.Replace('\\', '/')}\"" : "";
        Write("retrocore.json", $$"""
            { "sdk": "1", "name": "game", "cpu": "6502", "sources": ["src/*.s"], "entry": "START",
              "targets": { "disk": { "machine": "pet4032", "environment": "basic", "image": { "boot": "disk" }{{bootImage}} } } }
            """);

        Write("src/main.s", "DATA:\n    nop\nSTART:\n    lda #1\nLoop:\n    jmp Loop\n");
        using DapTestClient client = new();
        client.Request("initialize", []);
        BootMediaSet set = BootMedia.Named(SdkModules.SdkDirectory, BasicEnvironment.DriveRoms);
        if (BootMedia.Find(set, BootMedia.Roots(set, drive)) is null)
        {
            client.Fails("launch", Launch("disk")).Should().Contain("it boots its 4040 disk, but the Commodore 4040 dual drive's ROMs");
            Assert.Inconclusive("Set RETROCORE_PET_ROMS to a folder with MAME's c4040 set unzipped to boot the 4040 disk.");
        }

        client.Request("launch", Launch("disk"));
        client.Request("evaluate", new JsonObject
        {
            ["expression"] = "PC"
        }).String("result").Should().StartWith("$411 ");
    }

    /// <summary>
    ///  On the Apple II, HELLO CALLs an entry at <c>$8000</c>, which Integer BASIC cannot write as a number, as
    ///  <c>-32767-1</c>, and the program starts there.
    /// </summary>
    [TestMethod]
    public void Dos33LaunchCallsAnEntryAt8000OnTheII()
    {
        Write("retrocore.json", """
            { "sdk": "1", "name": "game", "cpu": "6502", "sources": ["src/*.s"], "entry": "START",
              "targets": { "dos": { "machine": "apple2-ii", "environment": "dos33", "memoryMap": { "load": "$7FFF" } } } }
            """);

        Write("src/main.s", "DATA:\n    nop\nSTART:\n    lda #1\nLoop:\n    jmp Loop\n");
        using DapTestClient client = new();
        client.Request("initialize", []);
        client.Request("launch", Launch("dos"))["project"]?["entry"]?.GetValue<int>().Should().Be(0x8000);
        client.Request("evaluate", new JsonObject
        {
            ["expression"] = "PC"
        }).String("result").Should().StartWith("$8000");
    }

    /// <summary>
    ///  A <c>dos33</c> target, or its launch, cannot give the options of the Disk II its launch boots, nor launch with its
    ///  image off, nor on the Apple II's original Monitor, which boots no disk.
    /// </summary>
    [TestMethod]
    public void Dos33LaunchRefusesWhatItsDiskDecides()
    {
        Write("retrocore.json", """
            { "sdk": "1", "name": "game", "cpu": "6502", "sources": ["src/*.s"],
              "targets": {
                "image": { "machine": "apple2-iiplus", "environment": "dos33", "options": { "diskImage": "x.dsk" } },
                "none": { "machine": "apple2-iiplus", "environment": "dos33", "image": false },
                "original": { "machine": "apple2-ii", "environment": "dos33", "options": { "monitor": "original" } } } }
            """);

        Write("src/main.s", "rts\n");
        using DapTestClient client = new();
        client.Request("initialize", []);
        client.Fails("launch", Launch("image")).Should().EndWith(
            "a dos33 target boots its own disk in slot 6's 16-sector Disk II, so its options and its launch cannot give 'diskImage'.");

        JsonObject thirteen = Launch("none");
        thirteen["diskSectors"] = 13;
        client.Fails("launch", thirteen).Should().EndWith(
            "a dos33 target boots its own disk in slot 6's 16-sector Disk II, so its options and its launch cannot give 'diskSectors'.");

        client.Fails("launch", Launch("none")).Should().EndWith("the 'dos33' environment boots its image, so its image cannot be false to launch it.");
        client.Fails("launch", Launch("original")).Should().EndWith(
            "a dos33 target boots its disk as the machine powers on, which the Apple II's original Monitor does not do; leave out 'monitor', or give 'autostart'.");
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