// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Debug.Language;
using Retrocore.Documentation;
using Retrocore.Debug.Project;
using Retrocore.Machines.Apple1;
using System.Globalization;
using System.Text.RegularExpressions;

namespace Retrocore.Tests;

/// <summary>
///  A target's build gets the SDK's <c>RC_</c> defines and its headers: <c>&lt;cpu.inc&gt;</c>,
///  <c>&lt;machine.inc&gt;</c> and <c>&lt;environment.inc&gt;</c> resolve to its own, each asserts the target it is
///  for, and the entry points the headers name are where their ROM sources put them.
/// </summary>
[TestClass]
public sealed partial class ProjectHeaderTests
{
    private string _folder = "";

    /// <summary>
    ///  Gets each test a folder of its own.
    /// </summary>
    [TestInitialize]
    public void Initialize()
    {
        _folder = Path.Join(Path.GetTempPath(), "retrocore-headers-" + Guid.NewGuid().ToString("N"));
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
    ///  The defines name the SDK, the target's CPU and every CPU whose code it runs, its machine's family and model, its
    ///  environment, RAM and screen, and its name as text.
    /// </summary>
    [TestMethod]
    public void DefinesDescribeTheTarget()
    {
        Write("retrocore.json", """
            { "sdk": "1", "cpu": "6502", "sources": ["main.s"], "targets": {
                "iie": { "machine": "apple2-iie-enhanced", "environment": "bare", "cpu": "65c02" },
                "apple1": { "machine": "apple1", "environment": "bare", "options": { "ramKilobytes": 32 } },
                "pet": { "machine": "pet4032", "environment": "bare" } } }
            """);

        Write("main.s", ".byte RC_TARGET, RC_RAM_KB, RC_SCREEN_COLUMNS, RC_SCREEN_ROWS");
        RetrocoreProject project = RetrocoreProject.Load(_folder);
        Dictionary<string, long> iie = project.Target("iie").Symbols();
        iie.Where(pair => pair.Key.StartsWith("RC_", StringComparison.Ordinal)).Should().BeEquivalentTo(new Dictionary<string, long>
        {
            ["RC_SDK"] = 1,
            ["RC_CPU_6502"] = 1,
            ["RC_CPU_65C02"] = 1,
            ["RC_MACHINE_APPLE2"] = 1,
            ["RC_MODEL_APPLE2_IIE_ENHANCED"] = 1,
            ["RC_ENV_BARE"] = 1,
            ["RC_RAM_KB"] = 48,
            ["RC_SCREEN_COLUMNS"] = 40,
            ["RC_SCREEN_ROWS"] = 24
        });

        File.ReadAllBytes(ProjectBuild.Build(project.Target("iie")).Binary).Should().Equal((byte)'i', (byte)'i', (byte)'e', 48, 40, 24);
        File.ReadAllBytes(ProjectBuild.Build(project.Target("apple1")).Binary).Should().Equal([.. "apple1"u8, 32, 40, 24]);
        File.ReadAllBytes(ProjectBuild.Build(project.Target("pet")).Binary).Should().Equal([.. "pet"u8, 32, 40, 25]);
        project.Target("pet").Symbols().Should().ContainKey("RC_MODEL_PET4032").And.ContainKey("RC_MACHINE_PET")
            .And.NotContainKey("RC_CPU_65C02");
    }

    /// <summary>
    ///  The assembler's textual predefinitions expand where their names appear, in native and ca65 sources alike, and
    ///  <c>.undefine</c> removes one; a name that is not an identifier is refused.
    /// </summary>
    /// <param name="dialect">The source's dialect.</param>
    [TestMethod]
    [DataRow(AssemblyDialect.Native)]
    [DataRow(AssemblyDialect.Ca65)]
    public void PredefinedTextsExpand(AssemblyDialect dialect)
    {
        AssemblyOptions options = new(ProcessorVariant.Mos6502, 0x6000, 0x100)
        {
            Dialect = dialect,
            PredefinedTexts = new Dictionary<string, string> { ["NAME"] = "\"ab\"", ["VALUE"] = "2 + 3" }
        };

        string source = ".byte NAME, VALUE\n.undefine VALUE\n.ifdef VALUE\n.byte 9\n.endif\n";
        AssemblyResult result = new Assembler.Assembler().Assemble(new AssemblySource(source, "test.s"), options);
        result.Success.Should().BeTrue(string.Join(Environment.NewLine, result.Diagnostics.Select(error => error.Message)));
        Retrocore.Debug.SourceBuild.Emitted(result).Single().Bytes.ToArray().Should().Equal((byte)'a', (byte)'b', 5);

        Action invalid = () => _ = new AssemblyOptions(ProcessorVariant.Mos6502, 0, 1)
        {
            PredefinedTexts = new Dictionary<string, string> { ["NOT A NAME"] = "1" }
        };

        invalid.Should().Throw<ArgumentException>();
    }

    /// <summary>
    ///  Every machine in the catalog has its RAM and its screen, so every target gets every define.
    /// </summary>
    [TestMethod]
    public void EveryMachineHasItsRamAndScreen()
    {
        foreach (CatalogMachine machine in CatalogMachine.All)
        {
            Write("retrocore.json", $$"""
                { "sdk": "1", "cpu": "{{machine.Cpu.Name}}", "targets": { "t": { "machine": "{{machine.Id}}", "environment": "bare" } } }
                """);

            Dictionary<string, long> symbols = RetrocoreProject.Load(_folder).Target("t").Symbols();
            symbols["RC_RAM_KB"].Should().BePositive(machine.Id);
            symbols["RC_SCREEN_COLUMNS"].Should().BePositive(machine.Id);
            symbols["RC_SCREEN_ROWS"].Should().BePositive(machine.Id);
            symbols.Should().ContainKey($"RC_MACHINE_{TargetDefines.Part(machine.Family)}", machine.Id)
                .And.ContainKey($"RC_CPU_{TargetDefines.Part(machine.Cpu.Name)}", machine.Id);
        }
    }

    /// <summary>
    ///  The Model I's RAM follows its Expansion Interface as its launch does: 48K with it, which Level II has unless
    ///  its target says not and Level I only when it says so.
    /// </summary>
    /// <param name="machine">The catalog machine.</param>
    /// <param name="options">The target's options.</param>
    /// <param name="ram">Its RAM, in kilobytes.</param>
    [TestMethod]
    [DataRow("trs80-model1-level2", "{}", 48)]
    [DataRow("trs80-model1-level2", "{ \"expansionInterface\": false }", 16)]
    [DataRow("trs80-model1-level1", "{}", 4)]
    [DataRow("trs80-model1-level1", "{ \"expansionInterface\": true }", 48)]
    [DataRow("trs80-model1-level1", "{ \"ramKilobytes\": 16 }", 16)]
    public void ModelIRamFollowsTheExpansionInterface(string machine, string options, int ram)
    {
        Write("retrocore.json", $$"""
            { "sdk": "1", "cpu": "z80", "targets": { "t": { "machine": "{{machine}}", "environment": "bare", "options": {{options}} } } }
            """);

        RetrocoreProject.Load(_folder).Target("t").Symbols()["RC_RAM_KB"].Should().Be(ram);
    }

    /// <summary>
    ///  A source may use the SDK's names but not define one: a constant or label starting with RC_, in any case, is an
    ///  error naming the file and line.
    /// </summary>
    /// <param name="source">The definition.</param>
    [TestMethod]
    [DataRow("RC_COLUMNS = 40")]
    [DataRow("rc_putchar:\n    rts")]
    [DataRow(".proc Main\nRC_LOOP:\n    rts\n.endproc")]
    [DataRow(".define RC_FAST 1")]
    [DataRow(".macro rc_getkey\n    rts\n.endmacro")]
    public void SourcesCannotDefineTheSdksNames(string source)
    {
        Write("retrocore.json", """
            { "sdk": "1", "cpu": "6502", "sources": ["main.s"], "targets": { "t": { "machine": "apple2-iiplus", "environment": "bare" } } }
            """);

        Write("main.s", "    nop\n" + source + "\n.if 0\n.define RC_OFF 1\n.endif");
        Error(() => ProjectBuild.Build(RetrocoreProject.Load(_folder).Target("t")))
            .Should().MatchRegex(@"main\.s\([23]\): [A-Za-z_:]*(RC_|rc_)").And.Contain("names starting with RC_ are the SDK's");
    }

    /// <summary>
    ///  The same three includes build on each of the five starting machines, each finding its own headers, and a
    ///  65C02 target's code can test for the CMOS instructions.
    /// </summary>
    /// <param name="machine">The catalog machine.</param>
    /// <param name="cpu">The target's CPU.</param>
    [TestMethod]
    [DataRow("apple1", "6502")]
    [DataRow("apple2-iiplus", "6502")]
    [DataRow("apple2-iie-enhanced", "65c02")]
    [DataRow("apple3", "6502")]
    [DataRow("pet2001", "6502")]
    [DataRow("pet4032", "6502")]
    [DataRow("bbcb", "6502")]
    public void HeadersResolveForEachMachine(string machine, string cpu)
    {
        Write("retrocore.json", $$"""
            { "sdk": "1", "cpu": "6502", "sources": ["main.s"], "targets": { "t": { "machine": "{{machine}}", "environment": "bare", "cpu": "{{cpu}}" } } }
            """);

        Write("main.s", """
            .include <cpu.inc>
            .include <machine.inc>
            .include <environment.inc>
            .if .defined(RC_CPU_65C02)
                stz ResetVector
            .else
                lda ResetVector
            .endif
                rts
            """);

        byte[] bytes = File.ReadAllBytes(ProjectBuild.Build(RetrocoreProject.Load(_folder).Target("t")).Binary);
        bytes.Should().Equal(cpu == "65c02" ? (byte)0x9C : (byte)0xAD, 0xFC, 0xFF, 0x60);
    }

    /// <summary>
    ///  A header included for a target it is not for fails at once, naming what it is for.
    /// </summary>
    [TestMethod]
    public void HeadersAssertTheirTargets()
    {
        Write("retrocore.json", """
            { "sdk": "1", "cpu": "6502", "sources": ["main.s"], "targets": { "t": { "machine": "pet4032", "environment": "bare" } } }
            """);

        Write("main.s", ".include <machines/apple2/machine.inc>\nrts");
        Error(() => ProjectBuild.Build(RetrocoreProject.Load(_folder).Target("t")))
            .Should().Contain("machine.inc for the Apple II is for targets whose machine is an Apple II.");

        Write("main.s", ".include <environments/bare/environment.inc>\n.include <cpus/6502/cpu.inc>\nrts");
        File.ReadAllBytes(ProjectBuild.Build(RetrocoreProject.Load(_folder).Target("t")).Binary).Should().Equal(0x60);
    }

    /// <summary>
    ///  Each entry a header names with <c>Inherit:</c> is at the address its ROM source gives the label it inherits,
    ///  so the header's names cannot drift from the ROMs.
    /// </summary>
    [TestMethod]
    public void HeaderEntriesAreWhereTheirRomsPutThem()
    {
        string repository = RepositoryRoot();
        string sdk = Path.Join(repository, "sdk");
        Dictionary<string, AssemblyResult> modules = [];
        int checkedEntries = 0;
        foreach (string header in Directory.EnumerateFiles(sdk, "*.inc", SearchOption.AllDirectories))
        {
            string[] lines = File.ReadAllLines(header);
            for (int index = 0; index < lines.Length; index++)
            {
                if (InheritLine().Match(lines[index]) is not { Success: true } inherit) { continue; }
                int definition = Array.FindIndex(lines, index, line => !line.StartsWith(";;", StringComparison.Ordinal));
                Match equate = EquateLine().Match(lines[definition]);
                equate.Success.Should().BeTrue($"{header}:{definition + 1} defines what it inherits as an address");

                string module = inherit.Groups["module"].Value;
                if (!modules.TryGetValue(module, out AssemblyResult? result))
                {
                    string source = Directory.EnumerateFiles(Path.Join(repository, "src"), module + ".asm", SearchOption.AllDirectories).Single();
                    result = SourceAnalysis.Assemble(source, _ => null).Result;
                    result.Success.Should().BeTrue($"{module} assembles");
                    modules[module] = result;
                }

                string label = inherit.Groups["label"].Value;
                result.Symbols.Should().ContainKey(label, $"{module} defines {label}");
                long address = long.Parse(equate.Groups["value"].Value, NumberStyles.HexNumber, CultureInfo.InvariantCulture);
                result.Symbols[label].Should().Be(address, $"{Path.GetFileName(header)}'s {equate.Groups["name"].Value} is {module}'s {label}");
                checkedEntries++;
            }
        }

        checkedEntries.Should().BeGreaterThan(20);
    }

    /// <summary>
    ///  Each machine's headers pass the editor's lint as a project on that machine sees them, their links reaching
    ///  the ROM sources they inherit from.
    /// </summary>
    /// <param name="machine">The catalog machine.</param>
    /// <param name="modules">The ROM sources the headers link to.</param>
    [TestMethod]
    [DataRow("apple1", "WozMonitor")]
    [DataRow("apple2-iie-enhanced", "Monitor")]
    [DataRow("apple3", "")]
    [DataRow("pet4032", "Kernal4")]
    [DataRow("bbcb", "Mos")]
    public void HeadersAreCleanInTheEditor(string machine, string modules)
    {
        Write("retrocore.json", $$"""
            { "sdk": "1", "cpu": "6502", "sources": ["main.s"], "targets": { "t": { "machine": "{{machine}}", "environment": "bare" } } }
            """);

        Write("main.s", ".include <cpu.inc>\n.include <machine.inc>\n.include <environment.inc>\nrts");
        ProjectTarget target = RetrocoreProject.Load(_folder).Target("t");
        SourceAnalysis analysis = SourceAnalysis.Assemble(ProjectSources.RootFor(target), _ => null);
        analysis.Result.Success.Should().BeTrue(string.Join(Environment.NewLine, analysis.Result.Diagnostics.Select(error => error.Message)));

        string src = Path.Join(RepositoryRoot(), "src");
        List<SourceAnalysis> others = [.. modules.Split(',', StringSplitOptions.RemoveEmptyEntries)
            .Select(module => Directory.EnumerateFiles(src, module + ".asm", SearchOption.AllDirectories).Single())
            .Select(root => SourceAnalysis.Assemble(root, _ => null))];

        DocumentationResolver resolver = new(
            analysis.Documentation,
            analysis.OtherModules(others).Select(other => other.Documentation),
            isDirective: name => DirectiveDocs.Describe(name) is not null,
            isInstruction: InstructionDocs.IsMnemonic);

        List<string> problems = [.. resolver.Lint()
            .Where(problem => problem.Path.EndsWith(".inc", StringComparison.OrdinalIgnoreCase))
            .Select(problem => $"{Path.GetFileName(Path.GetDirectoryName(problem.Path))}/{Path.GetFileName(problem.Path)}:{problem.Line + 1}: {problem.Text}")];

        problems.Should().BeEmpty($"the lint found:{Environment.NewLine}{string.Join(Environment.NewLine, problems)}");
        analysis.Members.Should().Contain(member => member.EndsWith("machine.inc", StringComparison.OrdinalIgnoreCase));
    }

    /// <summary>
    ///  The Apple-1's header names the PIA's four registers, which the machine's bus maps to its PIA.
    /// </summary>
    [TestMethod]
    public void Apple1PiaEquatesAreThePias()
    {
        string header = File.ReadAllText(Path.Join(RepositoryRoot(), "sdk", "1", "machines", "apple1", "machine.inc"));
        Apple1Bus bus = new Apple1Machine(new() { RamKilobytes = 32 }, Apple1MachineTests.Roms).Bus;
        foreach ((string name, ushort address) in (ReadOnlySpan<(string, ushort)>)
            [("Keyboard", 0xD010), ("KeyboardControl", 0xD011), ("Display", 0xD012), ("DisplayControl", 0xD013)])
        {
            header.Should().Contain($"\n{name} = ${address:X4}");
            bus.Area(address).Should().Be(Apple1MemoryArea.Pia, name);
        }
    }

    [GeneratedRegex(@"^;; Inherit: <(?<module>[A-Za-z0-9]+):(?<label>[A-Za-z0-9_:]+)>$")]
    private static partial Regex InheritLine();

    [GeneratedRegex(@"^(?<name>[A-Za-z_][A-Za-z0-9_]*) = \$(?<value>[0-9A-F]+)$")]
    private static partial Regex EquateLine();

    private static string RepositoryRoot()
    {
        string? root = AppContext.BaseDirectory;
        while (root is not null && !File.Exists(Path.Join(root, "Retrocore.slnx")))
        {
            root = Path.GetDirectoryName(root);
        }

        return root ?? throw new InvalidOperationException("The repository root was not found.");
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
