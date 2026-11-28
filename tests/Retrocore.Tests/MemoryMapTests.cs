// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug;
using Retrocore.Debug.Project;

namespace Retrocore.Tests;

/// <summary>
///  The SDK's memory maps for bare targets: each keeps what its machine's ROM sources use, covers the RAM sizes the
///  machine takes, and the build makes a linker configuration from it and checks a program against it.
/// </summary>
[TestClass]
public sealed class MemoryMapTests
{
    private string _folder = "";

    /// <summary>
    ///  Gets each test a folder of its own.
    /// </summary>
    [TestInitialize]
    public void Initialize()
    {
        _folder = Path.Join(Path.GetTempPath(), "retrocore-maps-" + Guid.NewGuid().ToString("N"));
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
    ///  What a machine's ROM sources name, through its <c>&lt;machine.inc&gt;</c>, is in the reserved area the map
    ///  gives for it.
    /// </summary>
    /// <param name="machine">The catalog machine.</param>
    /// <param name="kilobytes">Its RAM.</param>
    /// <param name="symbol">A name the machine's header gives.</param>
    /// <param name="why">The start of the reason of the area that must hold it.</param>
    [TestMethod]
    [DataRow("apple2-iiplus", 48, "InputBuffer", "the Monitor's input buffer")]
    [DataRow("apple2-iiplus", 16, "InputBuffer", "the Monitor's input buffer")]
    [DataRow("apple2-iiplus", 48, "BreakVector", "the vectors")]
    [DataRow("apple2-iiplus", 48, "UserIrqVector", "the vectors")]
    [DataRow("apple2-iiplus", 48, "TextPage1", "text and lo-res page 1")]
    [DataRow("apple2-iiplus", 48, "CharacterOut", "the ROMs: AppleSoft")]
    [DataRow("apple1", 32, "InputBuffer", "the Woz Monitor's input buffer")]
    [DataRow("apple1", 4, "Keyboard", "the keyboard and display PIA")]
    [DataRow("apple1", 32, "CharacterOut", "the Woz Monitor's ROM")]
    [DataRow("apple3", 256, "TextPage", "text page 1")]
    [DataRow("apple3", 256, "KBD", "I/O and the slots")]
    [DataRow("apple3", 256, "ZPREG", "the boot ROM")]
    [DataRow("pet4032", 32, "SCREEN", "the screen")]
    [DataRow("pet4032", 32, "PIA1_PA", "the PIAs and the VIA")]
    [DataRow("pet2001", 8, "VIA_ORB", "the PIAs and the VIA")]
    [DataRow("pet4032", 32, "KernalCharacterOut", "the Kernal's ROM")]
    [DataRow("bbcb", 32, "USERV", "the MOS's vectors")]
    [DataRow("bbcb", 32, "KEYBOARD_BUFFER", "the MOS's VDU, cassette and keyboard")]
    [DataRow("bbca", 16, "SOUND_WORKSPACE", "the MOS's sound")]
    [DataRow("bbcb", 32, "NMI_ROUTINE", "the MOS's sound")]
    [DataRow("bbcb", 32, "SHEILA", "the I/O pages")]
    [DataRow("bbcb", 32, "OSRDCH", "the MOS's ROM: its entry points")]
    public void MapsKeepWhatTheRomSourcesUse(string machine, int kilobytes, string symbol, string why)
    {
        TargetBuild build = Build(machine, kilobytes, ".include <machine.inc>\n    rts\n");
        build.Result.Symbols.TryGetValue(symbol, out long value).Should().BeTrue($"{machine}'s header gives {symbol}");
        MemoryMap map = build.Map ?? throw new AssertFailedException($"{machine} has no memory map.");
        map.Reserved.Should().Contain(area => area.Contains((int)value) && (area.Why ?? "").StartsWith(why, StringComparison.Ordinal),
            $"{symbol} (${value:X4}) is in the area for {why} in {Path.GetFileName(map.File)}");
    }

    /// <summary>
    ///  Each machine has a map for every RAM size it takes, whose free RAM is within the RAM the size has, and at its
    ///  default RAM the program loads where its launch loads one.
    /// </summary>
    /// <param name="machine">The catalog machine.</param>
    /// <param name="sizes">The RAM sizes its launch takes, the default first.</param>
    [TestMethod]
    [DataRow("apple2-iiplus", new[] { 48, 32, 16 })]
    [DataRow("apple1", new[] { 4, 8, 16, 32 })]
    [DataRow("apple3", new[] { 256, 128, 512 })]
    [DataRow("pet4032", new[] { 32, 16, 8, 4 })]
    [DataRow("pet2001", new[] { 8, 4, 16, 32 })]
    [DataRow("bbcb", new[] { 32 })]
    [DataRow("bbca", new[] { 16 })]
    public void MapsCoverTheRamSizes(string machine, int[] sizes)
    {
        foreach (int kilobytes in sizes)
        {
            TargetBuild build = Build(machine, kilobytes, "    rts\n");
            MemoryMap map = build.Map ?? throw new AssertFailedException($"{machine} with {kilobytes}K has no memory map.");

            // The Apple III's RAM above 48K is banked; a bare program's addresses reach bank 0 and the system bank.
            int top = Math.Min(kilobytes * 1024, 0xC000) - 1;
            map.Free.Max(area => area.End).Should().BeLessThanOrEqualTo(top, $"{machine} with {kilobytes}K has RAM to ${top:X4}");
            map.Free.Should().OnlyContain(area => area.End < 0xC000, "free RAM is below the I/O and ROMs");
            if (kilobytes == sizes[0])
            {
                map.Load.Should().Be(CatalogMachine.Find(machine)?.LoadAddress, "a bare program loads where its launch loads one");
            }
        }
    }

    /// <summary>
    ///  A target whose machine has a map links by one made from it, written to <c>obj/&lt;target&gt;/memory.cfg</c>:
    ///  its sections from the load address and its zero page in the largest run of free bytes.
    /// </summary>
    [TestMethod]
    public void TheBuildMakesALinkerConfigurationFromTheMap()
    {
        TargetBuild build = Build("apple2-iiplus", 48, """
            .section ZEROPAGE
            Pointer:
                .res 2
            .section CODE
            Start:
                lda Pointer
                rts
            .section BSS
            Scratch:
                .res 10
            """);

        File.ReadAllText(Path.Join(_folder, "obj", "t", "memory.cfg")).Should()
            .Contain("ZP: start = $06, size = $04,").And.Contain("RAM: start = $6000, size = $A000, file = %O;");

        build.Result.Symbols["Pointer"].Should().Be(0x06);
        build.Result.Symbols["Start"].Should().Be(0x6000);
        File.ReadAllBytes(build.Binary).Should().Equal(0xA5, 0x06, 0x60);
        build.Result.Symbols["Scratch"].Should().Be(0x6003);
    }

    /// <summary>
    ///  A section in a reserved area fails the build, naming the section, the area and the target, and how far over
    ///  its free RAM the program runs; the target's <c>memoryMap</c> can free the area.
    /// </summary>
    [TestMethod]
    public void ReservedAreasFailTheBuildUnlessTheTargetFreesThem()
    {
        Write("link.cfg", """
            MEMORY { SCREEN: start = $0400, size = $0400, file = %O; }
            SEGMENTS { CODE: load = SCREEN, type = ro; }
            """);

        const string Linked = "\"linkerConfiguration\": \"link.cfg\"";
        string screen = Error(() => Build("apple2-iiplus", 48, ".section CODE\n    rts\n", Linked));
        screen.Should().Contain("target t: apple2-48k.map.json:" + Environment.NewLine);
        screen.Should().EndWith(
            "section CODE ($0400) overlaps text and lo-res page 1, the screen, with the screen holes the cards use ($0400-$07FF) on target t.");

        const string Freed = Linked + ", \"memoryMap\": { \"free\": [{ \"start\": \"$0400\", \"end\": \"$07FF\" }] }";
        TargetBuild freed = Build("apple2-iiplus", 48, ".section CODE\n    rts\n", Freed);
        ProjectBuild.Image(freed).Address.Should().Be(0x0400);

        string over = Error(() => Build("apple1", 4, ".section CODE\n    .res 3400\n"));
        over.Should().Contain("section CODE ($0300-$1047) overlaps addresses with no RAM, as the machine has 4K from $0000 ($1000-$BFFF) on target t.");
        over.Should().EndWith(
            "The program does not fit: from $0300 its sections take 3400 bytes (CODE 3400), and the free RAM there ends at $0FFF, 3328 bytes, so it is 72 bytes over.");
    }

    /// <summary>
    ///  A zero-page section outside the bytes the map gives a program fails the build.
    /// </summary>
    [TestMethod]
    public void ZeroPageTheMachineKeepsFailsTheBuild()
    {
        Write("link.cfg", """
            MEMORY { ZP: start = $20, size = $10, file = ""; RAM: start = $6000, size = $1000, file = %O; }
            SEGMENTS { ZEROPAGE: load = ZP, type = zp; CODE: load = RAM, type = ro; }
            """);

        Error(() => Build("apple2-iiplus", 48, ".section ZEROPAGE\n    .res 2\n.section CODE\n    rts\n", "\"linkerConfiguration\": \"link.cfg\""))
            .Should().EndWith(
                "section ZEROPAGE ($0020-$0021) uses zero page $20-$21, which the memory map leaves to the machine; a program may use $06-$09, $FA-$FD on target t.");
    }

    /// <summary>
    ///  A target's <c>memoryMap</c> may move the load address and replace the zero page; one that loads outside
    ///  free RAM, or changes a map its machine lacks, or is malformed, is an error.
    /// </summary>
    [TestMethod]
    public void TargetsChangeTheirMaps()
    {
        TargetBuild moved = Build("apple2-iiplus", 48, "    rts\n", "\"memoryMap\": { \"load\": \"$0800\", \"zeroPage\": [\"$EB-$EF\"] }");
        ProjectBuild.Image(moved).Address.Should().Be(0x0800);
        moved.Map?.ZeroPage.Should().Equal(new MemoryArea(0xEB, 0xEF));

        Error(() => Build("apple2-iiplus", 48, "    rts\n", "\"memoryMap\": { \"load\": \"$0400\" }")).Should().EndWith(
            "target t: its program loads at $0400, which its memory map does not give as free RAM.");

        Error(() => Build("trs80-model3", 48, "    ret\n", "\"memoryMap\": { \"load\": \"$7000\" }", cpu: "z80")).Should().EndWith(
            "target t gives 'memoryMap', but the SDK has no memory map for trs80-model3 in the 'bare' environment to change.");

        Error(() => Build("apple2-iiplus", 48, "    rts\n", "\"memoryMap\": { \"reserved\": [{ \"start\": \"$6000\", \"end\": \"$60FF\" }] }"))
            .Should().EndWith("must say why.");

        Error(() => Build("apple2-iiplus", 48, "    rts\n", "\"memoryMap\": { \"free\": 1 }")).Should().EndWith(
            "target t's 'memoryMap' 'free' must be a list of areas.");
    }

    /// <summary>
    ///  A target's zero page merges runs that touch, so the made configuration's zero page is the largest of them; a
    ///  zero page of nothing, or free areas in the zero page, are errors; and the made configuration is there when the
    ///  map's check fails.
    /// </summary>
    [TestMethod]
    public void ZeroPageOverridesMergeAndTheConfigurationOutlivesAFailure()
    {
        TargetBuild merged = Build("apple2-iiplus", 48, "    rts\n", "\"memoryMap\": { \"zeroPage\": [\"$06\", \"$07\", \"$08-$0B\", \"$0A\"] }");
        merged.Map?.ZeroPage.Should().Equal(new MemoryArea(0x06, 0x0B));
        File.ReadAllText(Path.Join(_folder, "obj", "t", "memory.cfg")).Should().Contain("ZP: start = $06, size = $06,");

        Error(() => Build("apple2-iiplus", 48, "    rts\n", "\"memoryMap\": { \"zeroPage\": [] }")).Should().EndWith(
            "'zeroPage' must give at least one byte a program may use.");

        Error(() => Build("apple2-iiplus", 48, "    rts\n", "\"memoryMap\": { \"zeroPage\": [\"$06-$100\"] }")).Should().EndWith(
            "in target t's 'memoryMap' 'zeroPage', '$06-$100' must be a byte or a run of them, such as \"$06-$09\".");

        Error(() => Build("apple2-iiplus", 48, "    rts\n", "\"memoryMap\": { \"free\": [{ \"start\": \"$0050\", \"end\": \"$0060\" }] }"))
            .Should().EndWith("the zero page is given by 'zeroPage', not as free or reserved areas.");

        File.Delete(Path.Join(_folder, "obj", "t", "memory.cfg"));
        _ = Error(() => Build("apple1", 4, ".section CODE\n    .res 3400\n"));
        File.ReadAllText(Path.Join(_folder, "obj", "t", "memory.cfg")).Should().Contain("from apple1-4k.map.json");
    }

    /// <summary>
    ///  A machine whose family has maps but none for its RAM is an error; one with no maps builds as before.
    /// </summary>
    [TestMethod]
    public void MissingMapsForARamSizeAreErrors()
    {
        Error(() => Build("apple2-iie", 64, "    rts\n")).Should().EndWith(
            "target t: the SDK has no memory map for apple2-iie with 64K in the 'bare' environment.");

        TargetBuild unmapped = Build("trs80-model3", 48, "    ret\n", cpu: "z80");
        unmapped.Map.Should().BeNull();
        ProjectBuild.Image(unmapped).Address.Should().Be(0x7000);
    }

    /// <summary>
    ///  Every map the SDK ships reads, in each environment's folder, which checks that it accounts for every address
    ///  from <c>$0100</c> once, and gives a description and a zero page; each is named for machines that run its
    ///  environment.
    /// </summary>
    [TestMethod]
    public void EveryShippedMapReads()
    {
        Dictionary<string, int> counts = new()
        {
            // The Apple II at 3 sizes, the Apple-1 at 4, the Apple III, the PET at 4 and the BBC Micro at 2.
            ["bare"] = 14,

            // The Apple-1 at 4 sizes.
            ["wozmon"] = 4,

            // The Apple II Plus and IIe with 48K, which DOS 3.3 as the SDK builds it runs on, and the Apple II, whose
            // HELLO is Integer BASIC's.
            ["dos33"] = 2,

            // The BBC Micro model B, and the model A with the disk interface.
            ["dfs"] = 2,

            // The PET at 4 sizes.
            ["basic"] = 4,

            // The Apple III.
            ["sos"] = 1,

            // The II Plus with its language card and the IIe.
            ["prodos"] = 1,

            // The TRS-80 Model I with Level II and the Model III, each at 3 sizes.
            ["level2"] = 6
        };

        string environments = Path.Join(SdkModules.SdkDirectory, "1", "environments");
        Directory.GetDirectories(environments).Select(Path.GetFileName).Should().BeEquivalentTo(counts.Keys);
        foreach ((string environment, int count) in counts)
        {
            string[] files = Directory.GetFiles(Path.Join(environments, environment), "*.map.json");
            files.Should().HaveCount(count, environment);
            foreach (string file in files)
            {
                MemoryMap map = MemoryMap.Read(file);
                map.Description.Should().NotBeNullOrWhiteSpace(file);
                // A map gives the bytes of zero page a program may use where the CPU has one, the 6502 family's.
                string name = Path.GetFileName(file)[..^".map.json".Length];
                bool zeroPage = CatalogMachine.All.Any(machine => machine.Cpu.Runs(ProjectCpu.Mos6502) && (name == machine.Id || name.StartsWith(machine.Family + "-", StringComparison.Ordinal) || name == machine.Family));
                if (zeroPage) { map.ZeroPage.Should().NotBeEmpty(file); }
                else { map.ZeroPage.Should().BeEmpty(file); }

                // Each map is for machines that run its environment, by a catalog id or a family.
                CatalogMachine.All.Should().Contain(
                    machine => ProjectTarget.Runs(machine, environment) && (name == machine.Id || name == machine.Family || name.StartsWith(machine.Family + "-", StringComparison.Ordinal)),
                    file);
            }
        }
    }

    /// <summary>
    ///  The Woz Monitor is the Apple-1's bare environment as well, so each <c>wozmon</c> map is its <c>bare</c> map but
    ///  for its description: the same load address, free RAM, zero page and reserved areas.
    /// </summary>
    [TestMethod]
    public void WozmonMapsAreTheBareApple1Maps()
    {
        string environments = Path.Join(SdkModules.SdkDirectory, "1", "environments");
        foreach (string file in Directory.GetFiles(Path.Join(environments, "wozmon"), "*.map.json"))
        {
            MemoryMap wozmon = MemoryMap.Read(file);
            MemoryMap bare = MemoryMap.Read(Path.Join(environments, "bare", Path.GetFileName(file)));
            (wozmon.Load, wozmon.Free, wozmon.ZeroPage, wozmon.Reserved).Should().BeEquivalentTo(
                (bare.Load, bare.Free, bare.ZeroPage, bare.Reserved), options => options.WithStrictOrdering(), file);

            wozmon.Description.Should().Contain("wozmon", file);
        }
    }

    private TargetBuild Build(string machine, int kilobytes, string source, string? fields = null, string cpu = "6502")
    {
        Write("retrocore.json", $$"""
            { "sdk": "1", "name": "maps", "cpu": "{{cpu}}", "sources": ["main.s"],
              "targets": { "t": { "machine": "{{machine}}", "environment": "bare", "options": { "ramKilobytes": {{kilobytes}} }{{(fields is null ? "" : ", " + fields)}} } } }
            """);

        Write("main.s", source);
        return ProjectBuild.Build(RetrocoreProject.Load(_folder).Target("t"));
    }

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
}
