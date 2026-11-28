// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Cpu.Z80;
using Retrocore.Debug;
using Retrocore.Debug.Language;
using Retrocore.Documentation;
using Retrocore.Machines.Apple2;
using Retrocore.Machines.Commodore;

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

            problems.AddRange(resolver.Lint().Select(problem =>
                $"{Path.GetFileName(problem.Path)}:{problem.Line + 1}: {problem.Text}"));
        }

        problems.Should().BeEmpty($"the lint found:{Environment.NewLine}{string.Join(Environment.NewLine, problems)}");
    }

    /// <summary>
    ///  AppleSoft's documentation references resolve for each ROM variant.
    /// </summary>
    /// <param name="model">The Apple II model.</param>
    [TestMethod]
    [DataRow(Apple2Model.IIPlus)]
    [DataRow(Apple2Model.IIe)]
    [DataRow(Apple2Model.IIeEnhanced)]
    public void AppleSoftDocumentationIsCleanForEachModel(Apple2Model model)
    {
        AssemblyResult result = SdkModules.AssembleAppleSoft(SdkModules.AppleSoftPath(s_inputs), model);
        DocumentationSet basic = Set(result, "AppleSoft");
        foreach (string name in (string[])
            ["FADD", "NORMAL", "SHIFTR", "FONE", "LOGCN2", "LOG", "Functions::Log::MultiplyByLogOfTwo", "FMULT", "FDIV", "MOVFM", "MOVMF", "ROUND", "SIGN", "FCOMP",
             "QINT", "INT", "FIN", "FINEDG", "NZ9999", "FOUT", "FHALF", "FOUTBL", "SQR", "EXPCON", "EXP",
             "POLY", "RND", "RMULZC", "SIN", "Functions::Tan::ToDividePacked", "SINCON", "ATN", "ATNCON"])
        {
            basic.FindTopic(name).Should().NotBeNull($"the shared macro must retain {name}'s documentation");
        }

        DocumentationResolver resolver = new(
            basic,
            Sets().Where(set => set.Module != "AppleSoft"),
            isDirective: name => DirectiveDocs.Describe(name) is not null,
            isInstruction: InstructionDocs.IsMnemonic);

        var problems = resolver.Check();
        problems.Should().BeEmpty($"AppleSoft documentation must resolve for {model}");
    }

    /// <summary>
    ///  Each native PET BASIC listing resolves its documentation against its own build.
    /// </summary>
    /// <param name="model">The PET model.</param>
    /// <param name="original">Whether BASIC 1 or 4 uses its original first chip.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, false)]
    [DataRow(PetModel.Pet2001, true)]
    [DataRow(PetModel.Pet2001Basic2, false)]
    [DataRow(PetModel.Pet4032, false)]
    [DataRow(PetModel.Pet4032, true)]
    public void PetBasicDocumentationIsClean(PetModel model, bool original)
    {
        AssemblyResult result = PetSdkModules.AssembleBasic(
            Path.Join(s_inputs, "Pet"), model, original, BasicSourceKind.Native);

        DocumentationSet basic = Set(result, "PetBasic");
        DocumentationResolver resolver = new(
            basic,
            isDirective: name => DirectiveDocs.Describe(name) is not null,
            isInstruction: InstructionDocs.IsMnemonic);

        var problems = resolver.Check();
        problems.Should().BeEmpty(string.Join(Environment.NewLine, problems.Select(problem =>
            $"{Path.GetFileName(problem.Path)}:{problem.Line + 1}: {problem.Message}")));
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
                // A module's parts may be in a folder of their own, as the Monitor's are.
                string source = Path.Join(s_inputs, folder);
                foreach (string file in Directory.EnumerateFiles(source, "*", SearchOption.AllDirectories))
                {
                    string copy = Path.Join(repository, folder, Path.GetRelativePath(source, file));
                    Directory.CreateDirectory(Path.GetDirectoryName(copy) ?? repository);
                    File.Copy(file, copy);
                }
            }

            File.Copy(Path.Join(s_inputs, "Slot7.rom.asm"), Path.Join(repository, "Slot7.rom.asm"));
            File.Copy(Path.Join(s_inputs, "ProDosBlockDevice.asm"), Path.Join(repository, "ProDosBlockDevice.asm"));
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
    ///  The IIe equates use ROM as a word, not the Apple III boot ROM's definition of that name.
    /// </summary>
    [TestMethod]
    public void IIeEquatesCanExcludeRomAsAnUnlinkedName()
    {
        SourceAnalysis monitor = SourceAnalysis.Assemble(Path.Join(s_inputs, "System", "Monitor.asm"), _ => null);
        SourceAnalysis apple3 = SourceAnalysis.Assemble(Path.Join(s_inputs, "Apple3", "BootRom.asm"), _ => null);
        DocumentationResolver resolver = new(monitor.Documentation, [apple3.Documentation]);
        DocumentationTopic equate = monitor.Documentation.Find("LanguageCardRomOnly")
            ?? throw new AssertFailedException("The IIe's language card ROM switch is not documented.");

        DocumentationTopic rom = apple3.Documentation.Find("ROM")
            ?? throw new AssertFailedException("The Apple III's ROM flag is not documented.");

        resolver.Resolve(equate, "ROM").Topic.Should().BeSameAs(rom);

        static bool RomInIIeEquates(DocumentationDiagnostic diagnostic) =>
            Path.GetFileName(diagnostic.Path) == "IIeEquates.asm"
                && diagnostic.Rule == DocumentationRules.UnlinkedName
                && diagnostic.Name == "ROM";

        resolver.Check().Where(RomInIIeEquates).Should().NotBeEmpty();
        DocumentationResolver configured = new(monitor.Documentation, [apple3.Documentation])
        {
            IgnoreUnlinkedName = (_, name) => name == "ROM"
        };

        configured.Lint().Where(RomInIIeEquates).Should().BeEmpty();
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
        ["adventure"] = "Retrocore.Machines.Apple2",
        ["atari"] = "Retrocore.Machines.Atari",
        ["bbc"] = "Retrocore.Machines.Acorn",
        ["coco"] = "Retrocore.Machines.Coco",
        ["iie"] = "Retrocore.Machines.Apple2",
        ["project"] = "Retrocore.Machines.Apple2",
        ["softcard"] = "Retrocore.Machines.Apple2",
        ["trs80"] = "Retrocore.Machines.Trs80",
        ["z80"] = "Retrocore.Machines.Trs80"
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
        string src = Path.Join(repository, "src");
        string[] projectFolders = [.. Directory.EnumerateDirectories(src)];
        Dictionary<string, HashSet<string>> projectRoots = [];
        foreach (string project in projectFolders)
        {
            projectRoots[Path.GetFileName(project)] = [with(StringComparer.OrdinalIgnoreCase)];
        }

        foreach (string project in projectFolders)
        {
            foreach (string root in Sources(project))
            {
                string owner = Path.GetRelativePath(src, root).Split(Path.DirectorySeparatorChar)[0];
                if (!projectRoots.TryGetValue(owner, out HashSet<string>? roots))
                {
                    roots = projectRoots[Path.GetFileName(project)];
                }

                roots.Add(root);
            }
        }

        Dictionary<string, List<SourceAnalysis>> projects = projectRoots.ToDictionary(
            pair => pair.Key,
            pair => pair.Value.Select(file => SourceAnalysis.Assemble(file, _ => null)).ToList());

        List<string> problems = [];
        foreach ((string name, List<SourceAnalysis> sources) in projects)
        {
            List<SourceAnalysis> machineSources = name == "Retrocore.Machines.Apple2"
                ? [.. sources.Where(source =>
                    !Path.GetFileName(source.Root).Equals("applesoft.mac", StringComparison.OrdinalIgnoreCase))]
                : sources;

            foreach (SourceAnalysis analysis in sources)
            {
                List<SourceAnalysis> linked = Path.GetFileName(analysis.Root).Equals("applesoft.mac", StringComparison.OrdinalIgnoreCase)
                    ? sources
                    : machineSources;

                problems.AddRange(OwnProblems(analysis, linked, name));
            }
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

        // The templates retrocore new copies into a project, whose sources they become.
        foreach (string template in Directory.EnumerateDirectories(Path.Join(repository, "sdk", "1", "templates")))
        {
            List<string> roots = Sources(template);
            if (roots.Count == 0) { continue; }
            List<SourceAnalysis> sources = [.. roots.Select(file => SourceAnalysis.Assemble(file, _ => null))];
            List<SourceAnalysis> reach = [.. sources, .. projects["Retrocore.Machines.Apple2"]];
            string name = $"sdk/1/templates/{Path.GetFileName(template)}";
            problems.AddRange(sources.SelectMany(analysis => OwnProblems(analysis, reach, name)));
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

        // The shared BASIC files are included by roots in other projects; lint them in those assemblies.
        if (Path.GetFileName(folder).Equals("Retrocore.Basic", StringComparison.OrdinalIgnoreCase))
        {
            string shared = Path.GetFullPath(Path.Join(folder, "Roms", "Microsoft6502Basic"));
            roots = [.. roots.Select(file => string.Equals(Path.GetDirectoryName(file), shared, StringComparison.OrdinalIgnoreCase)
                ? SourceIncludes.RootOf(file)
                : file).Distinct(StringComparer.OrdinalIgnoreCase)];
        }

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
        return resolver.Lint()
            .Where(problem => Path.GetFullPath(problem.Path) == root || SourceIncludes.RootOf(Path.GetFullPath(problem.Path)) == root)
            .Select(problem => $"{label} {Path.GetRelativePath(folder, problem.Path)}:{problem.Line + 1}: {problem.Text}");
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

    /// <summary>
    ///  The Kaypro II's sources, its ROMs' and MBASIC's modules, pass the lint as the editor runs it.
    /// </summary>
    [TestMethod]
    public void KayproDocumentationIsCleanInTheEditor()
    {
        string folder = Path.Join(s_inputs, "Kaypro");
        List<SourceAnalysis> sdk = [.. SourceIncludes.Roots(folder).Select(file => SourceAnalysis.Assemble(file, _ => null))];
        string[] names = [.. sdk.Select(analysis => Path.GetFileName(analysis.Root))];
        names.Should().Contain(["Kaypro2.asm", "Kaypro2CharacterGenerator.asm", "Mbasic.asm"]);
        List<string> problems = [.. sdk.SelectMany(analysis => Problems(analysis, sdk, "SDK")).Order()];
        problems.Should().BeEmpty($"the editor's lint found:{Environment.NewLine}{string.Join(Environment.NewLine, problems)}");
    }

    private static readonly string[] s_sdkFolders =
        ["AppleSoft", "DiskII", "Dos", "IntegerBasic", "Microsoft6502Basic", "ProgrammersAid", "System"];

    /// <summary>
    ///  The SDK's modules as the editor indexes them: the roots among the IIe's ROM sources. AppleSoft.asm is the
    ///  default module; the overlay is a mutually exclusive MACRO-10 source.
    /// </summary>
    /// <param name="roms">The folder holding the IIe's ROM sources.</param>
    /// <returns>Each module's root.</returns>
    internal static IEnumerable<string> SdkRoots(string roms) =>
        s_sdkFolders
            .SelectMany(folder => SourceIncludes.Roots(Path.Join(roms, folder)))
            .Where(root => !Path.GetFileName(root).Equals("applesoft.mac", StringComparison.OrdinalIgnoreCase))
            .Where(root => !Path.GetFileName(root).StartsWith("MsBasic.", StringComparison.Ordinal))
            .Where(root => !Path.GetFileName(root).Equals("m6502.asm", StringComparison.OrdinalIgnoreCase))
            .Append(Path.GetFullPath(Path.Join(roms, "Slot7.rom.asm")));

    // The lint's findings for one module, its links reaching the SDK's other modules as the editor's do.
    private static IEnumerable<string> Problems(SourceAnalysis analysis, List<SourceAnalysis> sdk, string copy)
    {
        DocumentationResolver resolver = new(
            analysis.Documentation,
            analysis.OtherModules(sdk).Select(other => other.Documentation),
            isDirective: name => DirectiveDocs.Describe(name) is not null,
            isInstruction: InstructionDocs.IsMnemonic);

        return resolver.Lint().Select(problem => $"{copy} {Path.GetFileName(problem.Path)}:{problem.Line + 1}: {problem.Text}");
    }

    /// <summary>
    ///  The Monitor's other builds pass the lint too: the II's, the II Plus's and the original IIe's own routines'
    ///  documentation, and the links in it, with the other modules as the Enhanced IIe's Monitor sees them. The
    ///  Monitor's own problems are Monitor.asm's and its Monitor folder's.
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

        string folder = Path.Join(Path.GetDirectoryName(path), "Monitor") + Path.DirectorySeparatorChar;
        List<string> problems = [.. resolver.Lint()
            .Where(problem => problem.Path == path || problem.Path.StartsWith(folder, StringComparison.Ordinal))
            .Select(problem => $"{Path.GetFileName(problem.Path)}:{problem.Line + 1}: {problem.Text}")];

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
        DocumentationTopic plot = monitor.Find("LowRes::Plot") ?? throw new AssertFailedException("LowRes::Plot is not documented.");
        plot.Summary.Should().StartWith("Plots one lo-res block");
        plot.Value.Should().Be(0xF800);

        Dictionary<ushort, DebugContract> contracts = DebugContracts.Build(
            new DocumentationResolver(monitor, sets),
            "Enhanced",
            new DebugRegisters(M6502Isa.Description));

        contracts[0xF800].Registers.Should().Contain(["X", "Y"]);
    }

    /// <summary>
    ///  A routine that falls into another has its own contract: Screen::FlipCursor overwrites A with its cursor-off
    ///  test and keeps only Y, while Screen::InvertCursor, which it falls into, keeps A and Y.
    /// </summary>
    [TestMethod]
    public void FallThroughRoutineHasItsOwnContract()
    {
        List<DocumentationSet> sets = Sets();
        DocumentationSet firmware = sets.Single(set => set.Find("Screen::FlipCursor") is not null);
        Dictionary<ushort, DebugContract> contracts = DebugContracts.Build(
            new DocumentationResolver(firmware, sets),
            "Enhanced",
            new DebugRegisters(M6502Isa.Description));

        contracts[0xCE1F].Registers.Should().Equal("Y");
        contracts[0xCE26].Registers.Should().BeEquivalentTo(["A", "Y"]);
    }

    /// <summary>
    ///  An <c>Entry:</c> whose meaning ends in a keeps clause has that contract at its address: DFS_OSBPUT keeps A, X
    ///  and Y, but DFS_OSBPUT_CHANNEL, entered after its caller's SAVE_REGISTERS, keeps nothing itself, so a call there
    ///  is not checked; SET_ENTRY_EXEC_ADDRESS_MERGE keeps X and Y, not A; and Fill80::Aux keeps A, not X.
    /// </summary>
    [TestMethod]
    public void EntriesKeepWhatTheirClauseSays()
    {
        AssemblyResult dnfs = BbcSdkModules.AssembleDnfs(Path.Join(s_inputs, "Acorn"));
        SourceMapModule module = new(dnfs, area: null);
        long? Symbol(string name) => module.TryResolve(name, out long value) ? value : null;
        Dictionary<ushort, DebugContract> contracts = DebugContracts.Build(
            new DocumentationResolver(module.Documentation), model: "", new DebugRegisters(M6502Isa.Description), Symbol);

        contracts[(ushort)dnfs.Symbols["DFS_OSBPUT"]].Registers.Should().BeEquivalentTo(["A", "X", "Y"]);
        contracts.Should().NotContainKey((ushort)dnfs.Symbols["DFS_OSBPUT_CHANNEL"]);
        contracts[(ushort)dnfs.Symbols["SET_ENTRY_EXEC_ADDRESS"]].Registers.Should().BeEquivalentTo(["A", "X", "Y"]);
        contracts[(ushort)dnfs.Symbols["SET_ENTRY_EXEC_ADDRESS_MERGE"]].Registers.Should().BeEquivalentTo(["X", "Y"]);

        // An entry with a comment of its own but no Keeps: of its own, as the IIe's Fill80::Aux, has its clause too.
        List<DocumentationSet> sets = Sets();
        DocumentationSet firmware = sets.Single(set => set.Symbols.ContainsKey("Fill80::Aux"));
        Dictionary<ushort, DebugContract> iie = DebugContracts.Build(
            new DocumentationResolver(firmware, sets),
            "Enhanced",
            new DebugRegisters(M6502Isa.Description));

        iie[(ushort)firmware.Symbols["Fill80"]].Registers.Should().BeEquivalentTo(["A", "X"]);
        iie[(ushort)firmware.Symbols["Fill80::Aux"]].Registers.Should().Equal("A");
    }

    /// <summary>
    ///  A note in parentheses after a Uses: item, as in the MOS's <c>Y (for a sound channel)</c>, still names the
    ///  item for the debugger's check.
    /// </summary>
    [TestMethod]
    public void UsesNotesNameTheirItem()
    {
        AssemblyResult mos = BbcSdkModules.AssembleMos(Path.Join(s_inputs, "Acorn"));
        SourceMapModule module = new(mos, area: null);
        long? Symbol(string name) => module.TryResolve(name, out long value) ? value : null;
        Dictionary<ushort, DebugContract> contracts = DebugContracts.Build(
            new DocumentationResolver(module.Documentation), model: "", new DebugRegisters(M6502Isa.Description), Symbol);

        // FLUSH_BUFFER: "Uses: Y (for a sound channel)".
        contracts[(ushort)mos.Symbols["FLUSH_BUFFER"]].Changes.Should().Contain("Y");
    }

    /// <summary>
    ///  Level II's Model III routines keep their contracts in the Model III's build only: CASSETTE_READ and CIO
    ///  have a Model I and a Model III version under one name, and the Model III's Keeps: sections, under
    ///  <c>not MODEL = 1</c>, apply where the build's MODEL makes that hold.
    /// </summary>
    [TestMethod]
    public void Trs80ModelContractsFollowTheBuild()
    {
        string roms = Path.Join(s_inputs, "Trs80");
        DebugRegisters registers = new(Z80Isa.Description);
        Dictionary<ushort, DebugContract> Contracts(AssemblyResult result, string model)
        {
            SourceMapModule module = new(result, area: null);
            long? Symbol(string name) => module.TryResolve(name, out long value) ? value : null;
            return DebugContracts.Build(new DocumentationResolver(module.Documentation), model, registers, Symbol);
        }

        AssemblyResult model1 = Trs80SdkModules.AssembleLevel2(Path.Join(roms, "Level2.asm"), 13);
        AssemblyResult model3 = Trs80SdkModules.AssembleModel3(Path.Join(roms, "Model3.asm"), 3);
        foreach (string routine in (string[])["CASSETTE_READ", "CIO"])
        {
            ushort one = (ushort)model1.Symbols[routine];
            ushort three = (ushort)model3.Symbols[routine];
            Contracts(model1, "Level2").Should().NotContainKey(one, $"the Model I's {routine} promises nothing");
            Contracts(model3, "Model3")[three].Registers.Should().Contain(["DE", "HL"], $"the Model III's {routine} keeps them");
        }
    }

    /// <summary>
    ///  The SDK's modules' documentation, as the editor sees it, for checking a source whose links reach into them.
    /// </summary>
    /// <returns>A set per module.</returns>
    internal static List<DocumentationSet> Sets()
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

        // Slot 7's ROM, without the source generator's .rom declaration; its exports are the C# card's API. It includes
        // the ProDOS block-device names, beside it.
        string slot7 = Path.GetFullPath(Path.Join(s_inputs, "Slot7.rom.asm"));
        string proDos = Path.GetFullPath(Path.Join(s_inputs, "ProDosBlockDevice.asm"));
        string slot7Text = string.Join("\n", File.ReadAllLines(slot7).Where(line => !line.StartsWith(".rom", StringComparison.Ordinal)));
        AssemblyResult card = new Retrocore.Assembler.Assembler().Assemble(
            new AssemblySource(slot7Text, slot7),
            new AssemblyOptions(ProcessorVariant.Mos6502, 0xC700, 0x100)
            {
                SourceResolver = new FileAssemblySourceResolver()
            });

        card.Success.Should().BeTrue();
        sets.Add(DocumentationSet.Create(
            [DocumentationParser.Parse(slot7Text, slot7), DocumentationParser.Parse(File.ReadAllText(proDos), proDos)],
            card,
            "Slot7"));

        string appleSoft = SdkModules.AppleSoftPath(s_inputs);
        AssemblyResult basic = SdkModules.AssembleAppleSoft(appleSoft, Apple2Model.IIeEnhanced);

        // Every AppleSoft and shared BASIC file, those the assembly only expands macros from among them, and every other
        // file it reads, IIeEquates.asm among them.
        IEnumerable<string> appleSoftSources = Directory
            .GetFiles(Path.Join(s_inputs, "AppleSoft"), "AppleSoft*.asm")
            .Concat(Directory.GetFiles(Path.Join(s_inputs, "Microsoft6502Basic"), "MsBasic*.asm"))
            .Concat(basic.SourceMap.Select(entry => entry.Location?.Path).OfType<string>())
            .Concat(basic.SymbolDefinitions.Select(symbol => symbol.Location?.Path).OfType<string>())
            .Where(File.Exists)
            .Select(Path.GetFullPath)
            .Distinct(StringComparer.OrdinalIgnoreCase);

        sets.Add(DocumentationSet.Create(
            [.. appleSoftSources.Select(path => DocumentationParser.Parse(File.ReadAllText(path), path))],
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