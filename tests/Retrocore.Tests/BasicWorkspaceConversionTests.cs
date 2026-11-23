// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Debug;
using Retrocore.Documentation;
using Retrocore.Machines.Apple2;
using Retrocore.Machines.Commodore;

namespace Retrocore.Tests;

/// <summary>
///  Checks the BASIC workspace as converted to the style guide: both vendors' equates and dispatch tables and the
///  shared layouts keep every old name they renamed, each reaching the value Microsoft's MACRO-10 build gives it, and
///  each cited by documents in the bibliography.
/// </summary>
[TestClass]
public sealed class BasicWorkspaceConversionTests
{
    // The sources the workspace step converted, by folder under the inputs.
    private static readonly string[] s_appleFiles = ["AppleSoft.Equates.asm", "AppleSoft.DispatchTables.asm"];
    private static readonly string[] s_commodoreFiles = ["Commodore.Equates.asm", "Commodore.DispatchTables.asm"];
    private const string LayoutsFile = "MsBasic.Layouts.asm";

    private static string AppleFolder => Path.Join(BasicNames.Inputs, "AppleSoft");
    private static string PetFolder => Path.Join(BasicNames.Inputs, "Pet");
    private static string CommodoreFolder => Path.Join(PetFolder, "Basic");
    private static string SharedFolder => Path.Join(BasicNames.Inputs, "Microsoft6502Basic");
    private static string Layouts => Path.Join(SharedFolder, LayoutsFile);

    // The documents that give each vendor's names: a vendor's file cites only these, Microsoft's source and UNKN.
    private static readonly string[] s_appleKeys = ["M6502", "UNKN", "ASTIL", "AS82", "ASRM78"];
    private static readonly string[] s_commodoreKeys =
        ["M6502", "UNKN", "CBM4S79", "K4S79", "HV1", "HV1R", "HV2", "HV4", "HV4R", "HVK4"];

    // The SDK's own names, which no document and no overlay gives: the switches, the stack page and the layouts.
    private static readonly HashSet<string> s_sdkNames =
    [
        "Stack", "Variable", "ArrayHeader", "StringDescriptor", "ForFrame", "GosubFrame", "OperatorEntry",
        "ProgramLine", "FunctionDefinition", "TERMINAL_FIRST", "FULL_STACK_TOP", "STACK_RESERVE_19", "LOCAL_TERMINAL_POSITION", "LINE_WIDTH_STORAGE",
        "DISK_STATUS_STRING", "VARIABLE_LIST_IN_LINE_NUMBER", "CLOCK_IN_PAGE2", "STATUS_IN_PAGE2", "RND_TIMER_9044",
        "ERROR_PADDING5", "EXTENDED_DISK_VECTORS", "FLOAT_SIZE", "DEFAULT_BOUND"
    ];

    private static readonly Apple2Model[] s_appleModels =
        [Apple2Model.IIPlus, Apple2Model.IIe, Apple2Model.IIeEnhanced];
    private static readonly (PetModel Model, bool Original)[] s_pets =
    [
        (PetModel.Pet2001, false), (PetModel.Pet2001, true), (PetModel.Pet2001Basic2, false),
        (PetModel.Pet4032, false), (PetModel.Pet4032, true)
    ];

    /// <summary>
    ///  In each AppleSoft build, every old name the converted files give reaches the value the MACRO-10 overlay gives
    ///  that name.
    /// </summary>
    /// <param name="model">The Apple II model.</param>
    [TestMethod]
    [DataRow(Apple2Model.IIPlus)]
    [DataRow(Apple2Model.IIe)]
    [DataRow(Apple2Model.IIeEnhanced)]
    public void AppleSoftOldNamesMatchTheOverlay(Apple2Model model)
    {
        AssemblyResult native = AssembleAppleSoft(model);
        AssemblyResult legacy = SdkModules.AssembleAppleSoft(Path.Join(AppleFolder, "applesoft.mac"), model);
        CheckAgainstOverlay(native, legacy, [.. Converted(AppleFolder, s_appleFiles), Layouts], minimum: 200, s_sdkNames);
    }

    /// <summary>
    ///  In each PET build, every old name the converted files give reaches the value the MACRO-10 overlay gives that
    ///  name.
    /// </summary>
    /// <param name="model">The PET model.</param>
    /// <param name="original">Whether BASIC 1 or 4 uses its original chip.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, false)]
    [DataRow(PetModel.Pet2001, true)]
    [DataRow(PetModel.Pet2001Basic2, false)]
    [DataRow(PetModel.Pet4032, false)]
    [DataRow(PetModel.Pet4032, true)]
    public void PetOldNamesMatchTheOverlay(PetModel model, bool original)
    {
        AssemblyResult native = PetSdkModules.AssembleBasic(PetFolder, model, original);
        AssemblyResult legacy = PetLegacyBasic.Assemble(PetFolder, model, original);
        CheckAgainstOverlay(native, legacy, [.. Converted(CommodoreFolder, s_commodoreFiles), Layouts], minimum: 150, s_sdkNames);
    }

    /// <summary>
    ///  An old name only one vendor's converted files give resolves in none of the other vendor's builds, and the
    ///  shared layouts give only Microsoft's names, citing with M6502 the PET documents of their lineage.
    /// </summary>
    [TestMethod]
    public void VendorOldNamesResolveOnlyInTheirVendorsBuilds()
    {
        AssemblyResult[] apple = [.. s_appleModels.Select(AssembleAppleSoft)];
        AssemblyResult[] pet =
            [.. s_pets.Select(build => PetSdkModules.AssembleBasic(PetFolder, build.Model, build.Original))];

        HashSet<string> appleNames = OldNames(apple, Converted(AppleFolder, s_appleFiles));
        HashSet<string> petNames = OldNames(pet, Converted(CommodoreFolder, s_commodoreFiles));
        appleNames.Should().Contain(["TXTTAB", "CHRGET", "ERRSN", "ENDTK", "TEXTAB"]);
        petNames.Should().Contain(["TXTTAB", "CHRGET", "ERRSN", "ENDTK", "COPEN", "CQOPEN"]);

        foreach (string name in appleNames.Except(petNames))
        {
            foreach (AssemblyResult build in pet)
            {
                build.HistoricalNames.Should().NotContainKey(name, $"{name} is AppleSoft's name, not the PET's");
            }
        }

        foreach (string name in petNames.Except(appleNames))
        {
            foreach (AssemblyResult build in apple)
            {
                build.HistoricalNames.Should().NotContainKey(name, $"{name} is the PET's name, not AppleSoft's");
            }
        }

        // The layouts are shared, so each old name there must be Microsoft's, which every build has. Under the lineage
        // rule it also cites every PET document whose listing names it; no AppleSoft document is checked here (S11).
        DocumentationFile layouts = Parse(Path.Join(SharedFolder, LayoutsFile));
        DocumentationAlso[] shared = [.. OldNamesIn(layouts)];
        shared.Select(also => also.Name).Should().BeEquivalentTo(["STRSIZ", "FORSIZ"]);
        string[] lineage = ["M6502", "CBM4S79", "HV1", "HV1R", "HV2", "HV4", "HV4R"];
        foreach (DocumentationAlso also in shared)
        {
            also.Sources.Should().Equal(lineage, $"{also.Name} is Microsoft's name, which every PET listing also gives");
            foreach (AssemblyResult build in apple.Concat(pet))
            {
                build.Symbol(also.Name).Should().Be(build.Symbol(build.DefinitionName(also.Name)));
            }
        }
    }

    /// <summary>
    ///  Every old name in the converted files cites at least one document, every document is in the bibliography,
    ///  and a vendor's file cites only that vendor's documents and Microsoft's.
    /// </summary>
    [TestMethod]
    public void OldNamesCiteDocumentsInTheBibliography()
    {
        string[] files =
        [
            .. Converted(AppleFolder, s_appleFiles), .. Converted(CommodoreFolder, s_commodoreFiles),
            Path.Join(SharedFolder, LayoutsFile)
        ];

        int count = 0;
        foreach (string path in files)
        {
            // A vendor's file cites its vendor's documents; the shared layouts, Microsoft's (checked above).
            string name = Path.GetFileName(path);
            string[]? vendor = null;
            if (s_appleFiles.Contains(name)) { vendor = s_appleKeys; }
            if (s_commodoreFiles.Contains(name)) { vendor = s_commodoreKeys; }

            foreach (DocumentationAlso also in OldNamesIn(Parse(path)))
            {
                count++;
                if (vendor is not null)
                {
                    also.Sources.Should().BeSubsetOf(vendor, $"{also.Name} in {name} is its vendor's name");
                }

                also.Sources.Should().NotBeEmpty($"{also.Name} in {Path.GetFileName(path)} must cite its documents");
                foreach (string key in also.Sources)
                {
                    BasicAttribution.Bibliography.Find(key).Should().NotBeNull(
                        $"{also.Name} in {Path.GetFileName(path)} cites {key}, which must be in docs/Bibliography.md");
                }
            }
        }

        count.Should().BeGreaterThan(400, "the converted workspace keeps every old name it renamed");
    }

    /// <summary>
    ///  Checks that each old name a converted file gives reaches its definition with the overlay's value for that
    ///  name, and that each definition the files make reaches the overlay by its name or an old name.
    /// </summary>
    /// <param name="native">The native build.</param>
    /// <param name="legacy">The MACRO-10 overlay's build of the same model.</param>
    /// <param name="files">The converted files.</param>
    /// <param name="minimum">The fewest old names that must be compared.</param>
    /// <param name="sdkNames">The SDK's own definitions, which no overlay gives.</param>
    /// <param name="scoped">
    ///  Whether a scoped definition is checked too; the workspace's are a type's members, which come with their type.
    /// </param>
    internal static void CheckAgainstOverlay(
        AssemblyResult native,
        AssemblyResult legacy,
        string[] files,
        int minimum,
        IReadOnlySet<string> sdkNames,
        bool scoped = false)
    {
        native.Success.Should().BeTrue();
        legacy.Success.Should().BeTrue();
        int compared = 0;
        foreach ((string name, AssemblySymbol definition) in
            native.HistoricalNames.OrderBy(pair => pair.Key, StringComparer.Ordinal))
        {
            if (!InFiles(definition, files)) { continue; }
            native.SymbolDefinitions.Any(symbol => symbol.Name == name)
                .Should().BeFalse($"{name} must be an old name, not a definition's name");

            if (!legacy.TryGetSymbol(name, out long expected)) { continue; }
            native.Symbol(name).Should().Be(expected, $"{name} ({definition.Name}) must keep the overlay's value");
            compared++;
        }

        compared.Should().BeGreaterThan(minimum, "the converted files rename the overlay's names");

        // Every definition the converted files make reaches the overlay by its name or an old name, so an old name
        // dropped from an Also: section, which code may not use, still fails.
        IEnumerable<AssemblySymbol> definitions = native.SymbolDefinitions.Where(symbol =>
            InFiles(symbol, files)
                && (scoped || !symbol.Name.Contains("::", StringComparison.Ordinal))
                && !sdkNames.Contains(symbol.Name));

        foreach (AssemblySymbol definition in definitions)
        {
            legacy.TryGetCounterpart(native, definition.Name, out long expected).Should().BeTrue(
                $"{definition.Name} must keep the name the overlay gives it, as its own or in its Also: section");

            definition.Value.Should().Be(expected, $"{definition.Name} must keep the overlay's value");
        }
    }

    /// <summary>
    ///  Gets the old names the given files give in any of the builds.
    /// </summary>
    /// <param name="builds">The builds.</param>
    /// <param name="files">The files.</param>
    /// <returns>The old names.</returns>
    internal static HashSet<string> OldNames(IEnumerable<AssemblyResult> builds, string[] files) =>
        [.. builds.SelectMany(build => build.HistoricalNames)
            .Where(pair => InFiles(pair.Value, files))
            .Select(pair => pair.Key)];

    /// <summary>
    ///  Gets whether a definition is in one of the files.
    /// </summary>
    /// <param name="definition">The definition.</param>
    /// <param name="files">The files.</param>
    /// <returns>Whether it is.</returns>
    internal static bool InFiles(AssemblySymbol definition, string[] files) =>
        definition.Location is { } location
            && files.Any(file => string.Equals(
                Path.GetFullPath(location.Path), Path.GetFullPath(file), StringComparison.OrdinalIgnoreCase));

    private static AssemblyResult AssembleAppleSoft(Apple2Model model) =>
        SdkModules.AssembleAppleSoft(SdkModules.AppleSoftPath(BasicNames.Inputs), model);

    private static IEnumerable<DocumentationAlso> OldNamesIn(DocumentationFile file) =>
        file.Comments.SelectMany(comment => DocumentationAlso.Of(comment.Sections));

    private static string[] Converted(string folder, string[] files) =>
        [.. files.Select(file => Path.Join(folder, file))];

    private static DocumentationFile Parse(string path) => DocumentationParser.Parse(File.ReadAllText(path), path);
}
