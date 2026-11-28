// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug;
using Retrocore.Debug.Project;
using Retrocore.Media;
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
                "held6": { "machine": "apple2-iiplus", "environment": "bare", "options": { "diskController": "diskII" }, "cards": { "6": "mockingboard" } } } }
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

        Write("main.s", "stz $00");
        client.Fails("launch", Launch("iiplus")).Should().Contain("target iiplus:").And.Contain("main.s(1)");

        // An environment that does not build yet fails the launch, as its build does.
        string project = File.ReadAllText(Path.Join(_folder, "retrocore.json"));
        Write("main.s", "ret");
        Write("retrocore.json", """
            { "sdk": "1", "cpu": "z80", "sources": ["main.s"], "targets": { "dos": { "machine": "trs80-model3", "environment": "trsdos" } } }
            """);

        client.Fails("launch", Launch("dos")).Should().EndWith("the 'trsdos' environment is not yet supported; only 'bare', 'wozmon', 'dos33', 'dfs', 'basic', 'sos', 'prodos', 'level2', 'colorbasic', 'diskbasic' and 'cpm' build.");
        Write("retrocore.json", project);

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
    ///  A <c>prodos</c> target's launch boots its disk in slot 6, ProDOS 2.4.3's boot blocks and PRODOS found by the
    ///  disk's hash, on the II Plus with its language card and on both IIe models: ProDOS starts the system file at its
    ///  first byte, whose <c>JMP</c> goes on to the entry, where the launch stops, with the program's data file on the
    ///  disk. Without ProDOS 2.4.3 the launch fails naming it, so the test is inconclusive.
    /// </summary>
    /// <param name="machine">The catalog machine.</param>
    [TestMethod]
    [DataRow("apple2-iiplus")]
    [DataRow("apple2-iie")]
    [DataRow("apple2-iie-enhanced")]
    public void ProdosLaunchBootsItsDisk(string machine)
    {
        Write("retrocore.json", $$"""
            { "sdk": "1", "name": "game", "cpu": "6502", "sources": ["src/*.s"], "entry": "START",
              "targets": { "prodos": { "machine": "{{machine}}", "environment": "prodos", "files": [{ "path": "data.bin", "name": "DATA.BIN", "address": "$4000" }] } } }
            """);

        string main = Write("src/main.s", "    jmp START\nSTART:\n    lda #1\nLoop:\n    jmp Loop\n");
        File.WriteAllBytes(Path.Join(_folder, "data.bin"), [1, 2, 3]);

        using DapTestClient client = new();
        client.Request("initialize", []);
        JsonObject launch = Launch("prodos");
        launch["checkContracts"] = "stop";
        JsonObject? launched = client.TryRequest("launch", launch, out string? failure);
        if (launched is null)
        {
            failure.Should().Contain("ProDOS 2.4.3's disk").And.Contain("was not found by its hash");
            Assert.Inconclusive($"ProDOS 2.4.3's disk was not found: {failure}");
        }

        launched["project"]?["entry"]?.GetValue<int>().Should().Be(0x2003);
        client.Request("evaluate", new JsonObject
        {
            ["expression"] = "PC"
        }).String("result").Should().StartWith("$2003");

        SosVolume volume = SosVolume.Read(File.ReadAllBytes(Path.Join(_folder, "artifacts", "prodos", "game.po")), proDosOrder: true);
        volume.Files.Select(file => file.Name).Should().Equal("PRODOS", "GAME.SYSTEM", "DATA.BIN");
        JsonObject set = client.Request("setBreakpoints", new JsonObject
        {
            ["source"] = new JsonObject { ["path"] = main },
            ["breakpoints"] = new JsonArray(new JsonObject { ["line"] = 5 })
        });

        (set["breakpoints"]?[0]?["verified"]?.GetValue<bool>()).Should().BeTrue();
        client.Request("configurationDone", []);
        client.Event("stopped").String("reason").Should().Be("entry");
        client.Request("continue", new JsonObject { ["threadId"] = 1 });
        client.Event("stopped").String("reason").Should().Be("breakpoint", "the program's lines are mapped where ProDOS loads it");
    }

    /// <summary>
    ///  A <c>prodos</c> target on the II Plus keeps its language card in slot 0, which ProDOS runs in, and no target or
    ///  launch gives the Disk II's options, as the launch boots its own disk.
    /// </summary>
    /// <param name="option">The option.</param>
    /// <param name="value">Its value, as JSON.</param>
    /// <param name="refusal">How the launch's error ends.</param>
    [TestMethod]
    [DataRow("slot0", "\"firmwareCard\"", "ProDOS needs 64K, which the II Plus has with its language card in slot 0, so a prodos target's options and its launch cannot give 'slot0' firmwareCard.")]
    [DataRow("diskImage", "\"x.dsk\"", "a prodos target boots its own disk in slot 6's 16-sector Disk II, so its options and its launch cannot give 'diskImage'.")]
    [DataRow("bootSeconds", "1", "the 'prodos' environment boots its image from power-on, so its options and its launch cannot give 'bootSeconds'.")]
    public void ProdosLaunchRefusesWhatItsDiskDecides(string option, string value, string refusal)
    {
        Write("retrocore.json", $$"""
            { "sdk": "1", "name": "game", "cpu": "6502", "sources": ["src/*.s"],
              "targets": { "prodos": { "machine": "apple2-iiplus", "environment": "prodos", "options": { "{{option}}": {{value}} } } } }
            """);

        Write("src/main.s", "rts\n");
        using DapTestClient client = new();
        client.Request("initialize", []);
        string failure = client.Fails("launch", Launch("prodos"));

        // Without ProDOS 2.4.3 the launch says so after the options it refuses first.
        if (option == "bootSeconds" && failure.Contains("was not found by its hash", StringComparison.Ordinal))
        {
            Assert.Inconclusive($"ProDOS 2.4.3's disk was not found: {failure}");
        }

        failure.Should().EndWith(refusal);
    }

    /// <summary>
    ///  A <c>level2</c> target's launch puts its SYSTEM tape in the cassette recorder and boots the machine with no
    ///  disk: it answers the ROM's start-up questions, types SYSTEM, the tape's name and then <c>/</c>, and stops at the
    ///  entry, on the Model I with Level II 1.3 and 1.2, whose MEMORY SIZE? differ, and on the Model III, which asks
    ///  Cass? first. The program, 4K, plays for over a minute of the machine's time. It then shows its line, and a
    ///  breakpoint in its source stops.
    /// </summary>
    /// <param name="machine">The catalog machine.</param>
    /// <param name="options">The target's options, as JSON.</param>
    [TestMethod]
    [DataRow("trs80-model1-level2", "{}")]
    [DataRow("trs80-model1-level2", "{ \"revision\": \"1.2\" }")]
    [DataRow("trs80-model3", "{}")]
    public void Level2LaunchBootsItsTape(string machine, string options)
    {
        Write("retrocore.json", $$"""
            { "sdk": "1", "name": "hello", "cpu": "z80", "sources": ["src/*.s"], "entry": "START",
              "targets": { "tape": { "machine": "{{machine}}", "environment": "level2", "options": {{options}} },
                           "own": { "machine": "{{machine}}", "environment": "level2", "options": { "cassette": "x.cas" } },
                           "disk": { "machine": "{{machine}}", "environment": "level2", "options": { "diskController": true } } } }
            """);

        string main = Write("src/main.s", """
            .include <machine.inc>
            MESSAGE:
                .byte "LOADED FROM TAPE", RETURN, 0
            START:
                LD HL,MESSAGE
            NEXT:
                LD A,[HL]
                OR A
                JR Z,DONE
                CALL DisplayCharacter
                INC HL
                JR NEXT
            DONE:
                JR DONE

            ; Data after the code, so the tape plays for over a minute of the machine's time.
                .res 4096, $E5
            """);

        using DapTestClient client = new();
        client.Request("initialize", []);
        client.Fails("launch", Launch("own")).Should().EndWith(
            "a level2 target loads its own tape with SYSTEM, so its options and its launch cannot give 'cassette'.");

        client.Fails("launch", Launch("disk")).Should().EndWith(
            "a level2 target boots with no disk controller, for the ROM to start in BASIC, so its options and its launch cannot give 'diskController'.");

        int start = machine == "trs80-model3" ? 0x4400 : 0x4300;
        client.Request("launch", Launch("tape"))["project"]?["entry"]?.GetValue<int>().Should().Be(start + 18);
        string entry = "$" + (start + 18).ToString("X4", System.Globalization.CultureInfo.InvariantCulture);
        client.Request("evaluate", new JsonObject
        {
            ["expression"] = "PC"
        }).String("result").Should().StartWith(entry);

        JsonObject set = client.Request("setBreakpoints", new JsonObject
        {
            ["source"] = new JsonObject { ["path"] = main },
            ["breakpoints"] = new JsonArray(new JsonObject { ["line"] = 14 })
        });

        (set["breakpoints"]?[0]?["verified"]?.GetValue<bool>()).Should().BeTrue();
        client.Request("configurationDone", []);
        client.Event("stopped").String("reason").Should().Be("entry");
        client.Request("continue", new JsonObject { ["threadId"] = 1 });
        client.Event("stopped").String("reason").Should().Be("breakpoint", "the program runs to its loop once it has shown its line");
        Trs80Screen(client).Should().Contain("*? HELLO").And.Contain("LOADED FROM TAPE");
    }

    /// <summary>
    ///  A <c>colorbasic</c> target's launch puts its cassette in the recorder and boots Color BASIC from the SDK's
    ///  ROMs with no disk controller: at OK it types <c>CLOADM"&lt;NAME&gt;"</c>, and once the program is in, <c>EXEC</c>,
    ///  and stops at the entry, on the Color Computer 1, 2 and 3. The program, 2K, plays for over ten of the machine's
    ///  seconds, with <c>$55</c> bytes in its blocks, which are not leaders, and a name with OK in it, which is not
    ///  BASIC's prompt. It then shows its line, and a breakpoint in its source stops. Its target cannot give a disk
    ///  controller, nor, on the CoCo 1 and 2, leave out Extended BASIC.
    /// </summary>
    /// <param name="machine">The catalog machine.</param>
    [TestMethod]
    [DataRow("coco1")]
    [DataRow("coco2")]
    [DataRow("coco3")]
    public void ColorbasicLaunchBootsItsTape(string machine)
    {
        Write("retrocore.json", $$"""
            { "sdk": "1", "name": "bookshop", "cpu": "6809", "sources": ["src/*.s"], "entry": "START",
              "targets": { "tape": { "machine": "{{machine}}", "environment": "colorbasic" },
                           "disk": { "machine": "{{machine}}", "environment": "colorbasic", "options": { "diskController": true } },
                           "alone": { "machine": "{{machine}}", "environment": "colorbasic", "options": { "extendedBasic": "none" } } } }
            """);

        string main = Write("src/main.s", """
            .include <machine.inc>
            MESSAGE:
                .byte "LOADED FROM TAPE", RETURN, 0
            START:
                leax MESSAGE,pcr
            NEXT:
                lda ,x+
                beq DONE
                jsr [CharacterOutVector]
                bra NEXT
            DONE:
                bra DONE

            ; Data after the code, so the tape plays for a while: a block's own $55s, which are not a leader, a run of
            ; them, and a $3C after one.
                .res 2048, $E5
                .byte $55, 1, $55, $55, $3C
                .res 64, $55
                .byte "PUMPKIN UNUSUAL", $55
            """);

        using DapTestClient client = new();
        client.Request("initialize", []);
        client.Fails("launch", Launch("disk")).Should().EndWith(
            "a colorbasic target boots Color BASIC with no disk controller, as Disk BASIC is the diskbasic environment, so its options and its launch cannot give 'diskController'.");

        if (machine != "coco3")
        {
            client.Fails("launch", Launch("alone")).Should().EndWith(
                "a colorbasic target runs under Extended Color BASIC, whose memory its maps give, so its options and its launch cannot give 'extendedBasic' none.");
        }

        client.Request("launch", Launch("tape"))["project"]?["entry"]?.GetValue<int>().Should().Be(0x1F12);
        client.Request("evaluate", new JsonObject
        {
            ["expression"] = "PC"
        }).String("result").Should().StartWith("$1F12");

        JsonObject set = client.Request("setBreakpoints", new JsonObject
        {
            ["source"] = new JsonObject { ["path"] = main },
            ["breakpoints"] = new JsonArray(new JsonObject { ["line"] = 12 })
        });

        (set["breakpoints"]?[0]?["verified"]?.GetValue<bool>()).Should().BeTrue();
        client.Request("configurationDone", []);
        client.Event("stopped").String("reason").Should().Be("entry");
        client.Request("continue", new JsonObject { ["threadId"] = 1 });
        client.Event("stopped").String("reason").Should().Be("breakpoint", "the program runs to its loop once it has shown its line");
        CocoScreen(client).Should().Contain("F BOOKSHOP").And.Contain("LOADED FROM TAPE");
    }

    /// <summary>
    ///  A <c>diskbasic</c> target's launch fits the disk controller with Disk BASIC from the SDK's sources, puts its disk
    ///  in drive 0, types <c>LOADM"&lt;NAME&gt;"</c> at OK and, once the program is in, <c>EXEC</c>, and stops at the
    ///  entry, on the Color Computer 1, 2 and 3. The program then shows its line, and a breakpoint in its source stops.
    ///  Its target cannot give the disks, a cassette or a cartridge.
    /// </summary>
    /// <param name="machine">The catalog machine.</param>
    [TestMethod]
    [DataRow("coco1")]
    [DataRow("coco2")]
    [DataRow("coco3")]
    public void DiskbasicLaunchBootsItsDisk(string machine)
    {
        Write("retrocore.json", $$"""
            { "sdk": "1", "name": "bookshop", "cpu": "6809", "sources": ["src/*.s"], "entry": "START",
              "targets": { "disk": { "machine": "{{machine}}", "environment": "diskbasic", "files": [{ "path": "data.bin", "name": "DATA.DAT" }] },
                           "own": { "machine": "{{machine}}", "environment": "diskbasic", "options": { "disks": ["x.dsk"] } },
                           "tape": { "machine": "{{machine}}", "environment": "diskbasic", "options": { "cassette": "x.cas" } },
                           "pack": { "machine": "{{machine}}", "environment": "diskbasic", "options": { "cartridge": "x.ccc" } } } }
            """);

        File.WriteAllBytes(Path.Join(_folder, "data.bin"), [1, 2, 3]);
        string main = Write("src/main.s", """
            .include <machine.inc>
            MESSAGE:
                .byte "LOADED FROM DISK", RETURN, 0
            START:
                leax MESSAGE,pcr
            NEXT:
                lda ,x+
                beq DONE
                jsr [CharacterOutVector]
                bra NEXT
            DONE:
                bra DONE
                .res 1024, $55
            """);

        using DapTestClient client = new();
        client.Request("initialize", []);
        client.Fails("launch", Launch("own")).Should().EndWith(
            "a diskbasic target boots Disk BASIC with its own disk in drive 0, so its options and its launch cannot give 'disks'.");

        client.Fails("launch", Launch("tape")).Should().EndWith(
            "a diskbasic target loads its program from its disk under Disk BASIC, so its options and its launch cannot give 'cassette'.");

        client.Fails("launch", Launch("pack")).Should().EndWith(
            "a diskbasic target boots Disk BASIC from the cartridge port, which a cartridge would take over, so its options and its launch cannot give 'cartridge'.");

        client.Request("launch", Launch("disk"))["project"]?["entry"]?.GetValue<int>().Should().Be(0x2712);
        client.Request("evaluate", new JsonObject
        {
            ["expression"] = "PC"
        }).String("result").Should().StartWith("$2712");

        JsonObject set = client.Request("setBreakpoints", new JsonObject
        {
            ["source"] = new JsonObject { ["path"] = main },
            ["breakpoints"] = new JsonArray(new JsonObject { ["line"] = 12 })
        });

        (set["breakpoints"]?[0]?["verified"]?.GetValue<bool>()).Should().BeTrue();
        client.Request("configurationDone", []);
        client.Event("stopped").String("reason").Should().Be("entry");
        client.Request("continue", new JsonObject { ["threadId"] = 1 });
        client.Event("stopped").String("reason").Should().Be("breakpoint", "the program runs to its loop once it has shown its line");
        CocoScreen(client).Should().Contain("LOADM\"BOOKSHOP\"").And.Contain("LOADED FROM DISK");
    }

    /// <summary>
    ///  The 6809 sample, <c>sample/6809</c>, boots on each of its targets, from its cassette under Color BASIC and from its
    ///  disk under Disk BASIC, and shows its greeting, then goes back to BASIC's OK.
    /// </summary>
    /// <param name="target">The sample's target.</param>
    [TestMethod]
    [DataRow("coco-colorbasic")]
    [DataRow("coco3-colorbasic")]
    [DataRow("coco-diskbasic")]
    [DataRow("coco3-diskbasic")]
    public void M6809SampleRunsOnEachTarget(string target)
    {
        string sample = Path.Join(RepositoryRoot(), "sample", "6809");
        using DapTestClient client = new();
        client.Request("initialize", []);
        client.Request("launch", new JsonObject { ["project"] = sample, ["target"] = target, ["stopOnEntry"] = false });
        client.Request("configurationDone", []);
        for (DateTime end = DateTime.UtcNow.AddSeconds(30); !CocoScreen(client).Contains("HELLO, WORLD!\nOK", StringComparison.Ordinal); Thread.Sleep(100))
        {
            DateTime.UtcNow.Should().BeBefore(end, $"{target} shows its greeting and BASIC's OK:\n{CocoScreen(client)}");
        }
    }

    // The Color Computer's text screen, 32 columns by 16 rows from $0400, as rows of text with their trailing spaces
    // left out: each byte's low six bits, $00-$1F as @ to _ and $20-$3F as space to ?.
    private static string CocoScreen(DapTestClient client)
    {
        byte[] bytes = Convert.FromBase64String(client.Request("readMemory", new JsonObject
        {
            ["memoryReference"] = "0x400",
            ["count"] = 512
        }).String("data") ?? "");

        IEnumerable<string> rows = bytes.Chunk(32).Select(row => new string([.. row.Select(value =>
        {
            int character = value & 0x3F;
            return (char)(character < 0x20 ? character + 0x40 : character);
        })]).TrimEnd());

        return string.Join("\n", rows);
    }

    /// <summary>
    ///  A <c>cpm</c> target's launch puts its disk, the Kaypro II's CP/M disk with the program added, in drive A, types
    ///  the program's name at <c>A&gt;</c>, and stops at <c>$0100</c>, where the CCP starts it; the program then writes
    ///  its line through the BDOS. Its target cannot give the disks or the command. Without the system disk the test is
    ///  inconclusive.
    /// </summary>
    [TestMethod]
    public void CpmLaunchBootsItsDisk()
    {
        Write("retrocore.json", """
            { "sdk": "1", "name": "hello", "cpu": "z80", "sources": ["src/*.s"], "entry": "START",
              "targets": { "cpm": { "machine": "kaypro2", "environment": "cpm" },
                           "own": { "machine": "kaypro2", "environment": "cpm", "options": { "command": "DIR" } } } }
            """);

        string main = Write("src/main.s", """
            START:
                LD DE,MESSAGE
                LD C,9
                CALL 5
            LOOP:
                JR LOOP
            MESSAGE:
                .byte "LOADED FROM CP/M", 13, 10, "$"
            """);

        using DapTestClient client = new();
        client.Request("initialize", []);
        client.Fails("launch", Launch("own")).Should().EndWith(
            "a cpm target boots its own disk in drive A and types its program's name, so its options and its launch cannot give 'command'.");

        JsonObject? launched = client.TryRequest("launch", Launch("cpm"), out string? failure);
        if (launched is null)
        {
            failure.Should().Contain("the Kaypro II's CP/M 2.2 system disk").And.Contain("was not found by its hash");
            Assert.Inconclusive($"The Kaypro II's CP/M disk was not found: {failure}");
        }

        (launched["project"]?["entry"]?.GetValue<int>()).Should().Be(0x0100);
        JsonObject set = client.Request("setBreakpoints", new JsonObject
        {
            ["source"] = new JsonObject { ["path"] = main },
            ["breakpoints"] = new JsonArray(new JsonObject { ["line"] = 6 })
        });

        (set["breakpoints"]?[0]?["verified"]?.GetValue<bool>()).Should().BeTrue();
        client.Request("configurationDone", []);
        client.Event("stopped").String("reason").Should().Be("entry");
        client.Request("continue", new JsonObject { ["threadId"] = 1 });
        client.Event("stopped").String("reason").Should().Be("breakpoint", "the program runs to its loop once it has written its line");
        string screen = string.Join("\n", (client.Request("retro/display", [])["rows"] as JsonArray ?? []).Select(row => row?.GetValue<string>()));
        screen.Should().Contain("A>HELLO").And.Contain("LOADED FROM CP/M");
    }

    /// <summary>
    ///  The Z80 sample, <c>sample/z80</c>, boots on each of its targets and shows its greeting, then goes back to its
    ///  environment: under Level II, to BASIC's READY.
    /// </summary>
    /// <param name="target">The sample's target.</param>
    [TestMethod]
    [DataRow("trs80-level2")]
    [DataRow("trs80-model3-level2")]
    public void Z80SampleRunsOnEachTarget(string target)
    {
        string sample = Path.Join(RepositoryRoot(), "sample", "z80");
        using DapTestClient client = new();
        client.Request("initialize", []);
        client.Request("launch", new JsonObject { ["project"] = sample, ["target"] = target, ["stopOnEntry"] = false });
        client.Request("configurationDone", []);
        for (DateTime end = DateTime.UtcNow.AddSeconds(30); !Trs80Screen(client).Contains("HELLO, WORLD!\nREADY", StringComparison.Ordinal); Thread.Sleep(100))
        {
            DateTime.UtcNow.Should().BeBefore(end, $"{target} shows its greeting and BASIC's READY:\n{Trs80Screen(client)}");
        }
    }

    private static string RepositoryRoot()
    {
        string? root = AppContext.BaseDirectory;
        while (root is not null && !File.Exists(Path.Join(root, "Retrocore.slnx")))
        {
            root = Path.GetDirectoryName(root);
        }

        return root ?? throw new InvalidOperationException("The repository root was not found.");
    }

    /// <summary>
    ///  The Z80 sample's <c>kaypro-cpm</c> target boots CP/M on the Kaypro II, and the program shows its greeting through
    ///  the BDOS and warm boots back to <c>A&gt;</c>. Without the Kaypro II's CP/M disk the test is inconclusive.
    /// </summary>
    [TestMethod]
    public void Z80SampleRunsUnderCpm()
    {
        string sample = Path.Join(RepositoryRoot(), "sample", "z80");
        using DapTestClient client = new();
        client.Request("initialize", []);
        JsonObject launch = new()
        {
            ["project"] = sample,
            ["target"] = "kaypro-cpm",
            ["stopOnEntry"] = false,
            ["speed"] = "max"
        };

        if (client.TryRequest("launch", launch, out string? failure) is null)
        {
            failure.Should().Contain("was not found by its hash");
            Assert.Inconclusive($"The Kaypro II's CP/M disk was not found: {failure}");
        }

        client.Request("configurationDone", []);

        // The display's rows, those that show something: the greeting, then CP/M's prompt below it.
        List<string> Shown() => [.. (client.Request("retro/display", [])["rows"] as JsonArray ?? [])
            .Select(row => row?.GetValue<string>()?.TrimEnd() ?? "")
            .Where(row => row.Length != 0)];

        for (DateTime end = DateTime.UtcNow.AddSeconds(30); !Done(Shown()); Thread.Sleep(200))
        {
            DateTime.UtcNow.Should().BeBefore(end, $"the sample shows its greeting and CP/M's prompt:\n{string.Join("\n", Shown())}");
        }

        static bool Done(List<string> rows) =>
            rows.IndexOf("HELLO, WORLD!") is int greeting and >= 0 && rows.Count > greeting + 1 && rows[^1].StartsWith("A>", StringComparison.Ordinal);
    }

    // The TRS-80's screen, 64 columns by 16 rows from $3C00, as rows of text with their trailing spaces left out. A
    // byte below $20 is the capital 64 above it, as the Model I's video RAM has no bit 6.
    private static string Trs80Screen(DapTestClient client)
    {
        byte[] bytes = Convert.FromBase64String(client.Request("readMemory", new JsonObject
        {
            ["memoryReference"] = "0x3C00",
            ["count"] = 1024
        }).String("data") ?? "");

        IEnumerable<string> rows = bytes.Chunk(64).Select(row => new string([.. row.Select(value =>
        {
            int character = value & 0x7F;
            return (char)(character < 0x20 ? character + 0x40 : character);
        })]).TrimEnd());

        return string.Join("\n", rows);
    }

    /// <summary>
    ///  A routine's <c>Keeps:</c> contract is checked only where memory holds the routine's code, as its source lines
    ///  apply only there: a call to its address once the program has written other code over it, as ProDOS fills a
    ///  language card where Integer BASIC's routines were mapped, runs on, and a call to it as built stops.
    /// </summary>
    [TestMethod]
    public void ContractsHoldOnlyWhereTheirCodeIs()
    {
        Write("retrocore.json", """
            { "sdk": "1", "name": "game", "cpu": "6502", "sources": ["src/*.s"], "entry": "START",
              "targets": { "iiplus": { "machine": "apple2-iiplus", "environment": "bare" } } }
            """);

        const string Keeper = ";; Claims to keep X, and does not.\n;; Keeps: X\nKeeper:\n    inx\n    rts\n";
        Write("src/main.s", $"START:\n    lda #$CA\n    sta Keeper\n    jsr Keeper\nLoop:\n    jmp Loop\n{Keeper}");
        using (DapTestClient client = new())
        {
            client.Request("initialize", []);
            JsonObject launch = Launch("iiplus");
            (launch["checkContracts"], launch["stopOnEntry"]) = ("stop", false);
            client.Request("launch", launch);
            client.Request("configurationDone", []);
            Thread.Sleep(500);
            client.Request("pause", new JsonObject { ["threadId"] = 1 });
            client.Event("stopped").String("reason").Should().Be("pause", "Keeper's inx is now a dex, which is not the routine its contract describes");
        }

        Write("src/main.s", $"START:\n    jsr Keeper\nLoop:\n    jmp Loop\n{Keeper}");
        using (DapTestClient client = new())
        {
            client.Request("initialize", []);
            JsonObject launch = Launch("iiplus");
            (launch["checkContracts"], launch["stopOnEntry"]) = ("stop", false);
            client.Request("launch", launch);
            client.Request("configurationDone", []);
            JsonObject stopped = client.Event("stopped");
            stopped.String("reason").Should().Be("exception");
            stopped.String("description").Should().Contain("Keeper returned with X changed");
        }
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
    ///  as its <c>bootImage</c> what is not a folder when it boots the disk; a tape target never reads it.
    /// </summary>
    [TestMethod]
    public void BasicDiskLaunchRefusesBasic1AndAMissingFolder()
    {
        Write("retrocore.json", """
            { "sdk": "1", "name": "game", "cpu": "6502", "sources": ["src/*.s"],
              "targets": {
                "basic1": { "machine": "pet2001", "environment": "basic", "image": { "boot": "disk" } },
                "missing": { "machine": "pet4032", "environment": "basic", "image": { "boot": "disk" }, "bootImage": "no-such-folder" },
                "tape": { "machine": "pet4032", "environment": "basic", "bootImage": "no-such-folder" } } }
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
        RetrocoreProject.Load(_folder).Target("tape").RequireSupported();
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
    ///  A <c>sos</c> program whose code runs past <c>$A000</c>, in the fixed system RAM above the switched bank SOS gives
    ///  the interpreter below it, has its lines mapped there too: the launch stops at its entry there, and a breakpoint
    ///  there stops.
    /// </summary>
    [TestMethod]
    public void SosLaunchMapsLinesInEachBankTheProgramSpans()
    {
        Write("retrocore.json", """
            { "sdk": "1", "name": "game", "cpu": "6502", "sources": ["src/*.s"], "entry": "START",
              "targets": { "sos": { "machine": "apple3", "environment": "sos" } } }
            """);

        string main = Write("src/main.s", "    jmp START\n    .res $8000\nSTART:\n    lda #1\nLoop:\n    jmp Loop\n");
        using DapTestClient client = new();
        client.Request("initialize", []);
        client.Request("launch", Launch("sos"))["project"]?["entry"]?.GetValue<int>().Should().Be(0xA003);
        JsonObject set = client.Request("setBreakpoints", new JsonObject
        {
            ["source"] = new JsonObject { ["path"] = main },
            ["breakpoints"] = new JsonArray(new JsonObject { ["line"] = 6 })
        });

        (set["breakpoints"]?[0]?["verified"]?.GetValue<bool>()).Should().BeTrue();
        client.Request("configurationDone", []);
        client.Event("stopped").String("reason").Should().Be("entry");
        client.Request("continue", new JsonObject { ["threadId"] = 1 });
        client.Event("stopped").String("reason").Should().Be("breakpoint", "the line above $A000 is mapped where SOS runs it");
    }

    /// <summary>
    ///  A <c>sos</c> target's launch puts its boot disk in .D1, and the Apple III boots SOS from it, which starts the
    ///  interpreter: the launch stops at its entry, past its first byte's <c>JMP</c>, with its lines mapped where SOS
    ///  runs it, so a breakpoint in its source binds and stops. Its target cannot give the disks.
    /// </summary>
    [TestMethod]
    public void SosLaunchBootsItsDisk()
    {
        Write("retrocore.json", """
            { "sdk": "1", "name": "game", "cpu": "6502", "sources": ["src/*.s"], "entry": "START",
              "targets": {
                "sos": { "machine": "apple3", "environment": "sos" },
                "disks": { "machine": "apple3", "environment": "sos", "options": { "disks": ["x.dsk"] } } } }
            """);

        string main = Write("src/main.s", "    jmp START\nSTART:\n    lda #1\nLoop:\n    jmp Loop\n");
        using DapTestClient client = new();
        client.Request("initialize", []);
        client.Fails("launch", Launch("disks")).Should().EndWith(
            "a sos target boots its own disk in .D1, so its options and its launch cannot give 'disks'.");

        client.Request("launch", Launch("sos"))["project"]?["entry"]?.GetValue<int>().Should().Be(0x2003);
        client.Request("evaluate", new JsonObject
        {
            ["expression"] = "PC"
        }).String("result").Should().StartWith("$2003");

        JsonObject set = client.Request("setBreakpoints", new JsonObject
        {
            ["source"] = new JsonObject { ["path"] = main },
            ["breakpoints"] = new JsonArray(new JsonObject { ["line"] = 5 })
        });

        (set["breakpoints"]?[0]?["verified"]?.GetValue<bool>()).Should().BeTrue();
        client.Request("configurationDone", []);
        client.Event("stopped").String("reason").Should().Be("entry");
        client.Request("continue", new JsonObject { ["threadId"] = 1 });
        client.Event("stopped").String("reason").Should().Be("breakpoint", "the program's lines are mapped where SOS runs it");
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