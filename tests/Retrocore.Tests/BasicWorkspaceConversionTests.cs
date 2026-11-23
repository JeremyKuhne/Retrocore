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
        CheckAgainstOverlay(native, legacy, Converted(AppleFolder, s_appleFiles), minimum: 200);
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
        CheckAgainstOverlay(native, legacy, Converted(CommodoreFolder, s_commodoreFiles), minimum: 150);
    }

    /// <summary>
    ///  An old name only one vendor's converted files give resolves in none of the other vendor's builds, and the
    ///  shared layouts give only Microsoft's names.
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

        // The layouts are shared, so each old name there must be Microsoft's, which every build has.
        DocumentationFile layouts = Parse(Path.Join(SharedFolder, LayoutsFile));
        DocumentationAlso[] shared = [.. OldNamesIn(layouts)];
        shared.Select(also => also.Name).Should().BeEquivalentTo(["STRSIZ", "FORSIZ"]);
        foreach (DocumentationAlso also in shared)
        {
            also.Sources.Should().Contain("M6502", $"{also.Name} is on a shared definition");
            foreach (AssemblyResult build in apple.Concat(pet))
            {
                build.Symbol(also.Name).Should().Be(build.Symbol(build.DefinitionName(also.Name)));
            }
        }
    }

    /// <summary>
    ///  Every old name in the converted files cites at least one document, and every document is in the
    ///  bibliography.
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
            foreach (DocumentationAlso also in OldNamesIn(Parse(path)))
            {
                count++;
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

    // Each old name a converted file gives reaches its definition with the overlay's value for that name.
    private static void CheckAgainstOverlay(AssemblyResult native, AssemblyResult legacy, string[] files, int minimum)
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

        compared.Should().BeGreaterThan(minimum, "the converted files rename the overlay's workspace names");
    }

    private static HashSet<string> OldNames(IEnumerable<AssemblyResult> builds, string[] files) =>
        [.. builds.SelectMany(build => build.HistoricalNames)
            .Where(pair => InFiles(pair.Value, files))
            .Select(pair => pair.Key)];

    private static bool InFiles(AssemblySymbol definition, string[] files) =>
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
