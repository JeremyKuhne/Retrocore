// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Debug;
using Retrocore.Debug.Language;
using Retrocore.Documentation;
using Retrocore.Machines.Apple2;

namespace Retrocore.Tests;

/// <summary>
///  The SDK's ROM sources keep their <c>;;</c> documentation free of placement errors, broken links and
///  malformed sections.
/// </summary>
[TestClass]
public class SdkDocumentationTests
{
    private static readonly string s_inputs = Path.Join(AppContext.BaseDirectory, "Inputs");

    /// <summary>
    ///  Every SDK source passes the documentation lint, with links reaching the other SDK modules.
    /// </summary>
    [TestMethod]
    public void SdkDocumentationIsClean()
    {
        List<DocumentationSet> sets = Sets();
        List<string> problems = [];
        foreach (DocumentationSet set in sets)
        {
            DocumentationResolver resolver = new(
                set,
                sets,
                isDirective: name => DirectiveDocs.Describe(name) is not null,
                isInstruction: InstructionDocs.IsMnemonic);

            problems.AddRange(resolver.Check().Select(problem =>
                $"{Path.GetFileName(problem.Path)}:{problem.Line + 1}: {problem.Message}"));
        }

        problems.Should().BeEmpty($"the lint found:{Environment.NewLine}{string.Join(Environment.NewLine, problems)}");
    }

    /// <summary>
    ///  Every SDK source passes the lint as the editor runs it: each module's root assembled with the files it
    ///  includes, with links reaching the other modules under the names the editor gives them. The sources are
    ///  checked both as the SDK's own copy and as a repository copy opened beside it, which stands in for the
    ///  SDK's module of the same name.
    /// </summary>
    [TestMethod]
    public void SdkDocumentationIsCleanInTheEditor()
    {
        List<SourceAnalysis> sdk = [.. SdkRoots(s_inputs).Select(file => SourceAnalysis.Assemble(file, _ => null))];
        HashSet<string> problems = [];
        foreach (SourceAnalysis analysis in sdk) { problems.UnionWith(Problems(analysis, sdk, "SDK")); }

        string repository = Directory.CreateTempSubdirectory().FullName;
        try
        {
            foreach (string folder in s_sdkFolders)
            {
                foreach (string file in Directory.EnumerateFiles(Path.Join(s_inputs, folder)))
                {
                    Directory.CreateDirectory(Path.Join(repository, folder));
                    File.Copy(file, Path.Join(repository, folder, Path.GetFileName(file)));
                }
            }

            File.Copy(Path.Join(s_inputs, "Slot7.rom.asm"), Path.Join(repository, "Slot7.rom.asm"));
            foreach (string root in SdkRoots(repository))
            {
                problems.UnionWith(Problems(SourceAnalysis.Assemble(root, _ => null), sdk, "repository"));
            }
        }
        finally
        {
            Directory.Delete(repository, recursive: true);
        }

        problems.Should().BeEmpty($"the editor's lint found:{Environment.NewLine}{string.Join(Environment.NewLine, problems.Order())}");
    }

    /// <summary>
    ///  The TRS-80's ROM sources pass the lint as the editor runs it, Z80 registers and conditions included.
    ///  <c>Model3.asm</c> includes <c>Level2.asm</c>, so the editor reads Level II with the Model III's blocks; it is
    ///  checked on its own too, as the Model I's ROM.
    /// </summary>
    [TestMethod]
    public void Trs80DocumentationIsCleanInTheEditor()
    {
        string folder = Path.Join(s_inputs, "Trs80");
        List<string> roots = SourceIncludes.Roots(folder);
        string[] names = [.. roots.Select(root => Path.GetFileName(root))];
        names.Should().Contain(["Level1.asm", "Model3.asm", "Model4PBoot.asm", "Model2Boot.asm"]);
        names.Should().NotContain("Level2.asm");
        roots.Add(Path.GetFullPath(Path.Join(folder, "Level2.asm")));
        List<SourceAnalysis> sdk = [.. roots.Select(file => SourceAnalysis.Assemble(file, _ => null))];
        List<string> problems = [.. sdk.SelectMany(analysis => Problems(analysis, sdk, "SDK")).Order()];
        problems.Should().BeEmpty($"the editor's lint found:{Environment.NewLine}{string.Join(Environment.NewLine, problems)}");
    }

    // Sources another source includes that are also whole programs of their own, checked as roots too.
    private static readonly string[] s_includedRoots = ["Level2.asm"];

    // Each sample folder's machine project, whose sources its links reach.
    private static readonly Dictionary<string, string> s_sampleMachines = new()
    {
        ["coco"] = "Retrocore.Machines.Coco",
        ["iie"] = "Retrocore.Machines.Apple2",
        ["trs80"] = "Retrocore.Machines.Trs80"
    };

    /// <summary>
    ///  Every assembly source in the repository passes the lint as the editor runs it: each project's sources,
    ///  its ROMs and software together, and each sample with its machine's. It names no source folder, so a new
    ///  source is checked as soon as it is added. A file another source includes is checked as the editor sees it,
    ///  through the source the editor reads it in.
    /// </summary>
    [TestMethod]
    public void EveryRepositorySourceIsCleanInTheEditor()
    {
        string repository = RepositoryRoot();
        Dictionary<string, List<SourceAnalysis>> projects = [];
        foreach (string project in Directory.EnumerateDirectories(Path.Join(repository, "src")))
        {
            projects[Path.GetFileName(project)] = [.. Sources(project).Select(file => SourceAnalysis.Assemble(file, _ => null))];
        }

        List<string> problems = [];
        foreach ((string name, List<SourceAnalysis> sources) in projects)
        {
            problems.AddRange(sources.SelectMany(analysis => OwnProblems(analysis, sources, name)));
        }

        foreach (string sample in Directory.EnumerateDirectories(Path.Join(repository, "sample")))
        {
            List<string> roots = Sources(sample);
            if (roots.Count == 0) { continue; }
            string folder = Path.GetFileName(sample);
            s_sampleMachines.Should().ContainKey(folder, $"sample/{folder}'s links need its machine's project in s_sampleMachines");
            List<SourceAnalysis> sources = [.. roots.Select(file => SourceAnalysis.Assemble(file, _ => null))];
            List<SourceAnalysis> reach = [.. sources, .. projects[s_sampleMachines[folder]]];
            problems.AddRange(sources.SelectMany(analysis => OwnProblems(analysis, reach, $"sample/{folder}")));
        }

        problems.Should().BeEmpty($"the editor's lint found:{Environment.NewLine}{string.Join(Environment.NewLine, problems.Order())}");
    }

    // A folder's roots, with the included sources that are whole programs too, leaving out build output.
    private static List<string> Sources(string folder)
    {
        string bin = $"{Path.DirectorySeparatorChar}bin{Path.DirectorySeparatorChar}";
        string obj = $"{Path.DirectorySeparatorChar}obj{Path.DirectorySeparatorChar}";
        List<string> roots = [.. SourceIncludes.Roots(folder)
            .Where(file => !file.Contains(bin, StringComparison.Ordinal) && !file.Contains(obj, StringComparison.Ordinal))];

        foreach (string name in s_includedRoots)
        {
            roots.AddRange(Directory.EnumerateFiles(folder, name, SearchOption.AllDirectories).Select(Path.GetFullPath));
        }

        return roots;
    }

    // The problems in a root and in the files the editor reads through it.
    private static IEnumerable<string> OwnProblems(SourceAnalysis analysis, List<SourceAnalysis> others, string label)
    {
        DocumentationResolver resolver = new(
            analysis.Documentation,
            analysis.OtherModules(others).Select(other => other.Documentation),
            isDirective: name => DirectiveDocs.Describe(name) is not null,
            isInstruction: InstructionDocs.IsMnemonic);

        string root = Path.GetFullPath(analysis.Root);
        string folder = Path.GetDirectoryName(root) ?? "";
        return resolver.Check()
            .Where(problem => Path.GetFullPath(problem.Path) == root || SourceIncludes.RootOf(Path.GetFullPath(problem.Path)) == root)
            .Select(problem => $"{label} {Path.GetRelativePath(folder, problem.Path)}:{problem.Line + 1}: {problem.Message}");
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
    ///  The Apple III's ROM source passes the lint as the editor runs it, with its equates file.
    /// </summary>
    [TestMethod]
    public void Apple3DocumentationIsCleanInTheEditor()
    {
        string folder = Path.Join(s_inputs, "Apple3");
        List<SourceAnalysis> sdk = [.. SourceIncludes.Roots(folder).Select(file => SourceAnalysis.Assemble(file, _ => null))];
        sdk.Select(analysis => Path.GetFileName(analysis.Root)).Should().Contain("BootRom.asm");
        List<string> problems = [.. sdk.SelectMany(analysis => Problems(analysis, sdk, "SDK")).Order()];
        problems.Should().BeEmpty($"the editor's lint found:{Environment.NewLine}{string.Join(Environment.NewLine, problems)}");
    }

    /// <summary>
    ///  The Apple-1's sources pass the lint as the editor runs it: the Woz Monitor, the cassette interface, the
    ///  character generator and Apple-1 BASIC.
    /// </summary>
    [TestMethod]
    public void Apple1DocumentationIsCleanInTheEditor()
    {
        string folder = Path.Join(s_inputs, "Apple1");
        List<SourceAnalysis> sdk =
        [
            .. SourceIncludes.Roots(folder)
                .Concat(SourceIncludes.Roots(Path.Join(folder, "Basic")))
                .Select(file => SourceAnalysis.Assemble(file, _ => null))
        ];

        string[] names = [.. sdk.Select(analysis => Path.GetFileName(analysis.Root))];
        names.Should().Contain(["WozMonitor.asm", "Aci.asm", "Basic.asm"]);
        List<string> problems = [.. sdk.SelectMany(analysis => Problems(analysis, sdk, "SDK")).Order()];
        problems.Should().BeEmpty($"the editor's lint found:{Environment.NewLine}{string.Join(Environment.NewLine, problems)}");
    }

    /// <summary>
    ///  The Color Computer's ROM sources pass the lint as the editor runs it, 6809 registers and flags included.
    /// </summary>
    [TestMethod]
    public void CocoDocumentationIsCleanInTheEditor()
    {
        string folder = Path.Join(s_inputs, "Coco");
        List<SourceAnalysis> sdk = [.. SourceIncludes.Roots(folder).Select(file => SourceAnalysis.Assemble(file, _ => null))];
        string[] names = [.. sdk.Select(analysis => Path.GetFileName(analysis.Root))];
        names.Should().Contain("ColorBasic.asm");
        List<string> problems = [.. sdk.SelectMany(analysis => Problems(analysis, sdk, "SDK")).Order()];
        problems.Should().BeEmpty($"the editor's lint found:{Environment.NewLine}{string.Join(Environment.NewLine, problems)}");
    }

    private static readonly string[] s_sdkFolders = ["AppleSoft", "DiskII", "Dos", "IntegerBasic", "ProgrammersAid", "System"];

    // The SDK's modules as the editor indexes them: the roots among the IIe's ROM sources.
    private static IEnumerable<string> SdkRoots(string roms) =>
        s_sdkFolders
            .SelectMany(folder => SourceIncludes.Roots(Path.Join(roms, folder)))
            .Append(Path.GetFullPath(Path.Join(roms, "Slot7.rom.asm")));

    // The lint's findings for one module, its links reaching the SDK's other modules as the editor's do.
    private static IEnumerable<string> Problems(SourceAnalysis analysis, List<SourceAnalysis> sdk, string copy)
    {
        DocumentationResolver resolver = new(
            analysis.Documentation,
            analysis.OtherModules(sdk).Select(other => other.Documentation),
            isDirective: name => DirectiveDocs.Describe(name) is not null,
            isInstruction: InstructionDocs.IsMnemonic);

        return resolver.Check().Select(problem => $"{copy} {Path.GetFileName(problem.Path)}:{problem.Line + 1}: {problem.Message}");
    }

    /// <summary>
    ///  The Monitor's other builds pass the lint too: the II's, the II Plus's and the original IIe's own routines'
    ///  documentation, and the links in it, with the other modules as the Enhanced IIe's Monitor sees them.
    /// </summary>
    /// <param name="model">The II (the original Monitor), II Plus (the Autostart Monitor) or original IIe.</param>
    [TestMethod]
    [DataRow(Apple2Model.II)]
    [DataRow(Apple2Model.IIPlus)]
    [DataRow(Apple2Model.IIe)]
    public void MonitorBuildsForTheIIAreClean(Apple2Model model)
    {
        List<DocumentationSet> others = Sets();
        string path = Path.GetFullPath(Path.Join(s_inputs, "System", "Monitor.asm"));
        AssemblyResult result = SdkModules.AssembleSystem(path, SdkModules.MonitorOrigin, SdkModules.MonitorSize, model);
        DocumentationSet monitor = Set(result, "Monitor", model.DocumentationName());
        DocumentationResolver resolver = new(
            monitor,
            others,
            isDirective: name => DirectiveDocs.Describe(name) is not null,
            isInstruction: InstructionDocs.IsMnemonic);

        List<string> problems = [.. resolver.Check()
            .Where(problem => Path.GetFileName(problem.Path) == "Monitor.asm")
            .Select(problem => $"{Path.GetFileName(problem.Path)}:{problem.Line + 1}: {problem.Message}")];

        problems.Should().BeEmpty($"the lint found:{Environment.NewLine}{string.Join(Environment.NewLine, problems)}");
    }

    /// <summary>
    ///  The IIe sample documents its exports, so the editor shows it without documentation warnings.
    /// </summary>
    [TestMethod]
    public void SampleDocumentationIsClean()
    {
        string source = Path.GetFullPath(Path.Join(s_inputs, "IIe", "main.s"));
        string config = Path.Join(s_inputs, "IIe", "link.cfg");
        AssemblyResult result = new Retrocore.Assembler.Assembler().Assemble(
            new AssemblySource(File.ReadAllText(source), source),
            new AssemblyOptions(ProcessorVariant.Mos6502, 0x6000, 0x6000)
            {
                Dialect = AssemblyDialect.Ca65,
                LinkerConfiguration = new(File.ReadAllText(config), config)
            });

        result.Diagnostics.Should().BeEmpty();
        DocumentationSet set = DocumentationSet.Create([DocumentationParser.Parse(File.ReadAllText(source), source)], result);
        set.Exports.Select(export => export.Name).Should().BeEquivalentTo(["entry", "after_call", "counter"]);
        new DocumentationResolver(set).Check().Should().BeEmpty();
    }

    /// <summary>
    ///  The Monitor documents its entry points, and their contracts are what the debugger checks.
    /// </summary>
    [TestMethod]
    public void MonitorContractsAreBuilt()
    {
        List<DocumentationSet> sets = Sets();
        DocumentationSet monitor = sets.Single(set => set.Module == "Monitor");
        monitor.Topics.Count(topic => topic.Kind == DocumentationKind.Routine).Should().BeGreaterThan(100);
        DocumentationTopic plot = monitor.Find("PLOT") ?? throw new AssertFailedException("PLOT is not documented.");
        plot.Summary.Should().StartWith("Plots one lo-res block");
        plot.Value.Should().Be(0xF800);

        Dictionary<ushort, DebugContract> contracts = DebugContracts.Build(
            new DocumentationResolver(monitor, sets),
            "Enhanced",
            new DebugRegisters(M6502Isa.Description));

        contracts[0xF800].Registers.Should().Contain(["X", "Y"]);
    }

    private static List<DocumentationSet> Sets()
    {
        List<DocumentationSet> sets = [];
        foreach ((string file, int origin, int size, Apple2Model model, string module) in (
            (string, int, int, Apple2Model, string)[])
            [
                ("Monitor.asm", SdkModules.MonitorOrigin, SdkModules.MonitorSize, Apple2Model.IIeEnhanced, "Monitor"),
                ("Firmware.Enhanced.asm", SdkModules.FirmwareOrigin, SdkModules.FirmwareSize, Apple2Model.IIeEnhanced, "Firmware"),
                ("Firmware.Original.asm", SdkModules.FirmwareOrigin, SdkModules.FirmwareSize, Apple2Model.IIe, "Firmware")
            ])
        {
            string path = Path.GetFullPath(Path.Join(s_inputs, "System", file));
            AssemblyResult result = SdkModules.AssembleSystem(path, origin, size, model);
            string? modelName = file.Contains("Enhanced", StringComparison.Ordinal) ? "Enhanced"
                : file.Contains("Original", StringComparison.Ordinal) ? "Original" : null;

            sets.Add(Set(result, module, modelName));
        }

        // Slot 7's ROM, without the source generator's .rom declaration; its exports are the C# card's API.
        string slot7 = Path.GetFullPath(Path.Join(s_inputs, "Slot7.rom.asm"));
        string slot7Text = string.Join("\n", File.ReadAllLines(slot7).Where(line => !line.StartsWith(".rom", StringComparison.Ordinal)));
        AssemblyResult card = new Retrocore.Assembler.Assembler().Assemble(
            new AssemblySource(slot7Text, slot7),
            new AssemblyOptions(ProcessorVariant.Mos6502, 0xC700, 0x100));

        card.Success.Should().BeTrue();
        sets.Add(DocumentationSet.Create([DocumentationParser.Parse(slot7Text, slot7)], card, "Slot7"));

        string appleSoft = Path.GetFullPath(Path.Join(s_inputs, "AppleSoft", "applesoft.mac"));
        string m6502 = Path.GetFullPath(Path.Join(s_inputs, "AppleSoft", "m6502.asm"));
        AssemblyResult basic = SdkModules.AssembleAppleSoft(appleSoft, Apple2Model.IIeEnhanced);
        sets.Add(DocumentationSet.Create(
            [
                DocumentationParser.Parse(File.ReadAllText(appleSoft), appleSoft),
                DocumentationParser.Parse(File.ReadAllText(m6502), m6502)
            ],
            basic,
            "AppleSoft"));

        // The video ROM, the Disk II's ROMs and DOS, each with every file its assembly reads, named as the editor
        // names them.
        sets.Add(Set(SdkModules.AssembleCharacterGenerator(SdkModules.CharacterGeneratorPath(s_inputs), Apple2Model.IIeEnhanced), "Video"));
        foreach (string file in (ReadOnlySpan<string>)["Boot16.asm", "Boot13.asm"])
        {
            AssemblyResult boot = SdkModules.AssembleDiskII(SdkModules.DiskIIPath(file, s_inputs), SdkModules.DiskIIOrigin);
            sets.Add(Set(boot, SourceAnalysis.ModuleOf(file)));
        }

        foreach (string file in (ReadOnlySpan<string>)["Sequencer16.asm", "Sequencer13.asm"])
        {
            AssemblyResult sequencer = SdkModules.AssembleDiskII(SdkModules.DiskIIPath(file, s_inputs), origin: 0);
            sets.Add(Set(sequencer, SourceAnalysis.ModuleOf(file)));
        }

        sets.Add(Set(SdkModules.AssembleDos(SdkModules.DosPath("Dos33.asm", s_inputs), master: true), "Dos33"));
        sets.Add(Set(SdkModules.AssembleDos(SdkModules.DosPath("Dos32.asm", s_inputs), master: true), "Dos32"));
        sets.Add(Set(SdkModules.AssembleIntegerBasic(SdkModules.IntegerBasicPath(s_inputs)), "IntegerBasic"));
        sets.Add(Set(SdkModules.AssembleProgrammersAid(SdkModules.ProgrammersAidPath(s_inputs)), "ProgrammersAid"));

        // Apple's 3.5 controller's EPROM: the host's code, the diagnostics and the card's 65C02 firmware.
        string disk35 = Path.GetFullPath(Path.Join(s_inputs, "Disk35", "Disk35Controller.asm"));
        AssemblyOptions options = new(ProcessorVariant.Wdc65C02, 0x8000, 0x8000)
        {
            SourceResolver = new FileAssemblySourceResolver()
        };

        AssemblyResult controller = new Retrocore.Assembler.Assembler().Assemble(
            new AssemblySource(File.ReadAllText(disk35), disk35),
            options);

        controller.Success.Should().BeTrue();
        sets.Add(Set(controller, "Disk35"));
        return sets;
    }

    // A module's documentation: every source file its assembly took statements or symbols from.
    private static DocumentationSet Set(AssemblyResult result, string module, string? model = null)
    {
        IEnumerable<string?> paths = result.SourceMap
            .Select(entry => entry.Location?.Path)
            .Concat(result.SymbolDefinitions.Select(symbol => symbol.Location?.Path));

        List<DocumentationFile> files = [.. paths
            .OfType<string>()
            .Where(File.Exists)
            .Select(Path.GetFullPath)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .Select(path => DocumentationParser.Parse(File.ReadAllText(path), path))];

        return DocumentationSet.Create(files, result, module, model);
    }
}
