// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Security.Cryptography;
using System.Text;
using Retrocore.Assembler;
using Retrocore.Debug;
using Retrocore.Debug.Language;
using Retrocore.Machines.Apple2;
using Retrocore.Machines.Commodore;

namespace Retrocore.Tests;

/// <summary>
///  The shared Microsoft sources work from the repository and from the SDK's shipped layout.
/// </summary>
[TestClass]
public sealed class BasicSharedSourceTests
{
    private static string Inputs => Path.GetFullPath(BasicNames.Inputs);
    private static readonly string s_shipped = ShippedRoms();

    /// <summary>
    ///  The repository, test inputs and shipped SDK retain the pinned, LF-normalized Microsoft source.
    /// </summary>
    [TestMethod]
    public void RepositoryAndSdkKeepThePinnedBase()
    {
        string repository = RepositoryRoot();
        foreach (string folder in (string[])
            [
                RepositoryShared(repository),
                Path.Join(Inputs, "Microsoft6502Basic"),
                Path.Join(s_shipped, "Microsoft6502Basic")
            ])
        {
            string text = File.ReadAllText(Path.Join(folder, "m6502.asm")).Replace("\r\n", "\n", StringComparison.Ordinal);
            Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(text)))
                .Should().Be("F3EC99C91DEDB8EB3441DED866F45797BB3E03ED26567A253E24CECF23CD63AC");
        }
    }

    /// <summary>
    ///  The SDK ships Microsoft's LICENSE beside the shared sources derived from Microsoft's BASIC, each derived
    ///  module says it is derived from Microsoft's source, and the extension's third-party notices name that BASIC,
    ///  where the SDK keeps it and the modules derived from it.
    /// </summary>
    [TestMethod]
    public void SdkShipsMicrosoftsLicenseBesideTheSharedSources()
    {
        string repository = RepositoryRoot();
        string shipped = Path.Join(s_shipped, "Microsoft6502Basic");
        string license = Path.Join(shipped, "LICENSE");
        File.Exists(license).Should().BeTrue($"the SDK must ship Microsoft's LICENSE in {shipped}");
        File.ReadAllText(license).Should().Be(File.ReadAllText(Path.Join(RepositoryShared(repository), "LICENSE")));
        File.ReadAllText(license).Should().Contain("Copyright (c) Microsoft Corporation.");

        string[] sources = [.. Directory.EnumerateFiles(RepositoryShared(repository), "*.asm").Select(path => Path.GetFileName(path))];
        sources.Should().Contain("m6502.asm").And.Contain(name => name.StartsWith("MsBasic.", StringComparison.Ordinal));
        foreach (string source in sources)
        {
            File.Exists(Path.Join(shipped, source)).Should().BeTrue($"{source} must ship beside Microsoft's LICENSE");
        }

        string notices = File.ReadAllText(Path.Join(repository, "extension", "ThirdPartyNotices.txt"));
        notices.Should().Contain("Microsoft BASIC for 6502 Microprocessor")
            .And.Contain("https://github.com/microsoft/BASIC-M6502")
            .And.Contain("server/Sdk/Roms/Microsoft6502Basic/")
            .And.Contain("Copyright (c) Microsoft Corporation, 1976-1978.")
            .And.Contain("The native MsBasic.*.asm modules in src/Retrocore.Basic/Roms/Microsoft6502Basic")
            .And.Contain("server/Sdk/Roms/Microsoft6502Basic, are derived from Microsoft's m6502.asm, and the license below")
            .And.Contain("Microsoft code in them;")
            .And.Contain("Apple and Commodore code some of them carry is not Microsoft's.");

        // Each module derived from Microsoft's source says so in its first lines, after any pragmas.
        foreach (string module in Directory.EnumerateFiles(RepositoryShared(repository), "MsBasic.*.asm")
            .Concat(Directory.EnumerateFiles(shipped, "MsBasic.*.asm")))
        {
            File.ReadLines(module).SkipWhile(line => line.StartsWith("; retrocore:", StringComparison.Ordinal)).First()
                .Should().Be(DerivationLine, $"{Path.GetFileName(module)} must say it is derived from Microsoft's source");
        }
    }

    // The line each module derived from Microsoft's m6502.asm starts with.
    private const string DerivationLine =
        "; Derived from Microsoft's BASIC for 6502 (m6502.asm, MIT license; see LICENSE in this folder).";

    /// <summary>
    ///  Both AppleSoft selections assemble identically in either layout and map to that layout's shared files.
    /// </summary>
    /// <param name="model">The Apple II model.</param>
    [TestMethod]
    [DataRow(Apple2Model.IIPlus)]
    [DataRow(Apple2Model.IIe)]
    [DataRow(Apple2Model.IIeEnhanced)]
    public void RepositoryAndSdkAppleSoftBuildsMatch(Apple2Model model)
    {
        string repository = RepositoryRoot();
        string roms = Path.Join(repository, "src", "Retrocore.Machines.Apple2", "Roms");
        string shared = RepositoryShared(repository);
        foreach (BasicSourceKind kind in (BasicSourceKind[])[BasicSourceKind.Native, BasicSourceKind.Macro10])
        {
            AssemblyResult repo = SdkModules.AssembleAppleSoft(SdkModules.AppleSoftPath(roms, kind), model);
            AssemblyResult sdk = SdkModules.AssembleAppleSoft(SdkModules.AppleSoftPath(s_shipped, kind), model);
            SdkModules.AppleSoftImage(repo).ToArray().Should().Equal(SdkModules.AppleSoftImage(sdk).ToArray());

            string mapped = kind == BasicSourceKind.Native ? "MsBasic.AdditionCore.asm" : "m6502.asm";
            MapsTo(repo, Path.Join(shared, mapped));
            MapsTo(sdk, Path.Join(s_shipped, "Microsoft6502Basic", mapped));
        }
    }

    /// <summary>
    ///  The command's resolver assembles the repository root directly, and a plain file resolver can use its
    ///  include path without depending on the installed SDK.
    /// </summary>
    [TestMethod]
    public void RepositoryNativeRootAssemblesDirectly()
    {
        string repository = RepositoryRoot();
        string apple = Path.Join(repository, "src", "Retrocore.Machines.Apple2", "Roms", "AppleSoft");
        string root = Path.Join(apple, "AppleSoft.asm");
        string shared = RepositoryShared(repository);
        AssemblyResult host = SourceBuild.Assemble(root, dialect: null, cpu: "Mos6502", origin: 0, linkerConfiguration: null);
        AssemblyResult direct = Assemble(root, new FileAssemblySourceResolver(), [shared]);
        AssemblyResult overlay = Assemble(Path.Join(apple, "applesoft.mac"), new FileAssemblySourceResolver());

        SdkModules.AppleSoftImage(direct).ToArray().Should().Equal(SdkModules.AppleSoftImage(host).ToArray());
        SdkModules.AppleSoftImage(direct).ToArray().Should().Equal(SdkModules.AppleSoftImage(overlay).ToArray());
        MapsTo(host, Path.Join(shared, "MsBasic.AdditionCore.asm"));
        MapsTo(direct, Path.Join(shared, "MsBasic.AdditionCore.asm"));
        MapsTo(overlay, Path.Join(shared, "m6502.asm"));
    }

    /// <summary>
    ///  The actual shipped native listing assembles with the plain file resolver and no search paths.
    /// </summary>
    [TestMethod]
    public void ShippedNativeRootIsStandalone()
    {
        string root = Path.Join(s_shipped, "AppleSoft", "AppleSoft.asm");
        AssemblyResult direct = Assemble(root, new FileAssemblySourceResolver());
        AssemblyResult sdk = SdkModules.AssembleAppleSoft(root, Apple2Model.IIeEnhanced);
        SdkModules.AppleSoftImage(direct).ToArray().Should().Equal(SdkModules.AppleSoftImage(sdk).ToArray());
        MapsTo(direct, Path.Join(s_shipped, "Microsoft6502Basic", "MsBasic.AdditionCore.asm"));
    }

    /// <summary>
    ///  The Commodore platform definitions resolve their shared table macro from both source layouts.
    /// </summary>
    [TestMethod]
    public void CommodorePlatformResolvesTheSharedTable()
    {
        string repository = RepositoryRoot();
        string platform = Path.Join(repository, "src", "Retrocore.Machines.Commodore", "Roms", "Basic", "Commodore.Platform.asm");
        AssemblyResult repo = SourceBuild.Assemble(platform, dialect: null, cpu: "Mos6502", origin: 0, linkerConfiguration: null);
        AssemblyResult sdk = Assemble(Path.Join(s_shipped, "Pet", "Basic", "Commodore.Platform.asm"), new FileAssemblySourceResolver());

        repo.Success.Should().BeTrue(string.Join(Environment.NewLine, repo.Diagnostics.Select(diagnostic => diagnostic.Message)));
        sdk.Success.Should().BeTrue(string.Join(Environment.NewLine, sdk.Diagnostics.Select(diagnostic => diagnostic.Message)));

        foreach ((string root, string shared) in ((string, string)[])
            [
                (platform, RepositoryShared(repository)),
                (Path.Join(s_shipped, "Pet", "Basic", "Commodore.Platform.asm"), Path.Join(s_shipped, "Microsoft6502Basic"))
            ])
        {
            string directory = Path.GetDirectoryName(root)
                ?? throw new AssertFailedException($"No directory for {root}.");

            string table = Path.Join(directory, "Commodore.DispatchTables.asm");
            string operators = Path.Join(shared, "MsBasic.OperatorTable.asm");
            SourceIncludes.IncludesOf(table).Should().Contain(operators);
            SourceAnalysis analysis = SourceAnalysis.Assemble(root, _ => null);
            analysis.Result.Success.Should().BeTrue();
            analysis.Members.Should().Contain(operators);
        }
    }

    /// <summary>
    ///  Every native PET root resolves its shared modules in both layouts, including the shipped files without a
    ///  custom resolver, and gives the same BASIC and editor chips.
    /// </summary>
    /// <param name="model">The PET model.</param>
    /// <param name="original">Whether BASIC 1 or 4 uses its original first chip.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, false)]
    [DataRow(PetModel.Pet2001, true)]
    [DataRow(PetModel.Pet2001Basic2, false)]
    [DataRow(PetModel.Pet4032, false)]
    [DataRow(PetModel.Pet4032, true)]
    public void RepositoryAndSdkNativePetBuildsMatch(PetModel model, bool original)
    {
        string repository = RepositoryRoot();
        string repoPet = Path.Join(repository, "src", "Retrocore.Machines.Commodore", "Roms");
        string sdkPet = Path.Join(s_shipped, "Pet");
        string sdkRoot = Path.Join(sdkPet, "Basic", PetSdkModules.BasicFile(model, BasicSourceKind.Native));
        Dictionary<string, long> symbols = [];
        if (PetSdkModules.Version(model) != 2) { symbols["REVISD"] = original ? 0 : 1; }

        AssemblyResult repo = PetSdkModules.AssembleBasic(repoPet, model, original);
        AssemblyResult sdk = PetSdkModules.AssembleBasic(sdkPet, model, original);
        AssemblyResult direct = Assemble(sdkRoot, new FileAssemblySourceResolver(), symbols: symbols);
        AssemblyResult editor = PetSdkModules.AssembleEditor(repoPet, model);
        PetSdkModules.BasicImage(repo, model).ToArray().Should().Equal(PetSdkModules.BasicImage(sdk, model).ToArray());
        PetSdkModules.BasicImage(repo, model).ToArray().Should().Equal(PetSdkModules.BasicImage(direct, model).ToArray());
        PetSdkModules.EditorImage(repo, editor, model).Should().Equal(PetSdkModules.EditorImage(sdk, editor, model));
        PetSdkModules.EditorImage(repo, editor, model).Should().Equal(PetSdkModules.EditorImage(direct, editor, model));
        MapsTo(repo, Path.Join(RepositoryShared(repository), "MsBasic.AdditionCore.asm"));
        MapsTo(direct, Path.Join(s_shipped, "Microsoft6502Basic", "MsBasic.AdditionCore.asm"));
    }

    /// <summary>
    ///  Each PET overlay resolves its real repository path with a plain resolver and matches the shipped build,
    ///  including BASIC's bytes in the editor ROM.
    /// </summary>
    /// <param name="model">The PET model.</param>
    /// <param name="original">Whether BASIC 1 or 4 uses its original chip.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, false)]
    [DataRow(PetModel.Pet2001, true)]
    [DataRow(PetModel.Pet2001Basic2, false)]
    [DataRow(PetModel.Pet4032, false)]
    [DataRow(PetModel.Pet4032, true)]
    public void RepositoryAndSdkPetOverlaysMatch(PetModel model, bool original)
    {
        string repository = RepositoryRoot();
        string pet = Path.Join(repository, "src", "Retrocore.Machines.Commodore", "Roms");
        string overlay = Path.Join(pet, "Basic", PetSdkModules.BasicFile(model, BasicSourceKind.Macro10));
        Dictionary<string, long> symbols = [];
        if (PetSdkModules.Version(model) != 2) { symbols["REVISD"] = original ? 0 : 1; }

        AssemblyResult direct = Assemble(overlay, new FileAssemblySourceResolver(), symbols: symbols);
        AssemblyResult repo = PetLegacyBasic.Assemble(pet, model, original);
        AssemblyResult sdk = PetLegacyBasic.Assemble(Path.Join(s_shipped, "Pet"), model, original);
        direct.Sections[0].Bytes.ToArray().Should().Equal(repo.Sections[0].Bytes.ToArray());
        repo.Sections[0].Bytes.ToArray().Should().Equal(sdk.Sections[0].Bytes.ToArray());
        MapsTo(direct, Path.Join(RepositoryShared(repository), "m6502.asm"));
        MapsTo(sdk, Path.Join(s_shipped, "Microsoft6502Basic", "m6502.asm"));
    }

    /// <summary>
    ///  The command assembles shipped overlays against their neighboring SDK base, not another host installation.
    /// </summary>
    [TestMethod]
    public void ShippedOverlaysUseTheirOwnBase()
    {
        string basePath = Path.Join(s_shipped, "Microsoft6502Basic", "m6502.asm");
        foreach (string overlay in (string[])
            [
                Path.Join(s_shipped, "AppleSoft", "applesoft.mac"),
                Path.Join(s_shipped, "Pet", "Basic", "Basic2.mac")
            ])
        {
            AssemblyResult result = SourceBuild.Assemble(overlay, dialect: null, cpu: "Mos6502", origin: 0, linkerConfiguration: null);
            MapsTo(result, basePath);
        }
    }

    /// <summary>
    ///  The fallback is limited to explicit shared-module requests and does not resolve unrelated missing files.
    /// </summary>
    [TestMethod]
    public void RepositoryModuleFallbackIsScoped()
    {
        string repository = RepositoryRoot();
        string from = Path.Join(repository, "src", "Retrocore.Machines.Apple2", "Roms", "AppleSoft", "AppleSoft.asm");
        OverlayBaseResolver resolver = new(Path.Join(Inputs, "Microsoft6502Basic"));
        resolver.TryResolve(from, "../Microsoft6502Basic/MsBasic.FloatConstants.asm", out AssemblySource? source)
            .Should().BeTrue();

        source?.Path.Should().Be(Path.Join(RepositoryShared(repository), "MsBasic.FloatConstants.asm"));
        resolver.TryResolve(from, "../Microsoft6502Basic/Equates.asm", out _).Should().BeFalse();
        resolver.TryResolve(from, "../Microsoft6502Basic/MsBasic.Missing.asm", out _).Should().BeFalse();
        resolver.TryResolve(from, "../../Microsoft6502Basic/MsBasic.FloatConstants.asm", out _).Should().BeFalse();

        string pet = Path.Join(repository, "src", "Retrocore.Machines.Commodore", "Roms", "Basic", "Commodore.DispatchTables.asm");
        resolver.TryResolve(pet, "../../Microsoft6502Basic/MsBasic.OperatorTable.asm", out source).Should().BeTrue();
        source?.Path.Should().Be(Path.Join(RepositoryShared(repository), "MsBasic.OperatorTable.asm"));
    }

    /// <summary>
    ///  A repository-relative include in a nested AppleSoft module resolves to the shipped SDK's own shared file,
    ///  including its unsaved editor text.
    /// </summary>
    [TestMethod]
    public void RepositoryRelativeModuleFindsTheNeighboringSdkCopy()
    {
        string from = Path.Join(s_shipped, "AppleSoft", "AppleSoft.Initialization.asm");
        string path = Path.Join(s_shipped, "Microsoft6502Basic", "MsBasic.FloatConstants.asm");
        const string request = "../../../Retrocore.Basic/Roms/Microsoft6502Basic/MsBasic.FloatConstants.asm";
        OverlayBaseResolver files = new(Path.Join(s_shipped, "not-the-sdk"));
        files.TryResolve(from, request, out AssemblySource? source).Should().BeTrue();
        source?.Path.Should().Be(path);

        WorkspaceSourceResolver editor = new(
            candidate => string.Equals(candidate, path, StringComparison.OrdinalIgnoreCase) ? "; unsaved\n" : null,
            new SourceFileCache());

        editor.TryResolve(from, request, out AssemblySource? open).Should().BeTrue();
        open?.Path.Should().Be(path);
        open?.Text.Should().Be("; unsaved\n");
        editor.Resolved.Should().Contain(path);
    }

    /// <summary>
    ///  Opening a shared source first finds the same AppleSoft root in the repository and the shipped layout.
    /// </summary>
    /// <param name="file">The shared file.</param>
    /// <param name="root">The including AppleSoft root.</param>
    [TestMethod]
    [DataRow("m6502.asm", "applesoft.mac")]
    [DataRow("MsBasic.FloatArithmetic.asm", "AppleSoft.asm")]
    [DataRow("MsBasic.FloatConstants.asm", "AppleSoft.asm")]
    [DataRow("MsBasic.AdditionCore.asm", "AppleSoft.asm")]
    [DataRow("MsBasic.ArrayMultiplication.asm", "AppleSoft.asm")]
    [DataRow("MsBasic.Arrays.asm", "AppleSoft.asm")]
    [DataRow("MsBasic.CharacterReader.asm", "AppleSoft.asm")]
    [DataRow("MsBasic.OperatorTable.asm", "AppleSoft.asm")]
    [DataRow("MsBasic.Next.asm", "AppleSoft.asm")]
    [DataRow("MsBasic.ExpressionCore.asm", "AppleSoft.asm")]
    [DataRow("MsBasic.OperandEvaluation.asm", "AppleSoft.asm")]
    [DataRow("MsBasic.VariableLookup.asm", "AppleSoft.asm")]
    [DataRow("MsBasic.Dim.asm", "AppleSoft.asm")]
    [DataRow("MsBasic.Lister.asm", "AppleSoft.asm")]
    [DataRow("MsBasic.Print.asm", "AppleSoft.asm")]
    [DataRow("MsBasic.StringOutput.asm", "AppleSoft.asm")]
    [DataRow("MsBasic.StringStorage.asm", "AppleSoft.asm")]
    [DataRow("MsBasic.StringStorage.Classic.asm", "AppleSoft.asm")]
    [DataRow("MsBasic.StringStorage.Linked.asm", "AppleSoft.asm")]
    [DataRow("MsBasic.StringConcatenation.asm", "AppleSoft.asm")]
    [DataRow("MsBasic.IntegerConversion.asm", "AppleSoft.asm")]
    [DataRow("MsBasic.MemoryAccess.asm", "AppleSoft.asm")]
    [DataRow("MsBasic.MemoryManagement.asm", "AppleSoft.asm")]
    [DataRow("MsBasic.ProgramTransfers.asm", "AppleSoft.asm")]
    [DataRow("MsBasic.ProgramReset.asm", "AppleSoft.asm")]
    [DataRow("MsBasic.Relational.asm", "AppleSoft.asm")]
    [DataRow("MsBasic.StatementFlow.asm", "AppleSoft.asm")]
    [DataRow("MsBasic.StringFunctions.asm", "AppleSoft.asm")]
    public void SharedFilesFindTheirRoots(string file, string root)
    {
        string repository = RepositoryRoot();
        foreach ((string shared, string apple) in ((string, string)[])
            [
                (RepositoryShared(repository), Path.Join(repository, "src", "Retrocore.Machines.Apple2", "Roms", "AppleSoft")),
                (Path.Join(Inputs, "Microsoft6502Basic"), Path.Join(Inputs, "AppleSoft")),
                (Path.Join(s_shipped, "Microsoft6502Basic"), Path.Join(s_shipped, "AppleSoft"))
            ])
        {
            SourceIncludes.RootOf(Path.Join(shared, file)).Should().Be(Path.GetFullPath(Path.Join(apple, root)));
        }
    }

    /// <summary>
    ///  SDK indexing does not mistake the shared source or the overlay's base for independent roots.
    /// </summary>
    [TestMethod]
    public void SdkRootDiscoveryFindsTheShippedIncludes()
    {
        foreach (string roms in (string[])[Inputs, s_shipped])
        {
            List<string> roots = SourceIncludes.Roots(roms);
            roots.Should().Contain(Path.Join(roms, "AppleSoft", "AppleSoft.asm"));
            roots.Should().Contain(Path.Join(roms, "Pet", "Basic", "Basic1.asm"));
            roots.Should().Contain(Path.Join(roms, "Pet", "Basic", "Basic2.asm"));
            roots.Should().Contain(Path.Join(roms, "Pet", "Basic", "Basic4.asm"));
            roots.Should().NotContain(Path.Join(roms, "Microsoft6502Basic", "MsBasic.FloatConstants.asm"));
            roots.Should().NotContain(Path.Join(roms, "Microsoft6502Basic", "MsBasic.CharacterReader.asm"));
            roots.Should().NotContain(Path.Join(roms, "Microsoft6502Basic", "m6502.asm"));
        }
    }

    /// <summary>
    ///  An unsaved edit of the pinned base reaches the overlay and triggers its hash check in either layout.
    /// </summary>
    /// <param name="repository">Whether to open the repository copy rather than the SDK-layout copy.</param>
    [TestMethod]
    [DataRow(data: true)]
    [DataRow(data: false)]
    public void EditedBaseIsStillPinned(bool repository)
    {
        string root = RepositoryRoot();
        string shared = repository ? RepositoryShared(root) : Path.Join(s_shipped, "Microsoft6502Basic");
        string apple = repository
            ? Path.Join(root, "src", "Retrocore.Machines.Apple2", "Roms", "AppleSoft")
            : Path.Join(s_shipped, "AppleSoft");

        string path = Path.Join(shared, "m6502.asm");
        string edited = File.ReadAllText(path) + "\n; unsaved edit\n";
        SourceAnalysis analysis = SourceAnalysis.Assemble(
            Path.Join(apple, "applesoft.mac"),
            candidate => string.Equals(candidate, path, StringComparison.OrdinalIgnoreCase) ? edited : null);

        analysis.Members.Should().Contain(path);
        analysis.Result.Success.Should().BeFalse();
        analysis.Result.Diagnostics.Should().Contain(diagnostic => diagnostic.Message.Contains("SHA-256", StringComparison.Ordinal));
    }

    /// <summary>
    ///  An unsaved edit to a shared module, opened before its root, reassembles that root; a subsequent edit and
    ///  close are reflected too, without editing the files on disk.
    /// </summary>
    /// <param name="repository">Whether to open the repository copy rather than the SDK-layout copy.</param>
    /// <returns>A task that completes when the analysis reflects all edits.</returns>
    [TestMethod]
    [DataRow(data: true)]
    [DataRow(data: false)]
    public async Task EditingASharedFileReanalyzesItsRoot(bool repository)
    {
        string root = RepositoryRoot();
        string shared = repository ? RepositoryShared(root) : Path.Join(s_shipped, "Microsoft6502Basic");
        string apple = repository
            ? Path.Join(root, "src", "Retrocore.Machines.Apple2", "Roms", "AppleSoft")
            : Path.Join(s_shipped, "AppleSoft");

        string path = Path.Join(shared, "MsBasic.FloatConstants.asm");
        string disk = File.ReadAllText(path);
        const string original = ".byte $81, $00, $00, $00, $00";
        string first = disk.Replace(original, ".byte $82, $00, $00, $00, $00", StringComparison.Ordinal);
        string second = disk.Replace(original, ".byte $83, $00, $00, $00, $00", StringComparison.Ordinal);
        first.Should().NotBe(disk);

        LanguageWorkspace workspace = new(new SilentClient());
        workspace.Update(path, first);
        SourceAnalysis initial = await workspace.AnalysisOfAsync(path, CancellationToken.None)
            ?? throw new AssertFailedException("The shared file was not analyzed.");

        initial.Root.Should().Be(Path.Join(apple, "AppleSoft.asm"));
        initial.Result.Success.Should().BeTrue(string.Join('\n', initial.Result.Diagnostics.Select(item => item.Message)));
        initial.Members.Should().Contain(path);
        initial.Find("FONE").Should().ContainSingle().Which.Path.Should().Be(path);
        OneByte(initial).Should().Be(0x82);

        workspace.Update(path, second);
        await ByteOnceIdle(workspace, path, 0x83);
        workspace.Close(path);
        await ByteOnceIdle(workspace, path, 0x81);
        File.ReadAllText(path).Should().Be(disk);
    }

    // Waits for every edit so far to be analyzed, however long that takes under load, then checks the result.
    private static async Task ByteOnceIdle(LanguageWorkspace workspace, string path, byte expected)
    {
        await workspace.IdleAsync(path, CancellationToken.None);
        SourceAnalysis analysis = workspace.AnalysisOf(path) ?? throw new AssertFailedException("The shared file was not analyzed.");
        analysis.Result.Success.Should().BeTrue(string.Join('\n', analysis.Result.Diagnostics.Select(item => item.Message)));
        OneByte(analysis).Should().Be(expected);
    }

    private static byte OneByte(SourceAnalysis analysis) =>
        analysis.Result.Sections[0].Bytes.Span[checked((int)analysis.Result.Symbol("FONE"))];

    private static AssemblyResult Assemble(
        string path,
        IAssemblySourceResolver resolver,
        IReadOnlyList<string>? includePaths = null,
        IReadOnlyDictionary<string, long>? symbols = null)
    {
        AssemblyOptions options = new(ProcessorVariant.Mos6502, 0, 0x10000)
        {
            SourceResolver = resolver,
            IncludePaths = includePaths ?? [],
            PredefinedSymbols = BasicNames.WithCurrentNames(symbols ?? new Dictionary<string, long>())
        };

        AssemblyResult result = new Assembler.Assembler().Assemble(new AssemblySource(File.ReadAllText(path), path), options);
        result.Success.Should().BeTrue(string.Join('\n', result.Diagnostics.Select(item => item.Message)));
        return result;
    }

    private static void MapsTo(AssemblyResult result, string path) =>
        result.SourceMap.Any(entry => string.Equals(entry.Location?.Path, path, StringComparison.OrdinalIgnoreCase))
            .Should().BeTrue($"the source map must name {path}");

    private static string RepositoryShared(string root) =>
        Path.Join(root, "src", "Retrocore.Basic", "Roms", "Microsoft6502Basic");

    private static string ShippedRoms()
    {
        DirectoryInfo? project = new(AppContext.BaseDirectory);
        while (project is not null && !project.Name.Equals("Retrocore.Tests", StringComparison.OrdinalIgnoreCase))
        {
            project = project.Parent;
        }

        if (project?.Parent is not { } configuration)
        {
            throw new InvalidOperationException("The test project's output directory was not found.");
        }

        string target = Path.GetRelativePath(project.FullName, AppContext.BaseDirectory);
        return Path.GetFullPath(Path.Join(configuration.FullName, "Retrocore.Debug", target, "Sdk", "Roms"));
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
}

/// <summary>
///  Discards published diagnostics while tests inspect the analysis.
/// </summary>
file sealed class SilentClient : ILanguageClient
{
    /// <inheritdoc/>
    public void PublishDiagnostics(DocumentUri uri, IEnumerable<Diagnostic> diagnostics) { }
}
